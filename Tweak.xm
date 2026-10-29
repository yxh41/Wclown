#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "WCRClownConfig.h"
#import "WCRClownStore.h"
#import "WCRClownRuntime.h"
#import "WCRClownEntryInstaller.h"
#import "WCRClownPanel.h"
#import "WCRClownEntry.h"
#import "WCRClownLog.h"
#import "WCRClownEditor.h"

// 非 static 且显式 default visibility：面板要引用它显示实际构建版本，便于核对是否装错包。
// 注意：下方定义行是本文件唯一的版本注入点（build.yml 会改这一行的版本号），请勿在别处
// 复制该声明，也不要在本文件其它位置写入同名变量名加等号的格式，以免 sed 注入错位。
__attribute__((visibility("default"))) const char kWCRClownBuildTag[] = "wcrclown-0.0.4-ctxmenu";

// 从 Cell 取 CMessageWrap：先试 messageWrap，再试 viewModel.messageWrap，否则把 vm 当 wrap
static id WCRCellWrap(id cell, id vm) {
    if (!cell && !vm) return nil;
    id wrap = WCRSafeCall0(cell, NSSelectorFromString(@"messageWrap"));
    if (wrap) return wrap;
    id viewModel = vm ?: WCRSafeCall0(cell, NSSelectorFromString(@"viewModel"));
    if (viewModel) {
        id w2 = WCRSafeCall0(viewModel, NSSelectorFromString(@"messageWrap"));
        if (w2) return w2;
    }
    return vm;
}

// iOS 16 取前台 window 的 rootViewController（避免 UIApplication.keyWindow 废弃）
static UIViewController *WCRTopController(void) {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]] &&
            ((UIWindowScene *)scene).activationState == UISceneActivationStateForegroundActive) {
            window = ((UIWindowScene *)scene).keyWindow;
            break;
        }
    }
    UIViewController *rc = window.rootViewController;
    while (rc.presentedViewController) rc = rc.presentedViewController;
    return rc;
}

// 诊断：记录候选类/selector 存在性（不改数据）
static void WCRLogCompatibility(void) {
    NSArray<NSArray<NSString *> *> *candidates = @[
        @[@"BaseMessageCellView", @"filteredMenuItems:"],
        @[@"BaseMessageCellView", @"showOperationMenu"],
        @[@"BaseMessageCellView", @"onShowOperationMenu"],
        @[@"ImageMessageCellView", @"operationMenuItems"],
        @[@"ImageMessageCellView", @"setViewModel:"],
        @[@"BaseMessageCellView", @"setViewModel:"],
        @[@"BaseMessageCellView", @"initWithViewModel:"],
        @[@"ChatTimeCellView", @"setViewModel:"],
        @[@"ChatTimeCellView", @"initWithViewModel:"],
        @[@"ChatTimeViewModel", @"measure:"],
        @[@"CMessageWrap", @"m_nsContent"],
        @[@"CMessageWrap", @"m_uiCreateTime"],
        @[@"CMessageWrap", @"m_uiIsSenderStatus"],
        @[@"CMessageWrap", @"m_oWCPayInfoItem"],
        @[@"BaseMsgContentViewController", @"viewWillDisappear:"],
        @[@"BaseMsgContentViewController", @"viewDidDisappear:"],
        @[@"BaseMsgContentViewController", @"viewWillBePoped:"],
        @[@"UILabel", @"setText:"],
        @[@"UILabel", @"setAttributedText:"]
    ];
    for (NSArray<NSString *> *entry in candidates) {
        WCRLog("compat %@ %@: %@", entry[0], entry[1], WCRClassAndSelectorAvailable(entry[0], entry[1]) ? @"available" : @"missing");
    }
}

