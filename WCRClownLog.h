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
// extern "C"：Tweak.xm 经 Logos 预处理后以 Objective-C++ 编译，跨文件 C 函数必须
// 统一 C 链接，否则 C++ 名字修饰导致链接时找不到符号（与 WCRClownLog.m 的 C 符号不符）。
#if defined(__cplusplus)
extern "C" {
#endif
void WCRAppendLog(NSString * _Nullable msg);
#if defined(__cplusplus)
}
#endif

// 取代原先仅走 NSLog 的 WCRLog：所有 [WCRClown] 日志自动进内存缓冲。
#define WCRLog(fmt, ...) WCRAppendLog([NSString stringWithFormat:@"[WCRClown] " fmt, ##__VA_ARGS__])
