#import <UIKit/UIKit.h>
#import <objc/runtime.h>
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

#pragma mark - 长按菜单注入（iOS 13+ 上下文菜单 / UIMenu，适配微信 8.0.71）
// 微信 8.0.71 用 UIContextMenuInteraction + UIMenu 呈现长按菜单（已逆向 WCRefine 2.1-8 确认：dylib 内
// UIContextMenuInteraction/UIMenu 高引用、UIMenuController/UIMenuItem 仅旧系统兜底）。老的
// UIMenuController / filteredMenuItems: / operationMenuItems 在本版本根本不调用，所以之前一直不出现。
// 最稳的注入点：hook UIContextMenuConfiguration 的类工厂 configurationWithIdentifier:previewProvider:
// actionProvider: —— 无论微信把长按菜单的 delegate 放在哪个类（Cell / VC / 私有类），只要它用这个类
// 造配置，我们就能包住 actionProvider，往返回的 UIMenu.children 追加「小丑」UIAction。action 触发时
// 再用「当前活跃的 UIContextMenuInteraction.view」向上回溯到消息 Cell 取 CMessageWrap。
// 保留原生菜单不变（只追加一项），且幂等（已存在则跳过）。
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

#pragma mark - 长按菜单注入 0.2.0：单点、非原地、多级项安全
// 0.1.0 真机日志结论：
//   sig filteredMenuItems: ret=@ enc=@24@0:8@16 / generateOperationMenu ret=@ / operationMenuItems ret=@
//   链路：generateOperationMenu -> filteredMenuItems: -> onShowOperationMenu（MMMenuController setMenuItems: 未调用）
//   菜单项 proto=MMMenuItem；MMMenuItem / MMMultiMenuItem / MMMenuController 均存在。
// 0.1.0 两个问题根因：
//   ① 当数组本身是可变 __NSArrayM 时原地 addObject，改动了微信自己的菜单数组 -> 非文字消息闪退/抖动；
//   ② 多级菜单容器 MMMultiMenuItem 被当普通项克隆 -> 渲染异常。
// 0.2.0 铁律：只在 filteredMenuItems: 单点追加；永远新建 NSMutableArray，绝不改原数组；
//   多级项("Multi")与无法安全克隆的项一律跳过；绝不退回原生 UIMenuItem。

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

// 只克隆「普通单级菜单项」；多级容器(MMMultiMenuItem)或无法安全设置 title/action 的一律返回 nil
static id WCRMakeClownItem(NSArray *existing) {
    if (existing.count == 0) return nil;
    id proto = existing.firstObject;
    if (![proto isKindOfClass:[UIMenuItem class]]) return nil;
    NSString *pcn = NSStringFromClass([proto class]);
    if (pcn && [pcn rangeOfString:@"Multi"].location != NSNotFound) return nil;
    id clone = nil;
    @try { clone = [proto copy]; } @catch (NSException *e) { }
    if (!clone) return nil;
    @try {
        if (![clone respondsToSelector:@selector(setTitle:)] ||
            ![clone respondsToSelector:@selector(setAction:)]) return nil;
        [clone setTitle:@"小丑"];
        [clone setAction:@selector(wcr_clownMenuItemTapped:)];
    } @catch (NSException *e) { return nil; }
    return clone;
}

// 永远新建数组，绝不改动传入的微信内部数组
static id WCRAppendClownToItems(id items) {
    if (![items isKindOfClass:[NSArray class]]) return items;
    NSArray *a = (NSArray *)items;
    if (a.count == 0) return items;
    for (id el in a) {
        @try { if ([[el valueForKey:@"title"] isEqualToString:@"小丑"]) return items; } @catch (NSException *e) { }
    }
    id item = WCRMakeClownItem(a);
    if (!item) {
        WCRLog("entry skip append (protoClass=%@)", a.count ? NSStringFromClass([a.firstObject class]) : @"none");
        return items;
    }
    NSMutableArray *m = [NSMutableArray arrayWithCapacity:a.count + 1];
    [m addObjectsFromArray:a];
    [m addObject:item];
    WCRLog("entry appended 小丑 (%lu -> %lu, proto=%@)",
           (unsigned long)a.count, (unsigned long)m.count,
           NSStringFromClass([a.firstObject class]));
    return m;
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
    Class sup = class_getSuperclass(object_getClass(self));
    IMP imp = sup ? class_getMethodImplementation(sup, _cmd) : NULL;
    if (imp) {
        typedef BOOL (*WCRFn)(id, SEL, SEL, id);
        return ((WCRFn)(void *)imp)(self, _cmd, action, sender);
    }
    return NO;
}
%new
- (void)wcr_clownMenuItemTapped:(id)sender {
    (void)sender;
    id wrap = WCRCellWrap(self, nil);
    NSString *key = wrap ? [WCRClownStore.shared messageKeyForWrap:wrap session:nil] : nil;
    WCRLog("entry 小丑 tapped key=%@", key);
    if (key.length) {
        UIViewController *top = WCRTopController();
        if (top) {
            WCRClownEditorViewController *ed =
                [[WCRClownEditorViewController alloc] initWithMessageKey:key wrap:wrap host:top];
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:ed];
            nav.modalPresentationStyle = UIModalPresentationPageSheet;
            [top presentViewController:nav animated:YES completion:nil];
        }
    }
}
%end

%hook ImageMessageCellView
- (id)operationMenuItems {
    id r = %orig;
    @try {
        WCRLog("entry operationMenuItems fired ret=%c (passthrough)", gWCRImgOpRet ? gWCRImgOpRet : '?');
        if (gWCRImgOpRet == '@' && [r isKindOfClass:[NSArray class]]) r = WCRAppendClownToItems(r);
    } @catch (NSException *e) { WCRLog("entry operationMenuItems exc: %@", e); }
    return r;
}
%end

%hook MMMenuController
- (void)setMenuItems:(id)items {
    (void)items;
    WCRLog("entry MMMenuController setMenuItems fired (passthrough)");
    %orig;
}
%end

%hook UIMenuController
- (void)setMenuItems:(id)items {
    (void)items;
    WCRLog("entry UIMenuController setMenuItems fired (passthrough)");
    %orig;
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
        // 长按菜单（上下文菜单 / UIMenu，适配微信 8.0.71）：hook UIContextMenuConfiguration 工厂，
        // 无论微信把 delegate 放在哪个类都能命中，往 UIMenu 追加「小丑」
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
