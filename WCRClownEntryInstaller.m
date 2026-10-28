#import "WCRClownEntryInstaller.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static const void *kWCRClownButtonKey = &kWCRClownButtonKey;

@implementation WCRClownEntryInstaller

+ (void)installIfSupported {
    // Keep the scaffold inert until a stable WeChat settings host is verified.
    // This method intentionally performs capability discovery only.
    NSArray<NSString *> *hosts = @[
        @"NewSettingViewController",
        @"SettingViewController",
        @"MoreViewController"
    ];
    for (NSString *name in hosts) {
        Class cls = NSClassFromString(name);
        if (cls) NSLog(@"[WCRClownStandalone] settings host candidate: %@", name);
    }
}

@end
