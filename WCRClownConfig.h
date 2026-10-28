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
// 入口开关：长按菜单注入曾导致微信闪退（微信菜单数组很可能是自有菜单项类，
// 混入 UIMenuItem 会 unrecognized selector），故默认关闭；悬浮入口零风险，默认开启。
@property(nonatomic) BOOL menuEntryEnabled;
@property(nonatomic) BOOL floatingEntryEnabled;
- (void)reset;
@end

NS_ASSUME_NONNULL_END
