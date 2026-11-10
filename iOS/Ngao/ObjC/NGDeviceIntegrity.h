#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Best-effort jailbreak and tamper signals. None of these is proof, and a determined
/// attacker defeats all of them; the bank's risk engine treats the result as one signal
/// among many (device binding, behaviour, velocity). The app uses it to refuse to cache
/// anything sensitive and to tell the server.
@interface NGDeviceIntegrity : NSObject

/// Human-readable reasons, empty when nothing was found.
+ (NSArray<NSString *> *)suspiciousSignals;

+ (BOOL)isDebuggerAttached;

@end

NS_ASSUME_NONNULL_END
