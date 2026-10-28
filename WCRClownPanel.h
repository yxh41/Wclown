#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// 微信内设置面板：纯 UIKit，不依赖 PreferenceLoader，避免 roothide 下
// PSToggleSwitchCell 解析不到导致设置页只剩文字。
@interface WCRClownPanelController : UITableViewController
+ (void)presentFrom:(UIViewController *)presenter;
@end

NS_ASSUME_NONNULL_END
