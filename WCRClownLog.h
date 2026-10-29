#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WCRClownLog : NSObject
+ (instancetype)shared;
- (void)append:(NSString *)line;
- (NSArray<NSString *> *)allLines;
- (void)clear;
@end

NS_ASSUME_NONNULL_END

// 统一日志入口：同时落设备 syslog（NSLog，便于电脑端 idevicesyslog 抓取）
// 与内存缓冲（供 App 内「诊断日志」查看，无需电脑）。
void WCRAppendLog(NSString *msg);

// 取代原先仅走 NSLog 的 WCRLog：所有 [WCRClown] 日志自动进内存缓冲。
#define WCRLog(fmt, ...) WCRAppendLog([NSString stringWithFormat:@"[WCRClown] " fmt, ##__VA_ARGS__])
