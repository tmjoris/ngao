#import "NGDeviceIntegrity.h"
#import <UIKit/UIKit.h>
#import <sys/sysctl.h>
#import <sys/stat.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>

@implementation NGDeviceIntegrity

+ (NSArray<NSString *> *)suspiciousSignals {
    NSMutableArray<NSString *> *signals = [NSMutableArray array];
#if TARGET_OS_SIMULATOR
    return signals;
#endif
    NSArray<NSString *> *paths = @[
        @"/Applications/Cydia.app", @"/Applications/Sileo.app", @"/Applications/Zebra.app",
        @"/Library/MobileSubstrate/MobileSubstrate.dylib", @"/usr/sbin/sshd", @"/bin/bash",
        @"/etc/apt", @"/private/var/lib/apt/", @"/usr/libexec/ssh-keysign", @"/var/jb",
    ];
    for (NSString *path in paths) {
        struct stat s;
        if (stat(path.fileSystemRepresentation, &s) == 0) {
            [signals addObject:[NSString stringWithFormat:@"path:%@", path.lastPathComponent]];
        }
    }

    NSString *probe = [NSString stringWithFormat:@"/private/%@", NSUUID.UUID.UUIDString];
    NSError *error = nil;
    if ([@"probe" writeToFile:probe atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        [[NSFileManager defaultManager] removeItemAtPath:probe error:nil];
        [signals addObject:@"writable:/private"];
    }

    if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"cydia://package/com.example"]]) {
        [signals addObject:@"scheme:cydia"];
    }

    NSArray<NSString *> *libraries = @[@"MobileSubstrate", @"SubstrateLoader", @"libhooker", @"FridaGadget", @"frida", @"cynject"];
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        NSString *name = [NSString stringWithUTF8String:_dyld_get_image_name(i) ?: ""];
        for (NSString *library in libraries) {
            if ([name rangeOfString:library options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [signals addObject:[NSString stringWithFormat:@"dylib:%@", library]];
            }
        }
    }

    if (dlopen("/usr/lib/libsubstrate.dylib", RTLD_NOW | RTLD_NOLOAD) != NULL) {
        [signals addObject:@"dlopen:substrate"];
    }
    return signals;
}

+ (BOOL)isDebuggerAttached {
    struct kinfo_proc info;
    size_t size = sizeof(info);
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    if (sysctl(mib, 4, &info, &size, NULL, 0) != 0) { return NO; }
    return (info.kp_proc.p_flag & P_TRACED) != 0;
}

@end
