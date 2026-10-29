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

#pragma mark - 探针 0.0.9：纯旁路观察微信 8.0.71 真实长按菜单链路（零行为改动）
// 0.0.8 闪退根因：对 generateOperationMenu* 的 %orig 返回值当成 id 解引用，真实返回可能是 void
// -> 垃圾指针 EXC_BAD_ACCESS。本版铁律：**任何 hook 都不解引用 %orig 返回值**，只原样透传；
// 只打印「是否命中」与 setMenuItems: 的入参（入参按契约一定是数组，安全）。
// 绝不追加、绝不覆盖 canPerformAction、绝不加 %new。目的只有一个：真机长按一次，
// 确认到底哪个方法被调用、菜单项是什么类。

static void WCRProbeLogClasses(NSString *tag, id arr) {
    if (!arr) { WCRLog("probe %@ = nil", tag); return; }
    @try {
        if (![arr isKindOfClass:[NSArray class]]) {
            WCRLog("probe %@ not-array class=%@", tag, NSStringFromClass(object_getClass(arr)));
            return;
        }
        NSArray *a = (NSArray *)arr;
        WCRLog("probe %@ count=%lu", tag, (unsigned long)a.count);
        NSUInteger i = 0;
        for (id el in a) {
            if (i >= 8) { WCRLog("   probe %@ ...(more)", tag); break; }
            WCRLog("   probe %@ [%lu] class=%@", tag, (unsigned long)i, NSStringFromClass(object_getClass(el)));
            i++;
        }
    } @catch (NSException *e) {
        WCRLog("probe %@ inspect exception: %@", tag, e);
    }
}

// 只 dump 类自身方法（不遍历父类，避免 UIView 分类方法刷屏）
static void WCRProbeDumpOwn(Class cls, NSString *label, BOOL filterMenu) {
    if (!cls) { WCRLog("api %@: MISSING", label); return; }
    unsigned n = 0;
    Method *ms = class_copyMethodList(cls, &n);
    WCRLog("api %@ ownInstanceMethods=%u", label, n);
    for (unsigned i = 0; i < n; i++) {
        const char *nm = sel_getName(method_getName(ms[i]));
        NSString *ns = [NSString stringWithUTF8String:(nm ? nm : "")] ?: @"";
        if (filterMenu) {
            NSString *lower = ns.lowercaseString;
            if (!([lower containsString:@"menu"] || [lower containsString:@"operation"] ||
                  [lower containsString:@"filtered"] || [lower containsString:@"item"])) continue;
        }
        WCRLog("api %@ -%s %s", label, nm, method_getTypeEncoding(ms[i]));
    }
    if (ms) free(ms);
    Class meta = object_getClass(cls);
    unsigned mn = 0;
    Method *mms = meta ? class_copyMethodList(meta, &mn) : NULL;
    for (unsigned i = 0; i < mn; i++) {
        const char *nm = sel_getName(method_getName(mms[i]));
        NSString *ns = [NSString stringWithUTF8String:(nm ? nm : "")] ?: @"";
        if (filterMenu) {
            NSString *lower = ns.lowercaseString;
            if (!([lower containsString:@"menu"] || [lower containsString:@"item"])) continue;
        }
        WCRLog("api %@ +%s %s", label, nm, method_getTypeEncoding(mms[i]));
    }
    if (mms) free(mms);
}

%group WCRProbe
%hook BaseMessageCellView
- (id)filteredMenuItems:(id)arg {
    id r = %orig;
    WCRLog("probe filteredMenuItems fired argClass=%@",
           arg ? NSStringFromClass(object_getClass(arg)) : @"nil");
    return r;   // 原样透传，不解引用、不追加
}
- (id)generateOperationMenu {
    id r = %orig;
    WCRLog("probe generateOperationMenu fired");
    return r;   // 原样透传
}
- (id)generateOperationMenuForRecordDetail {
    id r = %orig;
    WCRLog("probe generateOperationMenuForRecordDetail fired");
    return r;
}
- (void)showOperationMenu {
    WCRLog("probe showOperationMenu fired");
    %orig;
}
- (void)onShowOperationMenu {
    WCRLog("probe onShowOperationMenu fired");
    %orig;
}
%end

%hook ImageMessageCellView
- (id)operationMenuItems {
    id r = %orig;
    WCRLog("probe operationMenuItems fired");
    return r;
}
%end

%hook MMMenuController
- (void)setMenuItems:(id)items {
    WCRLog("probe MMMenuController setMenuItems fired");
    WCRProbeLogClasses(@"MMMenuController.items", items);
    %orig;
}
%end

%hook UIMenuController
- (void)setMenuItems:(id)items {
    WCRLog("probe UIMenuController setMenuItems fired");
    WCRProbeLogClasses(@"UIMenuController.items", items);
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
        // 探针 0.0.9：只读确认类存在 + 自身方法（不遍历父类、不打 description），挂纯旁路观察 hook
        if (NSClassFromString(@"BaseMessageCellView")) {
            WCRLog("=== probe 0.0.9 begin ===");
            for (NSString *cn in @[@"MMMenuItem", @"MMMultiMenuItem", @"MMMenuController",
                                   @"MMMenuContentView", @"UIMenuItem", @"UIMenuController"]) {
                WCRLog("probe class %@ exists=%d", cn, NSClassFromString(cn) ? 1 : 0);
            }
            WCRProbeDumpOwn(NSClassFromString(@"BaseMessageCellView"), @"BaseMessageCellView", YES);
            WCRProbeDumpOwn(NSClassFromString(@"MMMenuItem"), @"MMMenuItem", NO);
            WCRProbeDumpOwn(NSClassFromString(@"MMMenuController"), @"MMMenuController", NO);
            WCRLog("=== probe 0.0.9 end ===");
            %init(WCRProbe);
        }
        if (objc_getClass("BaseMsgContentViewController")) %init(WCRReload);
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillTerminateNotification object:nil queue:nil usingBlock:^(__unused NSNotification *note) {
            [[WCRClownStore shared] clearAll];
        }];
    }
}
