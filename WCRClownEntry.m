#import "WCRClownEntry.h"
#import "WCRClownConfig.h"
#import "WCRClownPanel.h"
#import "WCRClownLog.h"

static UIWindow *gEntryWindow = nil;
// App 主窗口的弱引用：必须在创建自己的 overlay 之前捕获。
// 否则后续 scene.keyWindow 可能指回我们的小 overlay 窗口，导致面板被 present 进
// 46x46 的窗口里，屏幕上只剩一个白色小方块。
static __weak UIWindow *gHostWindow = nil;
static BOOL gOriginKnown = NO;
static CGPoint gEntryOrigin = {0, 0};

@implementation WCRClownEntry

+ (nullable UIWindowScene *)activeScene {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive &&
            [scene isKindOfClass:UIWindowScene.class]) {
            return (UIWindowScene *)scene;
        }
    }
    return nil;
}

+ (void)installIfNeeded {
    if (![WCRClownConfig shared].floatingEntryEnabled) return;
    // 关键：tweak 在 %ctor 加载时通常还没有 foreground-active scene，只试一次会永远
    // 建不出 window（表现＝看不到悬浮按钮）。改为注册「每次回到前台都重试」，幂等。
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                         object:nil
                                                          queue:NSOperationQueue.mainQueue
                                                     usingBlock:^(__unused NSNotification *note) {
            if (![WCRClownConfig shared].floatingEntryEnabled) return;
            if (gEntryWindow) { gEntryWindow.hidden = NO; return; }
            @try {
                [self wcr_buildWindow];
                WCRAppendLog([NSString stringWithFormat:@"[WCRClown] floating entry ready: %@", gEntryWindow ? @"yes" : @"no scene"]);
            } @catch (NSException *e) {
                WCRAppendLog([NSString stringWithFormat:@"[WCRClown] entry install failed: %@", e]);
            }
        }];
    });
    // 也立刻试一次（已在前台时立即生效）
    [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
}

+ (void)setVisible:(BOOL)visible {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            if (visible && !gEntryWindow) {
                [self wcr_buildWindow];
            } else if (gEntryWindow) {
                gEntryWindow.hidden = !visible;
            }
        } @catch (NSException *e) {
            WCRAppendLog([NSString stringWithFormat:@"[WCRClown] entry visibility failed: %@", e]);
        }
    });
}

+ (void)wcr_buildWindow {
    UIWindowScene *scene = [self activeScene];
    if (!scene) return;

    // 先记住 App 主窗口（此刻 keyWindow 一定还是微信的），再创建 overlay
    if (!gHostWindow) gHostWindow = scene.keyWindow;

    CGFloat size = 46.0;
    CGFloat top = scene.statusBarManager.statusBarFrame.size.height + 8.0;
    CGPoint origin = gOriginKnown ? gEntryOrigin : CGPointMake(12.0, top);

    UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene];
    window.frame = CGRectMake(origin.x, origin.y, size, size);
    window.windowLevel = UIWindowLevelStatusBar + 10.0;
    window.backgroundColor = UIColor.clearColor;

    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = UIColor.clearColor;
    root.view.frame = window.bounds;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = root.view.bounds;
    button.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [button setTitle:@"丑" forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:18.0];
    button.tintColor = UIColor.whiteColor;
    button.backgroundColor = [[UIColor colorWithRed:0.00 green:0.45 blue:0.45 alpha:1.0] colorWithAlphaComponent:0.9];
    button.layer.cornerRadius = size / 2.0;
    button.layer.masksToBounds = YES;
    button.alpha = 0.75;

    [button addTarget:self action:@selector(wcr_entryTapped) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                          action:@selector(wcr_entryPanned:)];
    [button addGestureRecognizer:pan];
    [root.view addSubview:button];

    window.rootViewController = root;
    window.hidden = NO;
    gEntryWindow = window;
}

// 只在 App 主窗口（或任一非 overlay 的可见窗口）里找 presenter，绝不从自己的
// 小 overlay 窗口 present，否则面板会被压缩进 46x46 的框子里。
+ (nullable UIViewController *)wcr_hostPresenter {
    UIViewController *presenter = gHostWindow.rootViewController;
    if (!presenter) {
        for (UIWindow *w in [self activeScene].windows) {
            if (w == gEntryWindow) continue;
            if (!w.hidden && w.rootViewController) { presenter = w.rootViewController; break; }
        }
    }
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;
    return presenter;
}

+ (void)wcr_entryTapped {
    UIViewController *presenter = [self wcr_hostPresenter];
    WCRAppendLog([NSString stringWithFormat:@"[WCRClown] entry tapped presenter=%@", presenter ?: @"(nil)"]);
    if (presenter.view.window == gEntryWindow) {
        WCRAppendLog(@"[WCRClown] ERROR: presenter resolved to overlay window, abort");
        return;
    }
    [WCRClownPanelController presentFrom:presenter];
}

+ (void)wcr_entryPanned:(UIPanGestureRecognizer *)pan {
    if (!gEntryWindow) return;
    CGPoint delta = [pan translationInView:gEntryWindow];
    gEntryWindow.center = CGPointMake(gEntryWindow.center.x + delta.x, gEntryWindow.center.y + delta.y);
    [pan setTranslation:CGPointZero inView:gEntryWindow];
    if (pan.state == UIGestureRecognizerStateEnded) {
        gEntryOrigin = gEntryWindow.frame.origin;
        gOriginKnown = YES;
    }
}

@end
