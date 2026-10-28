#import "WCRClownRuntime.h"
#import "WCRClownConfig.h"
#import "WCRClownStore.h"
#import <objc/message.h>
#import <objc/runtime.h>

id WCRSafeCall0(id object, SEL selector) {
    if (!object || !selector || ![object respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

id WCRSafeCall1(id object, SEL selector, id value) {
    if (!object || !selector || ![object respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL, id))objc_msgSend)(object, selector, value);
}

uint64_t WCRSafeUInt64(id object, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (!object || ![object respondsToSelector:selector]) return 0;
    return ((uint64_t (*)(id, SEL))objc_msgSend)(object, selector);
}

BOOL WCRSafeBool(id object, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (!object || ![object respondsToSelector:selector]) return NO;
    return ((BOOL (*)(id, SEL))objc_msgSend)(object, selector);
}

NSString *WCRSafeString(id object, NSString *selectorName) {
    id value = WCRSafeCall0(object, NSSelectorFromString(selectorName));
    return [value isKindOfClass:NSString.class] ? value : nil;
}

void WCRSafeSetUInt32(id object, NSString *selectorName, uint32_t value) {
    SEL selector = NSSelectorFromString(selectorName);
    if (object && [object respondsToSelector:selector]) ((void (*)(id, SEL, uint32_t))objc_msgSend)(object, selector, value);
}

void WCRSafeSetBool(id object, NSString *selectorName, BOOL value) {
    SEL selector = NSSelectorFromString(selectorName);
    if (object && [object respondsToSelector:selector]) ((void (*)(id, SEL, BOOL))objc_msgSend)(object, selector, value);
}

void WCRSafeSetObject(id object, NSString *selectorName, id value) {
    SEL selector = NSSelectorFromString(selectorName);
    if (object && [object respondsToSelector:selector]) ((void (*)(id, SEL, id))objc_msgSend)(object, selector, value);
}

BOOL WCRClassAndSelectorAvailable(NSString *className, NSString *selectorName) {
    Class cls = NSClassFromString(className);
    return cls && class_getInstanceMethod(cls, NSSelectorFromString(selectorName));
}

@implementation WCRClownRuntime

+ (void)applyOverridesToMessage:(id)wrap session:(NSString *)session {
    WCRClownConfig *config = WCRClownConfig.shared;
    if (!config.enabled || !wrap) return;
    NSString *key = [WCRClownStore.shared messageKeyForWrap:wrap session:session];
    NSDictionary *entry = key.length ? [WCRClownStore.shared overridesForKey:key] : nil;
    if (!entry.count) return;

    if (config.textEnabled && entry[@"text"] && WCRSafeBool(wrap, @"IsTextMsg")) {
        WCRSafeSetObject(wrap, @"setM_nsContent:", entry[@"text"]);
    }
    if (config.messageTimeEnabled && entry[@"messageTime"]) {
        WCRSafeSetUInt32(wrap, @"setM_uiCreateTime:", [entry[@"messageTime"] unsignedIntValue]);
    }
    if (config.yinYangEnabled && entry[@"yinYang"]) {
        WCRSafeSetBool(wrap, @"setM_uiIsSenderStatus:", [entry[@"yinYang"] boolValue]);
    }
}

+ (BOOL)isTransferMessage:(id)wrap {
    if (!wrap) return NO;
    for (NSString *name in @[@"m_oWCPayInfoItem", @"m_payInfoItem", @"payInfoItem"]) {
        if (WCRSafeCall0(wrap, NSSelectorFromString(name))) return YES;
    }
    NSString *content = WCRSafeString(wrap, @"m_nsContent");
    return [content containsString:@"wxpay://c2ctransfer"] || [content containsString:@"<transfer"];
}

+ (NSString *)transferAmountFromText:(NSString *)text wrap:(id)wrap {
    WCRClownConfig *config = WCRClownConfig.shared;
    if (!config.enabled || !config.transferAmountEnabled || !text.length || ![self isTransferMessage:wrap]) return nil;
    NSString *key = [WCRClownStore.shared messageKeyForWrap:wrap session:nil];
    NSString *amount = key.length ? [WCRClownStore.shared transferAmountForKey:key] : nil;
    return amount.length ? amount : nil;
}

@end
