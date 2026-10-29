#import "WCRClownSettingsController.h"
#import <UIKit/UIKit.h>

// 偏好域与 WCRClownConfig 完全一致：设置 bundle 与 tweak 进程都读写同一份
// com.zlhkf.wclown 偏好（tweak 用 initWithSuiteName:，这里同样）。
// 重置 = 删除所有键，让 tweak 的 registerDefaults（入口默认开、覆盖默认关）重新生效。
static NSString *const kWCRClownDefaults = @"com.zlhkf.wclown";

@implementation WCRClownSettingsController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

// PSButtonCell 的 action：无参调用（libprefs 以 performSelector:action 触发，安全）。
- (void)resetSettings {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:kWCRClownDefaults];
    for (NSString *k in @[@"enabled", @"textEnabled", @"imageEnabled", @"messageTimeEnabled",
                          @"messageSortEnabled", @"chatTimeEnabled", @"yinYangEnabled",
                          @"transferAmountEnabled", @"transferPersistOnExitChat",
                          @"diagnosticHooksEnabled", @"menuEntryEnabled", @"floatingEntryEnabled"]) {
        [d removeObjectForKey:k];
    }
    [d synchronize];
    [self reloadSpecifiers];   // 重新加载，开关回到默认显示态
    if ([UIAlertController class]) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"已恢复默认"
                                                                  message:@"长按菜单入口与悬浮入口已默认开启；重启微信后生效。"
                                                           preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
    }
}

@end
