#import <UIKit/UIKit.h>

// Tweak.xm 中定义、由本面板显示的构建标记（必须 extern 声明以获得外部链接，
// 否则跨 .o 引用会 ld: undefined symbol）
extern const char kWCRClownBuildTag[];

NS_ASSUME_NONNULL_BEGIN

// 微信内设置面板：纯 UIKit，不依赖 PreferenceLoader，避免 roothide 下
// PSToggleSwitchCell 解析不到导致设置页只剩文字。
@interface WCRClownPanelController : UITableViewController
+ (void)presentFrom:(UIViewController *)presenter;
@end

NS_ASSUME_NONNULL_END
