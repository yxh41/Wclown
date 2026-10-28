#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// 悬浮入口：自建 overlay UIWindow + 可拖动按钮，点击打开设置面板。
// 不触碰微信任何内部数据结构（不往菜单数组注入对象），因此不会引起微信闪退。
@interface WCRClownEntry : NSObject
+ (void)installIfNeeded;
+ (void)setVisible:(BOOL)visible;
@end

NS_ASSUME_NONNULL_END
