#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "WCRClownConfig.h"
#import "WCRClownStore.h"
#import "WCRClownRuntime.h"
#import "WCRClownEntryInstaller.h"
#import "WCRClownPanel.h"

// 非 static：面板要 extern 引用它显示实际构建版本（build.yml 的 sed 仍匹配 kWCRClownBuildTag[] = "）
const char kWCRClownBuildTag[] = "wcrclown-0.0.2-diag";
#define WCRLog(fmt, ...) NSLog(@"[WCRClown] " fmt, ##__VA_ARGS__)

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

// 菜单点击 IMP（通过 class_addMethod 注入到 Cell 类）：打开微信内设置面板
static void WCRClownMenuHandler(id self, SEL _cmd, id sender) {
    @try {
        id wrap = WCRCellWrap(self, nil);
        NSString *key = wrap ? [WCRClownStore.shared messageKeyForWrap:wrap session:nil] : nil;
        WCRLog("menu tapped key=%@", key);
        dispatch_async(dispatch_get_main_queue(), ^{
            [WCRClownPanelController presentFrom:WCRTopController()];
        });
    } @catch (NSException *e) {
        WCRLog("menu handler exception: %@", e);
    }
}

static void WCRInstallClownMenuSelectorIfNeeded(Class cls) {
    SEL sel = @selector(wcr_clownMenuTapped:);
    if (cls && !class_getInstanceMethod(cls, sel)) {
        class_addMethod(cls, sel, (IMP)WCRClownMenuHandler, "v@:@");
    }
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

#pragma mark - 长按菜单注入「小丑」条目（骨架：点击仅做诊断）
%group WCRMenu
%hook BaseMessageCellView
- (id)filteredMenuItems:(id)arg {
    id items = %orig;
    @try {
        // 始终注入「小丑」：开关全部在此面板内调整。若按 enabled/子开关条件显示，
        // 默认全关时会永远摸不到入口（鸡生蛋死锁），这是之前"动不了"的根因之一。
        WCRInstallClownMenuSelectorIfNeeded(object_getClass(self));
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        UIMenuItem *item = [[UIMenuItem alloc] initWithTitle:@"小丑" action:@selector(wcr_clownMenuTapped:)];
#pragma clang diagnostic pop
        if ([items isKindOfClass:NSArray.class]) items = [items arrayByAddingObject:item];
        else if (items) items = @[items, item];
        else items = @[item];
    } @catch (NSException *e) {
        WCRLog("menu exception: %@", e);
    }
    return items;
}
- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    if (action == @selector(wcr_clownMenuTapped:)) return YES;
    return %orig;
}
%end
%end

%ctor {
    @autoreleasepool {
        [WCRClownStore shared];
        [WCRClownEntryInstaller installIfSupported];
        WCRLog("loaded build %s", kWCRClownBuildTag);
        if ([WCRClownConfig shared].diagnosticHooksEnabled) WCRLogCompatibility();
        if (WCRClassAndSelectorAvailable(@"BaseMessageCellView", @"setViewModel:")) %init(WCRApply);
        if (WCRClassAndSelectorAvailable(@"BaseMessageCellView", @"filteredMenuItems:")) %init(WCRMenu);
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillTerminateNotification object:nil queue:nil usingBlock:^(__unused NSNotification *note) {
            [[WCRClownStore shared] clearAll];
        }];
    }
}
