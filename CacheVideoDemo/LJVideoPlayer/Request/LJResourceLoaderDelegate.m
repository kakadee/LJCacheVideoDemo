//
//  LJResourceLoaderDelegate.m
//  CacheVideoDemo
//
//  Created by lijian on 2018/4/25.
//  Copyright © 2018年 lijian. All rights reserved.
//

#import "LJResourceLoaderDelegate.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import "LJResourceLoadingRequestTask.h"
#import "LJSupportUtils.h"
#import "LJVideoPlayerCacheFile.h"

@interface LJResourceLoaderDelegate () <NSURLSessionDataDelegate, LJResourceLoadingRequestTaskDelegate>

@property (nonatomic, strong) NSMutableArray<AVAssetResourceLoadingRequest *> *loadingRequests;
@property (nonatomic, strong) AVAssetResourceLoadingRequest *runningLoadingRequest;
@property (nonatomic, strong) NSMutableArray<LJResourceLoadingRequestTask *> *requestTasks;
@property (nonatomic, strong) LJResourceLoadingRequestTask *runningRequestTask;
@property (nonatomic, strong) LJVideoPlayerCacheFile *cacheFile;

@property (nonatomic, strong, nonnull) dispatch_queue_t ioQueue;

@end

@implementation LJResourceLoaderDelegate

- (instancetype)init {
    NSAssert(NO, @"Please use given initialize method.");
    return [self initWithCustomURL:[NSURL new]];
}
 
