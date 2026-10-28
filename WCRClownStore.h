#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface WCRClownStore : NSObject
+ (instancetype)shared;
- (nullable NSString *)messageKeyForWrap:(id)wrap session:(nullable NSString *)session;
- (nullable NSString *)chatTimeKeyForViewModel:(id)viewModel session:(nullable NSString *)session;
- (void)setText:(nullable NSString *)text quotedText:(nullable NSString *)quoted forKey:(NSString *)key;
- (void)setImage:(nullable UIImage *)image data:(nullable NSData *)data forKey:(NSString *)key;
- (void)setMessageTime:(nullable NSNumber *)time forKey:(NSString *)key;
- (void)setYinYang:(nullable NSNumber *)value forKey:(NSString *)key;
- (void)setChatTime:(nullable NSNumber *)time forKey:(NSString *)key;
- (void)setTransferAmount:(nullable NSString *)amount forKey:(NSString *)key session:(nullable NSString *)session;
- (nullable NSDictionary *)overridesForKey:(NSString *)key;
- (nullable NSString *)transferAmountForKey:(NSString *)key;
- (void)clearMessage:(NSString *)key;
- (void)clearSession:(NSString *)session;
- (void)clearTransferSession:(NSString *)session;
- (void)clearAll;
@end

NS_ASSUME_NONNULL_END
