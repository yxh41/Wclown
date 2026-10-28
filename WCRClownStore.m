#import "WCRClownStore.h"
#import "WCRClownRuntime.h"

@interface WCRClownStore ()
@property(nonatomic) dispatch_queue_t queue;
@property(nonatomic) NSMutableDictionary<NSString *, NSMutableDictionary *> *messages;
@property(nonatomic) NSMutableDictionary<NSString *, NSNumber *> *chatTimes;
@property(nonatomic) NSMutableDictionary<NSString *, NSString *> *transferAmounts;
@property(nonatomic) NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *sessionKeys;
@property(nonatomic) NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *transferSessionKeys;
@end

@implementation WCRClownStore

+ (instancetype)shared {
    static WCRClownStore *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [self new]; });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("com.minis.wcrclown.store", DISPATCH_QUEUE_CONCURRENT);
        _messages = [NSMutableDictionary dictionary];
        _chatTimes = [NSMutableDictionary dictionary];
        _transferAmounts = [NSMutableDictionary dictionary];
        _sessionKeys = [NSMutableDictionary dictionary];
        _transferSessionKeys = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSString *)messageKeyForWrap:(id)wrap session:(NSString *)session {
    if (!wrap) return nil;
    uint64_t localID = WCRSafeUInt64(wrap, @"m_uiMesLocalID");
    uint64_t serverID = WCRSafeUInt64(wrap, @"m_n64MesSvrID");
    NSString *resolvedSession = session;
    if (!resolvedSession.length) {
        resolvedSession = WCRSafeString(wrap, @"m_nsFromUsr") ?: WCRSafeString(wrap, @"m_nsToUsr");
    }
    if (!resolvedSession.length && !localID && !serverID) return nil;
    NSString *key = [NSString stringWithFormat:@"%@:%llu:%llu", resolvedSession ?: @"", localID, serverID];
    if (resolvedSession.length) {
        dispatch_barrier_sync(self.queue, ^{
            NSMutableSet *keys = self.sessionKeys[resolvedSession] ?: [NSMutableSet set];
            [keys addObject:key];
            self.sessionKeys[resolvedSession] = keys;
        });
    }
    return key;
}

- (NSString *)chatTimeKeyForViewModel:(id)viewModel session:(NSString *)session {
    if (!viewModel || !session.length) return nil;
    uint64_t time = WCRSafeUInt64(viewModel, @"createTime");
    return [NSString stringWithFormat:@"%@:%llu:chat-time", session, time];
}

- (void)mutateKey:(NSString *)key block:(void (^)(NSMutableDictionary *entry))block {
    if (!key.length || !block) return;
    dispatch_barrier_sync(self.queue, ^{
        NSMutableDictionary *entry = self.messages[key] ?: [NSMutableDictionary dictionary];
        block(entry);
        if (entry.count) self.messages[key] = entry; else [self.messages removeObjectForKey:key];
    });
}

- (void)setText:(NSString *)text quotedText:(NSString *)quoted forKey:(NSString *)key {
    [self mutateKey:key block:^(NSMutableDictionary *entry) {
        if (text) entry[@"text"] = text; else [entry removeObjectForKey:@"text"];
        if (quoted) entry[@"quotedText"] = quoted; else [entry removeObjectForKey:@"quotedText"];
    }];
}

- (void)setImage:(UIImage *)image data:(NSData *)data forKey:(NSString *)key {
    [self mutateKey:key block:^(NSMutableDictionary *entry) {
        if (image) entry[@"image"] = image; else [entry removeObjectForKey:@"image"];
        if (data) entry[@"imageData"] = data; else [entry removeObjectForKey:@"imageData"];
    }];
}

- (void)setMessageTime:(NSNumber *)time forKey:(NSString *)key {
    [self mutateKey:key block:^(NSMutableDictionary *entry) { if (time) entry[@"messageTime"] = time; else [entry removeObjectForKey:@"messageTime"]; }];
}

- (void)setYinYang:(NSNumber *)value forKey:(NSString *)key {
    [self mutateKey:key block:^(NSMutableDictionary *entry) { if (value) entry[@"yinYang"] = value; else [entry removeObjectForKey:@"yinYang"]; }];
}

- (void)setChatTime:(NSNumber *)time forKey:(NSString *)key {
    if (!key.length) return;
    dispatch_barrier_sync(self.queue, ^{ if (time) self.chatTimes[key] = time; else [self.chatTimes removeObjectForKey:key]; });
}

- (void)setTransferAmount:(NSString *)amount forKey:(NSString *)key session:(NSString *)session {
    if (!key.length) return;
    dispatch_barrier_sync(self.queue, ^{
        if (amount.length) self.transferAmounts[key] = amount; else [self.transferAmounts removeObjectForKey:key];
        if (session.length) {
            NSMutableSet *keys = self.transferSessionKeys[session] ?: [NSMutableSet set];
            if (amount.length) [keys addObject:key]; else [keys removeObject:key];
            self.transferSessionKeys[session] = keys;
        }
    });
}

- (NSDictionary *)overridesForKey:(NSString *)key {
    __block NSDictionary *value;
    dispatch_sync(self.queue, ^{ value = [self.messages[key] copy]; });
    return value;
}

- (NSString *)transferAmountForKey:(NSString *)key {
    __block NSString *value;
    dispatch_sync(self.queue, ^{ value = self.transferAmounts[key]; });
    return value;
}

- (void)clearMessage:(NSString *)key { if (key.length) dispatch_barrier_sync(self.queue, ^{ [self.messages removeObjectForKey:key]; [self.transferAmounts removeObjectForKey:key]; }); }
- (void)clearSession:(NSString *)session {
    if (!session.length) return;
    dispatch_barrier_sync(self.queue, ^{ for (NSString *key in self.sessionKeys[session]) [self.messages removeObjectForKey:key]; [self.sessionKeys removeObjectForKey:session]; });
}
- (void)clearTransferSession:(NSString *)session {
    if (!session.length) return;
    dispatch_barrier_sync(self.queue, ^{ for (NSString *key in self.transferSessionKeys[session]) [self.transferAmounts removeObjectForKey:key]; [self.transferSessionKeys removeObjectForKey:session]; });
}
- (void)clearAll { dispatch_barrier_sync(self.queue, ^{ [self.messages removeAllObjects]; [self.chatTimes removeAllObjects]; [self.transferAmounts removeAllObjects]; [self.sessionKeys removeAllObjects]; [self.transferSessionKeys removeAllObjects]; }); }

@end
