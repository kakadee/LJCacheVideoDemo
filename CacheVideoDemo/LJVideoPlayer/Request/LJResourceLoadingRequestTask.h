//
//  LJResourceLoadingRequestTask.h
//  CacheVideoDemo
//
//  Created by lijian on 2018/4/26.
//  Copyright © 2018年 lijian. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@class LJVideoPlayerCacheFile;
@class LJResourceLoadingRequestTask;

@protocol LJResourceLoadingRequestTaskDelegate<NSObject>

@optional

- (void)requestTask:(LJResourceLoadingRequestTask *)requestTask
didCompleteWithError:(NSError *)error;

@end

@interface LJResourceLoadingRequestTask : NSObject

@property (nonatomic, weak) id<LJResourceLoadingRequestTaskDelegate> delegate;

@property (nonatomic, strong) AVAssetResourceLoadingRequest *loadingRequest;

@property(nonatomic, assign, readonly) NSRange requestRange;

@property (nonatomic, strong, readonly) LJVideoPlayerCacheFile *cacheFile;

@property (nonatomic, strong, readonly) NSURL *customURL;

- (instancetype)initWithLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest
                          requestRange:(NSRange)requestRange
                             cacheFile:(LJVideoPlayerCacheFile *)cacheFile
                             customURL:(NSURL *)customURL
                                cached:(BOOL)cached;

+ (instancetype)requestTaskWithLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest
                                 requestRange:(NSRange)requestRange
                                    cacheFile:(LJVideoPlayerCacheFile *)cacheFile
                                    customURL:(NSURL *)customURL
                                       cached:(BOOL)cached;

- (void)start NS_REQUIRES_SUPER;

- (void)startOnQueue:(dispatch_queue_t)queue NS_REQUIRES_SUPER;

- (void)cancel NS_REQUIRES_SUPER;

@end

@interface LJResourceLoadingRequestLocalTask: LJResourceLoadingRequestTask

@end

@interface LJResourceLoadingRequestWebTask: LJResourceLoadingRequestTask

@end
