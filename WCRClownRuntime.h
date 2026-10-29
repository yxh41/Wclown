#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT id _Nullable WCRSafeCall0(id _Nullable object, SEL selector);
FOUNDATION_EXPORT id _Nullable WCRSafeCall1(id _Nullable object, SEL selector, id _Nullable value);
FOUNDATION_EXPORT uint64_t WCRSafeUInt64(id _Nullable object, NSString *selectorName);
FOUNDATION_EXPORT BOOL WCRSafeBool(id _Nullable object, NSString *selectorName);
FOUNDATION_EXPORT NSString * _Nullable WCRSafeString(id _Nullable object, NSString *selectorName);
FOUNDATION_EXPORT void WCRSafeSetUInt32(id _Nullable object, NSString *selectorName, uint32_t value);
FOUNDATION_EXPORT void WCRSafeSetBool(id _Nullable object, NSString *selectorName, BOOL value);
FOUNDATION_EXPORT void WCRSafeSetObject(id _Nullable object, NSString *selectorName, id _Nullable value);
FOUNDATION_EXPORT BOOL WCRClassAndSelectorAvailable(NSString *className, NSString *selectorName);
// 保存后主动扫描当前屏幕的文本 Cell 并按 key 直接刷新 RichTextView（不依赖微信重渲染时机）
FOUNDATION_EXPORT void WCRForceRefreshVisibleTextCellsForKey(NSString * _Nullable targetKey);

@interface WCRClownRuntime : NSObject
+ (void)applyOverridesToMessage:(id)wrap session:(nullable NSString *)session;
+ (BOOL)isTransferMessage:(id)wrap;
+ (nullable NSString *)transferAmountFromText:(nullable NSString *)text wrap:(nullable id)wrap;
@end

NS_ASSUME_NONNULL_END
