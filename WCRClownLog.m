#import "WCRClownLog.h"

@interface WCRClownLog ()
@property(nonatomic) dispatch_queue_t queue;
@property(nonatomic) NSMutableArray<NSString *> *lines;
@end

@implementation WCRClownLog

+ (instancetype)shared {
    static WCRClownLog *inst;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ inst = [self new]; });
    return inst;
}

- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("com.minis.wcrclown.log", DISPATCH_QUEUE_SERIAL);
        _lines = [NSMutableArray array];
    }
    return self;
}

- (void)append:(NSString *)line {
    if (!line.length) return;
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"HH:mm:ss.SSS";
    NSString *ts = [fmt stringFromDate:[NSDate date]];
    NSString *entry = [ts stringByAppendingFormat:@"  %@", line];
    dispatch_async(self.queue, ^{
        [self.lines addObject:entry];
        if (self.lines.count > 2000) {
            [self.lines removeObjectsInRange:NSMakeRange(0, self.lines.count - 2000)];
        }
    });
}

- (NSArray<NSString *> *)allLines {
    __block NSArray<NSString *> *copy;
    dispatch_sync(self.queue, ^{ copy = [self.lines copy]; });
    return copy;
}

- (void)clear {
    dispatch_async(self.queue, ^{ [self.lines removeAllObjects]; });
}

@end

void WCRAppendLog(NSString *msg) {
    if (!msg) return;
    NSLog(@"%@", msg);
    [[WCRClownLog shared] append:msg];
}
