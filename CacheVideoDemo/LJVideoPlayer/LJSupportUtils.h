//
//  LJSupportUtils.h
//  CacheVideoDemo
//
//  Created by lijian on 2018/4/26.
//  Copyright © 2018年 lijian. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>



typedef NS_ENUM(NSUInteger, JPLogLevel) {
    // no log output.
    JPLogLevelNone = 0,
    
    // output debug, warning and error log.
    JPLogLevelError = 1,
    
    // output debug and warning log.
    JPLogLevelWarning = 2,
    
    // output debug log.
    JPLogLevelDebug = 3,
};

@interface JPLog : NSObject

/**
 * Output message to console.
 *
 *  @param logLevel         The log type.
 *  @param file         The current file name.
 *  @param function     The current function name.
 *  @param line         The current line number.
 *  @param format       The log format.
 */
+ (void)logWithFlag:(JPLogLevel)logLevel
               file:(const char *)file
           function:(const char *)function
               line:(NSUInteger)line
             format:(NSString *)format, ...;

@end

#ifdef __OBJC__

#define JP_LOG_MACRO(logFlag, frmt, ...) \
[JPLog logWithFlag:logFlag \
file:__FILE__ \
function:__FUNCTION__ \
line:__LINE__ \
format:(frmt), ##__VA_ARGS__]


#define JP_LOG_MAYBE(logFlag, frmt, ...) JP_LOG_MACRO(logFlag, frmt, ##__VA_ARGS__)

#if DEBUG

/**
 * Log debug log.
 */
#define JPDebugLog(frmt, ...) JP_LOG_MAYBE(JPLogLevelDebug, frmt, ##__VA_ARGS__)

/**
 * Log debug and warning log.
 */
#define JPWarningLog(frmt, ...) JP_LOG_MAYBE(JPLogLevelWarning, frmt, ##__VA_ARGS__)

/**
 * Log debug, warning and error log.
 */
#define JPErrorLog(frmt, ...) JP_LOG_MAYBE(JPLogLevelError, frmt, ##__VA_ARGS__)

#else

#define JPDebugLog(frmt, ...)
#define JPWarningLog(frmt, ...)
#define JPErrorLog(frmt, ...)
#endif

#endif

@interface LJSupportUtils : NSObject

BOOL LJValidByteRange(NSRange range);

void LJDispatchSyncOnMainQueue(dispatch_block_t block);

BOOL LJValidFileRange(NSRange range);

@end

@interface AVAssetResourceLoadingRequest (LJVideoPlayer)

/**
 * Fill content information for current request use response conent.
 *
 * @param response A response.
 */
- (void)lj_fillContentInformationWithResponse:(NSHTTPURLResponse *)response;

@end

@interface NSHTTPURLResponse (LJVideoPlayer)

- (long long)lj_fileLength;

- (BOOL)lj_supportRange;

@end

@interface NSFileHandle (LJVideoPlayer)

- (BOOL)lj_safeWriteData:(NSData *)data;

@end