- (instancetype)initWithCustomURL:(NSURL *)customURL {
    if (self = [super init]) {
        _customURL = customURL;
        _loadingRequests = [NSMutableArray new];
        _cacheFile = [[LJVideoPlayerCacheFile alloc] initCacheFileWithCustomURL:customURL.absoluteString];
        _ioQueue = dispatch_queue_create("com.tantan.CacheVideoDemo", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

#pragma mark - private
- (void)findAndStartNextLoadingRequestIfNeed {
    if(self.runningLoadingRequest || self.runningRequestTask || self.loadingRequests.count == 0) {
        return;
    }
    self.runningLoadingRequest = [self.loadingRequests firstObject];
    NSRange dataRange = [self fetchRequestRangeWithRequest:self.runningLoadingRequest];
    JPDebugLog(@"step2---开始组装请求---%ld,%ld",dataRange.location,dataRange.length + dataRange.location - 1);
    [self startCurrentRequestWithLoadingRequest:self.runningLoadingRequest
                                          range:dataRange];
    
}

- (NSRange)fetchRequestRangeWithRequest:(AVAssetResourceLoadingRequest *)loadingRequest {
    NSUInteger location, length;
    // data range.
    location = (NSUInteger)loadingRequest.dataRequest.requestedOffset;
    length = loadingRequest.dataRequest.requestedLength;
    if(loadingRequest.dataRequest.currentOffset > 0){
        location = (NSUInteger)loadingRequest.dataRequest.currentOffset;
    }
    return NSMakeRange(location, length);
    
    
}

// 开始新的请求
- (void)startCurrentRequestWithLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest
                                        range:(NSRange)dataRange {
    NSUInteger start = dataRange.location;
    NSUInteger end = NSMaxRange(dataRange);
    while (start < end) {
        NSRange firstNotCachedRange = [self.cacheFile firstNotCachedRangeFromPosition:start];
        JPDebugLog(@"step3---start:%ld---end:%ld---firstNotCachedRange:%ld,%ld",start,end,firstNotCachedRange.location,firstNotCachedRange.length + firstNotCachedRange.location - 1);
        if (!LJValidFileRange(firstNotCachedRange)) {
            [self addTaskWithLoadingRequest:loadingRequest
                                      range:dataRange
                                     cached:self.cacheFile.cachedDataBound > 0];
            start = end;
        }
        else if (firstNotCachedRange.location >= end) {
            [self addTaskWithLoadingRequest:loadingRequest
                                      range:dataRange
                                     cached:YES];
            start = end;
        }
        else if (firstNotCachedRange.location >= start) {
            if (firstNotCachedRange.location > start) {
                [self addTaskWithLoadingRequest:loadingRequest
                                          range:NSMakeRange(start, firstNotCachedRange.location - start)
                                         cached:YES];
            }
            NSUInteger notCachedEnd = MIN(NSMaxRange(firstNotCachedRange), end);
            [self addTaskWithLoadingRequest:loadingRequest
                                      range:NSMakeRange(firstNotCachedRange.location, notCachedEnd - firstNotCachedRange.location)
                                     cached:NO];
            start = notCachedEnd;
        }
        else {
            [self addTaskWithLoadingRequest:loadingRequest
                                      range:dataRange
                                     cached:NO];
            start = end;
        }
    }
    
    [self startNextTaskIfNeed];
}

- (void)addTaskWithLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest
                            range:(NSRange)range
                           cached:(BOOL)cached {
    LJResourceLoadingRequestTask *task;
    if(cached){
        JPDebugLog(@"ccc---ResourceLoader 创建一个本地请求 %ld, %ld",range.location,range.length);
        task = [LJResourceLoadingRequestLocalTask requestTaskWithLoadingRequest:loadingRequest
                                                                   requestRange:range
                                                                      cacheFile:self.cacheFile
                                                                      customURL:self.customURL
                                                                         cached:cached];
    }
    else {
         JPDebugLog(@"ccc---ResourceLoader 创建一个线上请求 %ld, %ld",range.location,range.length);
        task = [LJResourceLoadingRequestWebTask requestTaskWithLoadingRequest:loadingRequest
                                                              requestRange:range
                                                                 cacheFile:self.cacheFile
                                                                 customURL:self.customURL
                                                                    cached:cached];
    }
    task.delegate = self;
    if (!self.requestTasks) {
        self.requestTasks = [@[] mutableCopy];
    }
    [self.requestTasks addObject:task];
    
}


- (void)fillContentInformationWithResponse:(NSHTTPURLResponse *)response {
    if (!response) {
        return;
    }
    NSString *mimeType = [response MIMEType];
    CFStringRef contentType = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, (__bridge CFStringRef)(mimeType), NULL);
    self.runningLoadingRequest.contentInformationRequest.byteRangeAccessSupported = YES;
    self.runningLoadingRequest.contentInformationRequest.contentType = CFBridgingRelease(contentType);
    self.runningLoadingRequest.contentInformationRequest.contentLength = [self fileLengthOfResponse:response];
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

- (void)startNextTaskIfNeed {
    self.runningRequestTask = self.requestTasks.firstObject;

    if ([self.runningRequestTask isKindOfClass:[LJResourceLoadingRequestLocalTask class]]) {
        JPDebugLog(@"step4---开始本地请求---%ld,%ld",self.runningRequestTask.requestRange.location,NSMaxRange(self.runningRequestTask.requestRange)-1);
        [self.runningRequestTask startOnQueue:self.ioQueue];
    }
    else {
         JPDebugLog(@"step4---开始在线请求---%ld,%ld",self.runningRequestTask.requestRange.location,NSMaxRange(self.runningRequestTask.requestRange)-1);
        [self.runningRequestTask start];
    }
}

- (void)finishCurrentRequestWithError:(NSError *)error {
    if (error) {
        NSLog(@"aaa---ResourceLoader 完成一个请求 error: %@", error);
        [self.runningRequestTask.loadingRequest finishLoadingWithError:error];
        [self.loadingRequests removeObject:self.runningLoadingRequest];
        [self removeCurrentRequestTaskAndResetAll];
        [self findAndStartNextLoadingRequestIfNeed];
    }
    else {
        NSLog(@"stepN---ResourceLoader 完成一个请求, 没有错误");
        // 要所有的请求都完成了才行.
        [self.requestTasks removeObject:self.runningRequestTask];
        if(!self.requestTasks.count){ // 全部完成.
            [self.runningRequestTask.loadingRequest finishLoading];
            [self.loadingRequests removeObject:self.runningLoadingRequest];
            [self removeCurrentRequestTaskAndResetAll];
            [self findAndStartNextLoadingRequestIfNeed];
        }
        else { // 完成了一部分, 继续请求.
            [self startNextTaskIfNeed];
        }
    }
}

- (void)removeCurrentRequestTaskAndResetAll {
    self.runningLoadingRequest = nil;
    self.requestTasks = [@[] mutableCopy];
    self.runningRequestTask = nil;
}

# pragma mark - AVAssetResourceLoaderDelegate

- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest *)loadingRequest {
    JPDebugLog(@"step1---截取到loadingRequest---currentoffset:%ld---%ld, %ld",loadingRequest.dataRequest.currentOffset,loadingRequest.dataRequest.requestedOffset,loadingRequest.dataRequest.requestedLength + loadingRequest.dataRequest.requestedOffset - 1);
    if (resourceLoader && loadingRequest){
        [self.loadingRequests addObject:loadingRequest];
        [self findAndStartNextLoadingRequestIfNeed];
    }
    return YES;
}

- (void)resourceLoader:(AVAssetResourceLoader *)resourceLoader
didCancelLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest {
    JPDebugLog(@"stepN---取消请求---%ld, %ld---当前队列:%d,%d",loadingRequest.dataRequest.requestedOffset,loadingRequest.dataRequest.requestedLength + loadingRequest.dataRequest.requestedOffset - 1,self.loadingRequests.count,self.requestTasks.count);
    if ([self.loadingRequests containsObject:loadingRequest]) {
        if(loadingRequest == self.runningLoadingRequest) {
            if(self.runningLoadingRequest && self.runningRequestTask) {
                [self.runningRequestTask cancel];
            }
            if([self.loadingRequests containsObject:self.runningLoadingRequest]) {
                [self.loadingRequests removeObject:self.runningLoadingRequest];
            }
            [self removeCurrentRequestTaskAndResetAll];
            [self findAndStartNextLoadingRequestIfNeed];
        }
        else {
            [self.loadingRequests removeObject:loadingRequest];
        }
    }
    else {
        JPDebugLog(@"test-要取消的请求已经完成了");
    }
}

#pragma mark - LJResourceLoadingRequestTaskDelegate

- (void)requestTask:(LJResourceLoadingRequestTask *)requestTask
didCompleteWithError:(NSError *)error {
    if (error.code == NSURLErrorCancelled) {
        return;
    }
    if (![self.requestTasks containsObject:requestTask]) {
        JPDebugLog(@"完成的 task 不是正在进行的 task");
        return;
    }
    
    if (error) {
        JPDebugLog(@"step7---一个requestTask完成错误:%@---%ld,%ld",error.debugDescription,requestTask.requestRange.location,NSMaxRange(requestTask.requestRange)-1);
        [self finishCurrentRequestWithError:error];
    }
    else {
        JPDebugLog(@"step7---一个requestTask完成---%ld,%ld",requestTask.requestRange.location,requestTask.requestRange.length);
        [self finishCurrentRequestWithError:nil];
    }
}

# pragma mark - setter & getter

@end
