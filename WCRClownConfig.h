#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WCRClownConfig : NSObject
+ (instancetype)shared;
@property(nonatomic) BOOL enabled;
@property(nonatomic) BOOL textEnabled;
@property(nonatomic) BOOL imageEnabled;
@property(nonatomic) BOOL messageTimeEnabled;
@property(nonatomic) BOOL messageSortEnabled;
@property(nonatomic) BOOL chatTimeEnabled;
@property(nonatomic) BOOL yinYangEnabled;
@property(nonatomic) BOOL transferAmountEnabled;
@property(nonatomic) BOOL transferPersistOnExitChat;
@property(nonatomic) BOOL diagnosticHooksEnabled;
- (void)reset;
@end

NS_ASSUME_NONNULL_END
