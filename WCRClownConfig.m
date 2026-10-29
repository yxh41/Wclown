#import "WCRClownConfig.h"

static NSString *const kWCRClownDefaults = @"com.zlhkf.wclown";

@implementation WCRClownConfig {
    NSUserDefaults *_defaults;
}

+ (instancetype)shared {
    static WCRClownConfig *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [self new]; });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _defaults = [[NSUserDefaults alloc] initWithSuiteName:kWCRClownDefaults];
        [_defaults registerDefaults:@{
            @"enabled": @NO,
            @"textEnabled": @NO,
            @"imageEnabled": @NO,
            @"messageTimeEnabled": @NO,
            @"messageSortEnabled": @NO,
            @"chatTimeEnabled": @NO,
            @"yinYangEnabled": @NO,
            @"transferAmountEnabled": @NO,
            @"transferPersistOnExitChat": @NO,
            @"diagnosticHooksEnabled": @NO,
            @"menuEntryEnabled": @YES,         // 长按菜单注入默认开（已加 UIMenuItem 类型护栏，不再闪退）
            @"floatingEntryEnabled": @YES      // 悬浮入口默认开（零风险）
        }];
    }
    return self;
}

#define WCR_BOOL_PROPERTY(NAME, SETTER) \
- (BOOL)NAME { return [_defaults boolForKey:@#NAME]; } \
- (void)SETTER:(BOOL)value { [_defaults setBool:value forKey:@#NAME]; [_defaults synchronize]; }

WCR_BOOL_PROPERTY(enabled, setEnabled)
WCR_BOOL_PROPERTY(textEnabled, setTextEnabled)
WCR_BOOL_PROPERTY(imageEnabled, setImageEnabled)
WCR_BOOL_PROPERTY(messageTimeEnabled, setMessageTimeEnabled)
WCR_BOOL_PROPERTY(messageSortEnabled, setMessageSortEnabled)
WCR_BOOL_PROPERTY(chatTimeEnabled, setChatTimeEnabled)
WCR_BOOL_PROPERTY(yinYangEnabled, setYinYangEnabled)
WCR_BOOL_PROPERTY(transferAmountEnabled, setTransferAmountEnabled)
WCR_BOOL_PROPERTY(transferPersistOnExitChat, setTransferPersistOnExitChat)
WCR_BOOL_PROPERTY(diagnosticHooksEnabled, setDiagnosticHooksEnabled)
// 入口开关改为「永远开」，不可被设置开关误关：之前用户把这两个关掉后整个功能看不见、且没处恢复，
// 反复踩坑。长按菜单入口 + 悬浮入口是功能的「访问方式」，不应可被关到全失联。
// 若要隐藏悬浮按钮，后续单独加回一个非入口类开关即可。
- (BOOL)menuEntryEnabled { return YES; }
- (void)setMenuEntryEnabled:(BOOL)v { /* 永远开，忽略写入 */ }
- (BOOL)floatingEntryEnabled { return YES; }
- (void)setFloatingEntryEnabled:(BOOL)v { /* 永远开，忽略写入 */ }

- (void)reset {
    for (NSString *key in @[@"enabled", @"textEnabled", @"imageEnabled", @"messageTimeEnabled",
                            @"messageSortEnabled", @"chatTimeEnabled", @"yinYangEnabled",
                            @"transferAmountEnabled", @"transferPersistOnExitChat", @"diagnosticHooksEnabled",
                            @"menuEntryEnabled", @"floatingEntryEnabled"]) {
        [_defaults removeObjectForKey:key];
    }
    [_defaults synchronize];
}

@end
