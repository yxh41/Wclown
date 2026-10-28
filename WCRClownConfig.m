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
            @"diagnosticHooksEnabled": @NO
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

- (void)reset {
    for (NSString *key in @[@"enabled", @"textEnabled", @"imageEnabled", @"messageTimeEnabled",
                            @"messageSortEnabled", @"chatTimeEnabled", @"yinYangEnabled",
                            @"transferAmountEnabled", @"transferPersistOnExitChat", @"diagnosticHooksEnabled"]) {
        [_defaults removeObjectForKey:key];
    }
    [_defaults synchronize];
}

@end