#pragma mark - 应用覆盖到消息渲染（在 hook 前改数据，让 Cell 渲染读到覆盖）
%group WCRApply
%hook BaseMessageCellView
- (void)setViewModel:(id)vm {
    @try {
        if ([WCRClownConfig shared].enabled) {
            id wrap = WCRCellWrap(self, vm);
            if (wrap) [WCRClownRuntime applyOverridesToMessage:wrap session:nil];
        }
    } @catch (NSException *e) {
        WCRLog("apply exception: %@", e);
    }
    %orig;
}
%end
%end

#pragma mark - 长按菜单注入（UIContextMenuConfiguration 路径，8.0.71 实测不走，仅旧版本/其他 App 兼容）
// ⚠️ 实测结论（微信 8.0.71）：UIContextMenuConfiguration 工厂**从不触发**（日志无 ctx factory called），
// 本版本长按菜单走微信自制的 MMMenuController + 菜单项数组，注入点在 WCREntry 组。
// 以下 WCRMenuCtx 仅作为其它微信版本 / 其它 App 的兼容兜底，保留不代表 8.0.71 会命中。
static id WCRFindCellWrap(UIView *fromView) {
    UIView *v = fromView;
    while (v) {
        if ([v respondsToSelector:NSSelectorFromString(@"messageWrap")] ||
            [v respondsToSelector:NSSelectorFromString(@"viewModel")]) {
            return WCRCellWrap(v, nil);
        }
        v = v.superview;
    }
    return nil;
}

// 找到当前正在显示的上下文菜单所依附的 view（即被长按的 Cell 或其内容视图）
static UIView *WCRActiveContextMenuView(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            for (id inter in w.interactions) {
                if ([inter isKindOfClass:[UIContextMenuInteraction class]]) {
                    UIView *v = [inter view];
                    if (v) return v;
                }
            }
        }
    }
    return nil;
}

// 把「小丑」UIAction 追加进微信原生长按菜单（幂等：已存在则跳过）
static UIMenu *WCRMenuAppendClown(UIMenu *origMenu) {
    NSMutableArray *kids = [NSMutableArray arrayWithArray:origMenu.children ?: @[]];
    BOOL has = NO;
    for (id el in kids) {
        if ([el isKindOfClass:[UIAction class]] && [[el title] isEqualToString:@"小丑"]) { has = YES; break; }
    }
    if (!has) {
        UIAction *clown = [UIAction actionWithTitle:@"小丑" image:nil identifier:@"wcr.clown"
            handler:^(__kindof UIAction *action) {
                UIView *cv = WCRActiveContextMenuView();
                id wrap = cv ? WCRFindCellWrap(cv) : nil;
                NSString *key = wrap ? [WCRClownStore.shared messageKeyForWrap:wrap session:nil] : nil;
                WCRLog("ctx action tapped key=%@ cv=%@", key, cv ? NSStringFromClass(object_getClass(cv)) : @"nil");
                if (key.length) {
                    UIViewController *top = WCRTopController();
                    if (top) {
                        WCRClownEditorViewController *ed =
                            [[WCRClownEditorViewController alloc] initWithMessageKey:key wrap:wrap host:top];
                        UINavigationController *nav =
                            [[UINavigationController alloc] initWithRootViewController:ed];
                        nav.modalPresentationStyle = UIModalPresentationPageSheet;
                        [top presentViewController:nav animated:YES completion:nil];
                    }
                }
            }];
        [kids addObject:clown];
    }
    return [UIMenu menuWithTitle:origMenu.title ?: @"" children:kids];
}

// 包住微信的 actionProvider：把「小丑」UIAction 追加进微信原生 UIMenu。
// ⚠️ 致命递归修复：早期版本在 factory hook 内又调 [UIContextMenuConfiguration
// configurationWithIdentifier:...] 新建配置，会**递归进入本 hook** → 长按即栈溢出崩溃；
// 之前没爆是因为 menuEntryEnabled 被旧版持久化成 0、这段代码是死代码，一旦开入口首次长按就崩。
// 正确做法：把包好的 provider 直接传给 %orig（原始工厂/原始 init 实现），绝不再次调用被 hook 的构造器。
// 同时 hook 工厂 + init 两条构造路径（init 是 designated initializer，工厂内部也调 init），最稳；
// 用 id 捕获 + elements 透传兼容 iOS16 新签名 (NSArray<UIMenuElement*>*) -> UIMenu。
static UIMenu *WCRInvokeOrigProvider(id origProvider, id elements) {
    UIMenu *origMenu = nil;
    if (origProvider) {
        UIMenu *(^prov)(id) = origProvider;
        @try { origMenu = prov(elements); } @catch (NSException *e) { WCRLog("ctx provider exc: %@", e); }
    }
    return WCRMenuAppendClown(origMenu);
}

