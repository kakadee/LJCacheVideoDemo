//
//  LJResourceLoadingRequestTask.m
//  CacheVideoDemo
//
//  Created by lijian on 2018/4/26.
//  Copyright © 2018年 lijian. All rights reserved.
//

#import "LJResourceLoadingRequestTask.h"
#import <pthread.h>
#import "LJVideoPlayerCacheFile.h"
#import "LJSupportUtils.h"
#import <MobileCoreServices/MobileCoreServices.h>

static const NSTimeInterval RequestTimeout = 10;
static NSUInteger kFileReadBufferSize = 1024 * 32; // 限制一次最多读取的buffer大小
static const NSString *kContentRange = @"Content-Range";

@interface LJResourceLoadingRequestTask()

@property (nonatomic, assign, getter=isCached) BOOL cached;

@property (nonatomic, assign, getter = isExecuting) BOOL executing;

@property (nonatomic, assign, getter = isFinished) BOOL finished;

@property (nonatomic, assign, getter = isCancelled) BOOL cancelled;

@property (nonatomic) pthread_mutex_t lock;

@end

@implementation LJResourceLoadingRequestTask

- (void)dealloc {
    pthread_mutex_destroy(&_lock);
}

- (instancetype)initWithLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest
                          requestRange:(NSRange)requestRange
                             cacheFile:(LJVideoPlayerCacheFile *)cacheFile
                             customURL:(NSURL *)customURL
                                cached:(BOOL)cached {
    self = [super init];
    if (self) {
        _loadingRequest = loadingRequest;
        _requestRange = requestRange;
        _cacheFile = cacheFile;
        _customURL = customURL;
        _cached = cached;
        _executing = NO;
        _cancelled = NO;
        _finished = NO;
    }
    return self;
}

+ (instancetype)requestTaskWithLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest
                                 requestRange:(NSRange)requestRange
                                    cacheFile:(LJVideoPlayerCacheFile *)cacheFile
                                    customURL:(NSURL *)customURL
                                       cached:(BOOL)cached {
    return [[[self class] alloc] initWithLoadingRequest:loadingRequest
                                           requestRange:requestRange
                                              cacheFile:cacheFile
                                              customURL:customURL
                                                 cached:cached];
}

- (void)requestDidCompleteWithError:(NSError *_Nullable)error {
    LJDispatchSyncOnMainQueue(^{
        self.executing = NO;
        self.finished = YES;
        if (self.delegate && [self.delegate respondsToSelector:@selector(requestTask:didCompleteWithError:)]) {
            [self.delegate requestTask:self didCompleteWithError:error];
        }
    });
}

- (void)start {
    int lock = pthread_mutex_trylock(&_lock);;
    self.executing = YES;
    if (!lock) {
        pthread_mutex_unlock(&_lock);
    }
}

- (void)startOnQueue:(dispatch_queue_t)queue {
    dispatch_async(queue, ^{
        int lock = pthread_mutex_trylock(&self->_lock);
        self.executing = YES;
        if (!lock) {
            pthread_mutex_unlock(&self->_lock);
        }
    });
}

- (void)cancel {
    JPDebugLog(@"调用了 RequestTask 的取消方法");
    self.executing = NO;
    self.cancelled = YES;
}

#pragma mark - Private

- (void)setFinished:(BOOL)finished {
    [self willChangeValueForKey:@"isFinished"];
    _finished = finished;
    [self didChangeValueForKey:@"isFinished"];
}

- (void)setCancelled:(BOOL)cancelled {
    [self willChangeValueForKey:@"isCancelled"];
    _cancelled = cancelled;
    [self didChangeValueForKey:@"isCancelled"];
}

- (void)setExecuting:(BOOL)executing {
    [self willChangeValueForKey:@"isExecuting"];
    _executing = executing;
    [self didChangeValueForKey:@"isExecuting"];
}

@end

@interface LJResourceLoadingRequestLocalTask()

@property (nonatomic) pthread_mutex_t plock;

@end

@implementation LJResourceLoadingRequestLocalTask

- (void)dealloc {
    JPDebugLog(@"Local task dealloc");
    pthread_mutex_destroy(&_plock);
}

- (instancetype)initWithLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest
                          requestRange:(NSRange)requestRange
                             cacheFile:(LJVideoPlayerCacheFile *)cacheFile
                             customURL:(NSURL *)customURL
                                cached:(BOOL)cached {
    self = [super initWithLoadingRequest:loadingRequest
                            requestRange:requestRange
                               cacheFile:cacheFile
                               customURL:customURL
                                  cached:cached];
    if(self){
        pthread_mutexattr_t mutexattr;
        pthread_mutexattr_init(&mutexattr);
        pthread_mutexattr_settype(&mutexattr, PTHREAD_MUTEX_RECURSIVE);
        pthread_mutex_init(&_plock, &mutexattr);
        if(cacheFile.responseHeaders && !loadingRequest.contentInformationRequest.contentType){
            [self fillContentInformation];
        }
    }
    return self;
}

