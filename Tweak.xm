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
__attribute__((visibility("default"))) const char kWCRClownBuildTag[] = "wcrclown-0.0.3-menufix";

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

#pragma mark - 长按菜单加入「小丑」条目
// 真正的注入点：微信长按消息时调用 Cell 的菜单数组构造方法（filteredMenuItems: / operationMenuItems），
// 把 UIMenuItem 混入返回数组即可随原生菜单一起出现。全局 [UIMenuController menuItems] 注册会被微信
// 显示前重置覆盖（实测无效），必须在此处注入。
// 安全护栏：仅当数组为空或元素均为 UIMenuItem 时才混入，避免把 UIMenuItem 塞进微信自有菜单项类导致
// unrecognized selector 闪退（这是早期版本 menuEntryEnabled 默认关闭的原因）。
static NSArray *WCRAppendClownMenuItem(NSArray *orig) {
    NSMutableArray *items = [NSMutableArray arrayWithArray:orig ?: @[]];
    BOOL safe = (items.count == 0);
    if (!safe) {
        safe = YES;
        for (id it in items) { if (![it isKindOfClass:[UIMenuItem class]]) { safe = NO; break; } }
    }
    if (!safe) { WCRLog("menu array element not UIMenuItem, skip inject (cnt=%lu)", (unsigned long)items.count); return orig; }
    BOOL has = NO;
    for (UIMenuItem *it in items) { if ([[it title] isEqualToString:@"小丑"]) { has = YES; break; } }
    if (!has) {
        UIMenuItem *item = [[UIMenuItem alloc] initWithTitle:@"小丑" action:@selector(wcr_clownMenuTapped:)];
        [items addObject:item];
    }
    return items;
}

// 记录当前长按的 Cell，作为兜底：若 action 落到聊天 VC 而非 Cell，也能据此定位消息
static __weak id gWCRClownPendingCell = nil;

#pragma mark Cell 级：canPerformAction 门控 + 菜单数组注入 + action
%group WCRMenuCells
%hook BaseMessageCellView
- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    if (action == @selector(wcr_clownMenuTapped:) && [WCRClownConfig shared].menuEntryEnabled) {
        return YES;
    }
    return %orig;
}

%new
- (void)wcr_clownMenuTapped:(id)sender {
    @try {
        gWCRClownPendingCell = self;
        id wrap = WCRCellWrap(self, nil);
        NSString *key = wrap ? [WCRClownStore.shared messageKeyForWrap:wrap session:nil] : nil;
        WCRLog("cell menu tapped key=%@", key);
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
    } @catch (NSException *e) {
        WCRLog("cell menu tap exception: %@", e);
    }
}
%end
%end

#pragma mark 注入点 A：BaseMessageCellView -filteredMenuItems:（文字/通用 Cell）
%group WCRMenuFiltered
%hook BaseMessageCellView
- (NSArray *)filteredMenuItems:(id)arg {
    NSArray *orig = %orig(arg);
    if ([WCRClownConfig shared].menuEntryEnabled) {
        gWCRClownPendingCell = self;
        WCRLog("filteredMenuItems fired cls=%@ cnt=%lu", NSStringFromClass([self class]), (unsigned long)(orig.count));
        return WCRAppendClownMenuItem(orig);
    }
    return orig;
}
%end
%end

#pragma mark 注入点 B：ImageMessageCellView -operationMenuItems（图片 Cell，部分版本走此路）
%group WCRMenuOperation
%hook ImageMessageCellView
- (NSArray *)operationMenuItems {
    NSArray *orig = %orig;
    if ([WCRClownConfig shared].menuEntryEnabled) {
        gWCRClownPendingCell = self;
        WCRLog("operationMenuItems fired cls=%@ cnt=%lu", NSStringFromClass([self class]), (unsigned long)(orig.count));
        return WCRAppendClownMenuItem(orig);
    }
    return orig;
}
%end
%end

#pragma mark 兜底：action 可能落在聊天 VC 而非 Cell（responder chain）
%group WCRMenuVC
%hook BaseMsgContentViewController
- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    if (action == @selector(wcr_clownMenuTapped:) && [WCRClownConfig shared].menuEntryEnabled) return YES;
    return %orig;
}

%new
- (void)wcr_clownMenuTapped:(id)sender {
    @try {
        id cell = gWCRClownPendingCell;
        id wrap = cell ? WCRCellWrap(cell, nil) : nil;
        if (!wrap && cell) wrap = WCRSafeCall0(cell, NSSelectorFromString(@"messageWrap"));
        NSString *key = wrap ? [WCRClownStore.shared messageKeyForWrap:wrap session:nil] : nil;
        WCRLog("vc menu tapped key=%@", key);
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
    } @catch (NSException *e) {
        WCRLog("vc menu tap exception: %@", e);
    }
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
        // 长按菜单：canPerformAction 门控 + action 始终挂在 Cell 上（安全，canPerformAction 存在于 UIResponder）
        if (NSClassFromString(@"BaseMessageCellView")) %init(WCRMenuCells);
        // 注入点 A：仅当微信本版本确有 filteredMenuItems: 才挂（不存在则跳过，避免 hook 空方法）
        if (WCRClassAndSelectorAvailable(@"BaseMessageCellView", @"filteredMenuItems:")) %init(WCRMenuFiltered);
        // 注入点 B：图片 Cell 专用菜单数组（部分版本走此路）
        if (WCRClassAndSelectorAvailable(@"ImageMessageCellView", @"operationMenuItems")) %init(WCRMenuOperation);
        // 兜底 responder
        if (objc_getClass("BaseMsgContentViewController")) %init(WCRMenuVC);
        if (objc_getClass("BaseMsgContentViewController")) %init(WCRReload);
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillTerminateNotification object:nil queue:nil usingBlock:^(__unused NSNotification *note) {
            [[WCRClownStore shared] clearAll];
        }];
    }
}