%group WCRMenuCtx
%hook UIContextMenuConfiguration
+ (UIContextMenuConfiguration *)configurationWithIdentifier:(id)identifier previewProvider:(id)previewProvider actionProvider:(id)actionProvider {
    BOOL on = [WCRClownConfig shared].menuEntryEnabled;
    WCRLog("ctx factory called id=%@ menuEntry=%d ap=%d", identifier, on, actionProvider?1:0);
    if (on && actionProvider) {
        WCRLog("ctxConfig factory fired id=%@", identifier);
        id wrapped = ^UIMenu *(NSArray<UIMenuElement *> *elements) {
            return WCRInvokeOrigProvider(actionProvider, elements);
        };
        return %orig(identifier, previewProvider, wrapped);
    }
    return %orig(identifier, previewProvider, actionProvider);
}
- (instancetype)initWithIdentifier:(id)identifier previewProvider:(id)previewProvider actionProvider:(id)actionProvider {
    BOOL on = [WCRClownConfig shared].menuEntryEnabled;
    WCRLog("ctx init called id=%@ menuEntry=%d ap=%d", identifier, on, actionProvider?1:0);
    if (on && actionProvider) {
        WCRLog("ctxConfig init fired id=%@", identifier);
        id wrapped = ^UIMenu *(NSArray<UIMenuElement *> *elements) {
            return WCRInvokeOrigProvider(actionProvider, elements);
        };
        return %orig(identifier, previewProvider, wrapped);
    }
    return %orig(identifier, previewProvider, actionProvider);
}
%end
%end

#pragma mark - 长按菜单注入 0.3.0：MMMenuItem 克隆 + 安全 canPerformAction + 延迟弹出编辑器
// 0.2.0 日志结论：
//   ① protoClass=MMMenuItem 但 skip append -> MMMenuItem 不是 UIMenuItem 子类（0.2.0 的 isKindOfClass 判断误杀）；
//   ② MMMenuController -setMenuItems: 确实被调用；链路 generateOperationMenu -> filteredMenuItems: -> setMenuItems: -> onShowOperationMenu；
//   ③ 点「小丑」有 key 但编辑器没弹出 -> 在菜单收起动画中 present 被吞；
//   ④ 0.2.0 未加任何项仍闪退 -> canPerformAction 里手工 class_getMethodImplementation(super,_cmd) 可能拿到
//      _objc_msgForward，直接调用必崩。
// 0.3.0：允许任意可 copy + setAction 的菜单项（含 MMMenuItem）；canPerformAction 走 objc_msgSendSuper；
//   点击后延迟 0.45s 再 present，并带完整日志。

static char gWCRFilteredRet = 0;
static char gWCRGenRet = 0;
static char gWCRImgOpRet = 0;
static NSString *gWCRFilteredEnc = nil;
static NSString *gWCRGenEnc = nil;
static NSString *gWCRImgOpEnc = nil;