- (void)startOnQueue:(dispatch_queue_t)queue {
    [super startOnQueue:queue];
    dispatch_async(queue, ^{
        [self internalStart];
    });
}

- (void)start {
    NSAssert(![NSThread isMainThread], @"Do not use main thread when start a local task");
    [super start];
    [self internalStart];
}

- (void)internalStart {
    if ([self isCancelled]) {
        [self requestDidCompleteWithError:nil];
        return;
    }
    
    JPDebugLog(@"stepN:开始响应本地请求---%@",NSStringFromRange(self.requestRange));

    NSUInteger offset = self.requestRange.location;
    while (offset < NSMaxRange(self.requestRange)) {
        if ([self isCancelled]) {
            JPDebugLog(@"stepN:本地请求break");
            break;
        }
        @autoreleasepool {
            NSRange range = NSMakeRange(offset, MIN(NSMaxRange(self.requestRange) - offset, kFileReadBufferSize));
            NSData *data = [self.cacheFile dataWithRange:range];
            [self.loadingRequest.dataRequest respondWithData:data];
            JPDebugLog(@"stepN:本地请求回填数据");
            offset = NSMaxRange(range);
        }
    }
    JPDebugLog(@"stepN:完成本地请求---%@",NSStringFromRange(self.requestRange));
    [self requestDidCompleteWithError:nil];
}


- (void)fillContentInformation {
    int lock = pthread_mutex_trylock(&_plock);
    NSMutableDictionary *responseHeaders = [self.cacheFile.responseHeaders mutableCopy];
    BOOL supportRange = responseHeaders[kContentRange] != nil;
    if (supportRange && LJValidByteRange(self.requestRange)) {
        NSUInteger fileLength = [self.cacheFile fileLength];
        NSString *contentRange = [NSString stringWithFormat:@"bytes %tu-%tu/%tu", self.requestRange.location, fileLength, fileLength];
        responseHeaders[kContentRange] = contentRange;
    }
    else {
        [responseHeaders removeObjectForKey:kContentRange];
    }
    NSUInteger contentLength = self.requestRange.length != NSUIntegerMax ? self.requestRange.length : self.cacheFile.fileLength - self.requestRange.location;
    responseHeaders[@"Content-Length"] = [NSString stringWithFormat:@"%tu", contentLength];
    NSInteger statusCode = supportRange ? 206 : 200; // 服务器响应的状态码 206 表示支持断点续传
    
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.loadingRequest.request.URL
                                                              statusCode:statusCode
                                                             HTTPVersion:@"HTTP/1.1"
                                                            headerFields:responseHeaders];
    
    [self.loadingRequest lj_fillContentInformationWithResponse:response];
    if (!lock) {
        pthread_mutex_unlock(&_plock);
    }
}

@end

@interface LJResourceLoadingRequestWebTask() <NSURLSessionDelegate, NSURLSessionDataDelegate>

@property (nonatomic, strong) NSURLSession *session;

@property (nonatomic, strong) NSURLSessionDataTask *task;

@property(nonatomic, assign) NSUInteger offset;

@property(nonatomic, assign) NSUInteger requestLength;

@property(nonatomic, assign) BOOL haveDataSaved;

@property (nonatomic) pthread_mutex_t plock;

@end

@implementation LJResourceLoadingRequestWebTask

- (void)dealloc {
    JPDebugLog(@"Web task dealloc: %@", self);
    pthread_mutex_destroy(&_plock);
}

- (instancetype)initWithLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest
                          requestRange:(NSRange)requestRange
                             cacheFile:(LJVideoPlayerCacheFile *)cacheFile
                             customURL:(NSURL *)customURL
                                cached:(BOOL)cached {
    NSParameterAssert(LJValidByteRange(requestRange));
    self = [super initWithLoadingRequest:loadingRequest
                            requestRange:requestRange
                               cacheFile:cacheFile
                               customURL:customURL
                                  cached:cached];
    if(self){
        pthread_mutexattr_t mutexattr;
        pthread_mutexattr_init(&mutexattr);
        pthread_mutexattr_settype(&mutexattr, PTHREAD_MUTEX_RECURSIVE);
        pthread_mutex_init(&_plock, &mutexattr);
        _haveDataSaved = NO;
        _offset = requestRange.location;
        _requestLength = requestRange.length;
        _session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration] delegate:self delegateQueue:[NSOperationQueue mainQueue]];
    }
    return self;
}

- (void)start {
    [super start];
    LJDispatchSyncOnMainQueue(^{
        [self internalStart];
    });
}

