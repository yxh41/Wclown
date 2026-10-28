#import "WCRClownEntry.h"
#import "WCRClownConfig.h"
#import "WCRClownPanel.h"

static UIWindow *gEntryWindow = nil;
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
    if (gEntryWindow) { gEntryWindow.hidden = NO; return; }
    // 延迟到首个 runloop：构造 UIWindow 必须在主线程且 app 已完成基本启动
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            [self wcr_buildWindow];
        } @catch (NSException *e) {
            NSLog(@"[WCRClown] entry install failed: %@", e);
        }
    });
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
            NSLog(@"[WCRClown] entry visibility failed: %@", e);
        }
    });
}

+ (void)wcr_buildWindow {
    UIWindowScene *scene = [self activeScene];
    if (!scene) return;

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

+ (void)wcr_entryTapped {
    UIWindowScene *scene = [self activeScene];
    UIViewController *presenter = scene.keyWindow.rootViewController;
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;
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