static void WCRProbeSignatures(void) {
    Class c = NSClassFromString(@"BaseMessageCellView");
    if (c) {
        Method m = class_getInstanceMethod(c, @selector(filteredMenuItems:));
        if (m) {
            char b[32] = {0};
            method_getReturnType(m, b, sizeof(b));
            gWCRFilteredRet = b[0];
            gWCRFilteredEnc = [NSString stringWithUTF8String:method_getTypeEncoding(m)];
        }
        Method g = class_getInstanceMethod(c, @selector(generateOperationMenu));
        if (g) {
            char b[32] = {0};
            method_getReturnType(g, b, sizeof(b));
            gWCRGenRet = b[0];
            gWCRGenEnc = [NSString stringWithUTF8String:method_getTypeEncoding(g)];
        }
    }
    Class ic = NSClassFromString(@"ImageMessageCellView");
    if (ic) {
        Method o = class_getInstanceMethod(ic, @selector(operationMenuItems));
        if (o) {
            char b[32] = {0};
            method_getReturnType(o, b, sizeof(b));
            gWCRImgOpRet = b[0];
            gWCRImgOpEnc = [NSString stringWithUTF8String:method_getTypeEncoding(o)];
        }
    }
    WCRLog("sig filteredMenuItems: ret=%c enc=%@", gWCRFilteredRet ? gWCRFilteredRet : '?', gWCRFilteredEnc ?: @"nil");
    WCRLog("sig generateOperationMenu ret=%c enc=%@", gWCRGenRet ? gWCRGenRet : '?', gWCRGenEnc ?: @"nil");
    WCRLog("sig operationMenuItems ret=%c enc=%@", gWCRImgOpRet ? gWCRImgOpRet : '?', gWCRImgOpEnc ?: @"nil");
}

// 构造「小丑」菜单项：优先克隆微信原生 MMMenuItem（保留私有字段），失败则退回系统 UIMenuItem。
// ⚠️ 历史坑：0.2.0/0.3.0 用 `respondsToSelector:@selector(setAction:)` 当硬门槛，把 MMMenuItem 全卡掉
// （MMMenuItem 的 action 是 KVC-only 或类簇 copy 返回不同子类，运行期 respondsToSelector 返回 NO），
// 导致小丑完全不出现。0.1.0 实测微信 8.0.71 接受 UIMenuItem，故保留 UIMenuItem 兜底——这是关键。
static id WCRMakeClownItem(NSArray *existing) {
    SEL act = @selector(wcr_clownMenuItemTapped:);
    id proto = existing.count ? existing.firstObject : nil;
    if (proto) {
        NSString *pcn = NSStringFromClass([proto class]);
        // 多级菜单容器（MMMultiMenuItem 等）：不在克隆层处理，直接退回 UIMenuItem（更安全）
        if (pcn && [pcn rangeOfString:@"Multi"].location != NSNotFound) {
            return [[UIMenuItem alloc] initWithTitle:@"小丑" action:act];
        }
        id clone = nil;
        @try { if ([proto respondsToSelector:@selector(copy)]) clone = [proto copy]; } @catch (NSException *e) { }
        if (clone) {
            @try {
                if ([clone respondsToSelector:@selector(setTitle:)]) [clone setTitle:@"小丑"];
                else @try { [clone setValue:@"小丑" forKey:@"title"]; } @catch (NSException *e) { }
                if ([clone respondsToSelector:@selector(setAction:)]) {
                    [clone setAction:act];
                    return clone;
                }
                // 不响应 setAction: 也不强求，克隆层放弃，落到下方 UIMenuItem 兜底
            } @catch (NSException *e) {
                WCRLog("entry clone kvc failed: %@", e);
            }
        }
        // 克隆失败 -> 同类型 initWithTitle:action:
        Class cls = [proto class];
        if ([cls instancesRespondToSelector:@selector(initWithTitle:action:)]) {
            @try { return [[cls alloc] initWithTitle:@"小丑" action:act]; } @catch (NSException *e) { }
        }
    }
    return [[UIMenuItem alloc] initWithTitle:@"小丑" action:act];
}

