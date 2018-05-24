//
//  LJSupportUtils.m
//  CacheVideoDemo
//
//  Created by lijian on 2018/4/26.
//  Copyright © 2018年 lijian. All rights reserved.
//

#import "LJSupportUtils.h"
#import <MobileCoreServices/MobileCoreServices.h>

static JPLogLevel _logLevel;

void LJDispatchSyncOnMainQueue(dispatch_block_t block) {
    if (!block) { return; }
    if (strcmp(dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL), dispatch_queue_get_label(dispatch_get_main_queue())) == 0) {
        block();
    }
    else {
        dispatch_sync(dispatch_get_main_queue(), block);
    }
}

BOOL LJValidFileRange(NSRange range) {
    return ((range.location != NSNotFound) && range.length > 0 && range.length != NSUIntegerMax);
}

@implementation JPLog

+ (void)initialize {
    _logLevel = JPLogLevelDebug;
}

+ (void)logWithFlag:(JPLogLevel)logLevel
               file:(const char *)file
           function:(const char *)function
               line:(NSUInteger)line
             format:(NSString *)format, ... {
    if (logLevel > _logLevel) {
        return;
    }
    if (!format) {
        return;
    }
    
    
    va_list args;
    va_start(args, format);
    
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    if (message.length) {
        NSString *flag;
        switch (logLevel) {
            case JPLogLevelDebug:
                flag = @"DEBUG";
                break;
                
            case JPLogLevelWarning:
                flag = @"Waring";
                break;
                
            case JPLogLevelError:
                flag = @"Error";
                break;
                
            default:
                break;
        }
        
        NSString *threadName = [[NSThread currentThread] description];
        threadName = [threadName componentsSeparatedByString:@">"].lastObject;
        threadName = [threadName componentsSeparatedByString:@","].firstObject;
        threadName = [threadName stringByReplacingOccurrencesOfString:@"{number = " withString:@""];
        // message = [NSString stringWithFormat:@"[%@] [Thread: %@] %@ => [%@ + %ld]", flag, threadName, message, tempString, line];
        message = [NSString stringWithFormat:@"[%@] [Thread: %02ld] %@", flag, (long)[threadName integerValue], message];
        printf("%s\n", message.UTF8String);
    }
}

@end

@implementation NSHTTPURLResponse (LJVideoPlayer)

- (long long)lj_fileLength {
    NSString *range = [self allHeaderFields][@"Content-Range"];
    if (range) {
        NSArray *ranges = [range componentsSeparatedByString:@"/"];
        if (ranges.count > 0) {
            NSString *lengthString = [[ranges lastObject] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            return [lengthString longLongValue];
        }
    }
    else {
        return [self expectedContentLength];
    }
    return 0;
}

- (BOOL)lj_supportRange {
    return [self allHeaderFields][@"Content-Range"] != nil;
}

@end

@implementation LJSupportUtils

BOOL LJValidByteRange(NSRange range) {
    return ((range.location != NSNotFound) || (range.length > 0));
}
@end

@implementation AVAssetResourceLoadingRequest (LJVideoPlayer)

- (void)lj_fillContentInformationWithResponse:(NSHTTPURLResponse *)response {
    if (!response) {
        return;
    }
    
    self.response = response;
    if (!self.contentInformationRequest) {
        return;
    }
    
    NSString *mimeType = [response MIMEType];
    CFStringRef contentType = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, (__bridge CFStringRef)(mimeType), NULL);
    self.contentInformationRequest.byteRangeAccessSupported = [response lj_supportRange];
    self.contentInformationRequest.contentType = CFBridgingRelease(contentType);
    self.contentInformationRequest.contentLength = [response lj_fileLength];
    JPDebugLog(@"填充了响应信息到 contentInformationRequest");
}

@end

@implementation NSFileHandle (LJVideoPlayer)

- (BOOL)lj_safeWriteData:(NSData *)data {
    NSInteger retry = 3;
    size_t bytesLeft = data.length;
    const void *bytes = [data bytes];
    int fileDescriptor = [self fileDescriptor];
    while (bytesLeft > 0 && retry > 0) {
        ssize_t amountSent = write(fileDescriptor, bytes + data.length - bytesLeft, bytesLeft);
        if (amountSent < 0) {
            // write failed.
            JPErrorLog(@"Write file failed");
            break;
        }
        else {
            bytesLeft = bytesLeft - amountSent;
            if (bytesLeft > 0) {
                // not finished continue write after sleep 1 second.
                JPWarningLog(@"Write file retry");
                sleep(1);  //probably too long, but this is quite rare.
                retry--;
            }
        }
    }
    return bytesLeft == 0;
}

@end