- (void)startOnQueue:(dispatch_queue_t)queue {
    [super startOnQueue:queue];
    dispatch_async(queue, ^{
        [self internalStart];
    });
}

- (void)internalStart {
    NSMutableURLRequest * request = [NSMutableURLRequest requestWithURL:self.customURL cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:RequestTimeout];
    NSString *rangeValue = [self requestRangeValue:self.requestRange];
    if (rangeValue) {
        [request setValue:rangeValue forHTTPHeaderField:@"Range"];
    }
    self.task = [self.session dataTaskWithRequest:request];
    [self.task resume];
}

- (void)cancel {
    [super cancel];
    if (self.haveDataSaved) {
        [self.cacheFile synchronize];
    }
    if (self.task) {
        JPDebugLog(@"取消了一个网络请求, id 是: %d", self.task.taskIdentifier);
        [self.task cancel];
    }
}

- (NSString *)requestRangeValue:(NSRange)range {
    if (range.location == NSNotFound) {
        return [NSString stringWithFormat:@"bytes=-%tu",range.length];
    }
    else if (range.length == NSUIntegerMax) {
        return [NSString stringWithFormat:@"bytes=%tu-",range.location];
    }
    else {
        return [NSString stringWithFormat:@"bytes=%tu-%tu",range.location, NSMaxRange(range) - 1];
    }
}
- (void)requestDidReceiveResponse:(NSURLResponse *)response {
     if ([response isKindOfClass:[NSHTTPURLResponse class]] && !self.loadingRequest.contentInformationRequest.contentType) {
         NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
         [self.cacheFile storeResponse:httpResponse];
         [self fillContentInformationWithResponse:httpResponse];
         if (![(NSHTTPURLResponse *)response lj_supportRange]) {
             self.offset = 0;
         }
     }
}

- (void)fillContentInformationWithResponse:(NSHTTPURLResponse *)response {
    if (!response || response.expectedContentLength != 2) {
        return;
    }
    NSString *mimeType = [response MIMEType];
    CFStringRef contentType = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, (__bridge CFStringRef)(mimeType), NULL);
    
    self.loadingRequest.contentInformationRequest.byteRangeAccessSupported = ([response allHeaderFields][@"Content-Range"] != nil);
    self.loadingRequest.contentInformationRequest.contentType = CFBridgingRelease(contentType);
    self.loadingRequest.contentInformationRequest.contentLength = [self fileLengthOfResponse:response];
    JPDebugLog(@"step6---填充了响应信息到contentInformationRequest---%@---%ld",self.loadingRequest.contentInformationRequest.contentType,self.loadingRequest.contentInformationRequest.contentLength);
}

- (long long)fileLengthOfResponse:(NSHTTPURLResponse *)response{
    NSString *range = [response allHeaderFields][@"Content-Range"];
    if (range) {
        NSArray *ranges = [range componentsSeparatedByString:@"/"];
        if (ranges.count > 0) {
            NSString *lengthString = [[ranges lastObject] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            return [lengthString longLongValue];
        }
    }
    else {
        return [response expectedContentLength];
    }
    return 0;
}

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
    JPDebugLog(@"step5---URLSession收到响应---mimetype:%@---expectedContentLength:%ld",response.MIMEType,response.expectedContentLength);
    //'304 Not Modified' is an exceptional one.
    if (![response respondsToSelector:@selector(statusCode)] || (((NSHTTPURLResponse *)response).statusCode < 400 && ((NSHTTPURLResponse *)response).statusCode != 304)) {
        BOOL isSupportMIMEType = [response.MIMEType containsString:@"video"] || [response.MIMEType containsString:@"audio"];
        if(!isSupportMIMEType) {
            return;
        }
        [self requestDidReceiveResponse:response];
        if (completionHandler) {
            completionHandler(NSURLSessionResponseAllow);
        }
    }
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
    if (data.bytes) {
        JPDebugLog(@"step6.1---URLSession 请求offset:%lu,收到数据长度为:%lu",self.offset,(unsigned long)data.length);
        [self.cacheFile storeVideoData:data atOffset:self.offset];
        int lock = pthread_mutex_trylock(&_plock);
        self.haveDataSaved = YES;
        self.offset += [data length];
        [self.loadingRequest.dataRequest respondWithData:data];
        if (!lock) {
            pthread_mutex_unlock(&_plock);
        }
    }
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    NSLog(@"test-----------------URLSession complete");
    if (self.delegate && [self.delegate respondsToSelector:@selector(requestTask:didCompleteWithError:)]) {
        [self.delegate requestTask:self didCompleteWithError:error];
    }
    if (self.haveDataSaved) {
        [self.cacheFile synchronize];
    }
}


@end