// 永远新建数组，绝不改动传入的微信内部数组；幂等：已含「小丑」则原样返回
static id WCRAppendClownToItems(id items) {
    if (![items isKindOfClass:[NSArray class]]) return items;
    NSArray *a = (NSArray *)items;
    if (a.count == 0) return items;
    for (id el in a) {
        @try { if ([[el valueForKey:@"title"] isEqualToString:@"小丑"]) return items; } @catch (NSException *e) { }
    }
    id item = nil;
    @try { item = WCRMakeClownItem(a); } @catch (NSException *e) { WCRLog("entry make item failed: %@", e); }
    if (!item) {
        WCRLog("entry skip append (protoClass=%@)", a.count ? NSStringFromClass([a.firstObject class]) : @"none");
        return items;
    }
    NSMutableArray *m = [NSMutableArray arrayWithCapacity:a.count + 1];
    [m addObjectsFromArray:a];
    [m addObject:item];
    WCRLog("entry appended 小丑 (%lu -> %lu, proto=%@, item=%@)",
           (unsigned long)a.count, (unsigned long)m.count,
           a.count ? NSStringFromClass([a.firstObject class]) : @"none",
           NSStringFromClass([item class]));
    return m;
}

// 取最上层可用 presenter（遍历前台 scene 的 window，再沿 presented 链走到最顶）
static UIViewController *WCRPresenterVC(void) {
    UIWindow *keyWin = nil;
    for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
        if (![sc isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)sc;
        if (ws.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *w in ws.windows) { if (w.isKeyWindow) { keyWin = w; break; } }
        if (!keyWin) keyWin = ws.windows.firstObject;
        if (keyWin) break;
    }
    if (!keyWin) {
        for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
            if ([sc isKindOfClass:[UIWindowScene class]]) {
                keyWin = ((UIWindowScene *)sc).windows.firstObject;
                break;
            }
        }
    }
    UIViewController *vc = keyWin.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

%group WCREntry
%hook BaseMessageCellView
- (id)filteredMenuItems:(id)arg {
    id r = %orig;
    @try {
        WCRLog("entry filteredMenuItems fired arg=%@ ret=%c",
               arg ? NSStringFromClass(object_getClass(arg)) : @"nil", gWCRFilteredRet ? gWCRFilteredRet : '?');
        if (gWCRFilteredRet == '@' && [r isKindOfClass:[NSArray class]]) r = WCRAppendClownToItems(r);
    } @catch (NSException *e) { WCRLog("entry filteredMenuItems exc: %@", e); }
    return r;
}
- (id)generateOperationMenu {
    id r = %orig;
    @try { WCRLog("entry generateOperationMenu fired ret=%c (passthrough)", gWCRGenRet ? gWCRGenRet : '?'); }
    @catch (NSException *e) { }
    return r;
}
- (id)generateOperationMenuForRecordDetail {
    return %orig;
}
- (id)showOperationMenu {
    id r = %orig;
    WCRLog("entry showOperationMenu fired");
    return r;
}
- (id)onShowOperationMenu {
    id r = %orig;
    WCRLog("entry onShowOperationMenu fired");
    return r;
}
- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    if (sel_isEqual(action, @selector(wcr_clownMenuItemTapped:))) return YES;
    struct objc_super sup = { self, class_getSuperclass(object_getClass(self)) };
    if (!sup.super_class) return NO;
    return ((BOOL (*)(struct objc_super *, SEL, SEL, id))objc_msgSendSuper)(&sup, _cmd, action, sender);
}
%new
- (void)wcr_clownMenuItemTapped:(id)sender {
    (void)sender;
    id wrap = WCRCellWrap(self, nil);
    NSString *key = wrap ? [WCRClownStore.shared messageKeyForWrap:wrap session:nil] : nil;
    WCRLog("entry 小丑 tapped key=%@ wrap=%@", key, wrap ? NSStringFromClass([wrap class]) : @"nil");
    if (!key.length) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
            UIViewController *top = WCRPresenterVC();
            WCRLog("entry presenting editor top=%@", top ? NSStringFromClass([top class]) : @"nil");
            if (!top) return;
            WCRClownEditorViewController *ed =
                [[WCRClownEditorViewController alloc] initWithMessageKey:key wrap:wrap host:top];
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:ed];
            nav.modalPresentationStyle = UIModalPresentationPageSheet;
            [top presentViewController:nav animated:YES completion:^{
                WCRLog("entry editor presented");
            }];
        } @catch (NSException *e) {
            WCRLog("entry present editor exc: %@", e);
        }
    });
}
%end

%hook ImageMessageCellView
- (id)operationMenuItems {
    id r = %orig;
    @try {
        WCRLog("entry operationMenuItems fired ret=%c", gWCRImgOpRet ? gWCRImgOpRet : '?');
        if (gWCRImgOpRet == '@' && [r isKindOfClass:[NSArray class]]) r = WCRAppendClownToItems(r);
    } @catch (NSException *e) { WCRLog("entry operationMenuItems exc: %@", e); }
    return r;
}
%end

%hook MMMenuController
- (void)setMenuItems:(id)items {
    id aug = items;
    @try {
        WCRLog("entry MMMenuController setMenuItems fired (sink)");
        if ([items isKindOfClass:[NSArray class]]) aug = WCRAppendClownToItems(items);
    } @catch (NSException *e) { WCRLog("entry MMMenuController setMenuItems exc: %@", e); }
    %orig(aug);
}
%end

%hook UIMenuController
- (void)setMenuItems:(id)items {
    id aug = items;
    @try {
        WCRLog("entry UIMenuController setMenuItems fired (sink)");
        if ([items isKindOfClass:[NSArray class]]) aug = WCRAppendClownToItems(items);
    } @catch (NSException *e) { WCRLog("entry UIMenuController setMenuItems exc: %@", e); }
    %orig(aug);
}
%end
%end

#pragma mark - 会话实时刷新（编辑保存后重载列表）
%group WCRReload
%hook BaseMsgContentViewController
%new
- (void)wcr_reloadChat {
    @try {
        id tv = WCRSafeCall0(self, NSSelectorFromString(@"tableView"));
        if (!tv) tv = WCRSafeCall0(self, NSSelectorFromString(@"m_tableView"));
        if (tv) WCRSafeCall0(tv, NSSelectorFromString(@"reloadData"));
    } @catch (NSException *e) {
        WCRLog("reload exception: %@", e);
    }
}
%end
%end

%ctor {
    @autoreleasepool {
        [WCRClownStore shared];
        [WCRClownEntryInstaller installIfSupported];
        WCRLog("loaded build %s", kWCRClownBuildTag);
        if ([WCRClownConfig shared].diagnosticHooksEnabled) WCRLogCompatibility();
        // 悬浮入口：纯 UIKit overlay，不依赖微信任何私有类，也不会往微信数据结构注入对象
        [WCRClownEntry installIfNeeded];
        if (WCRClassAndSelectorAvailable(@"BaseMessageCellView", @"setViewModel:")) %init(WCRApply);
        // 长按菜单：WCRMenuCtx(UIContextMenuConfiguration) 是旧系统兜底，8.0.71 实测不走这条（工厂从不触发）；
        // 真正的注入在 WCREntry 组（MMMenuController / filteredMenuItems: / operationMenuItems）。保留 WCRMenuCtx
        // 仅作其他微信版本的兼容，不影响 8.0.71。
        if (NSClassFromString(@"UIContextMenuConfiguration")) %init(WCRMenuCtx);
        // 长按菜单注入 0.1.0：先读真实返回类型（决定能否安全触碰返回值），再挂注入 hook
        if (NSClassFromString(@"BaseMessageCellView")) {
            WCRProbeSignatures();
            for (NSString *cn in @[@"MMMenuItem", @"MMMultiMenuItem", @"MMMenuController", @"UIMenuItem"]) {
                WCRLog("entry class %@ exists=%d", cn, NSClassFromString(cn) ? 1 : 0);
            }
            %init(WCREntry);
        }
        if (objc_getClass("BaseMsgContentViewController")) %init(WCRReload);
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillTerminateNotification object:nil queue:nil usingBlock:^(__unused NSNotification *note) {
            [[WCRClownStore shared] clearAll];
        }];
    }
}
