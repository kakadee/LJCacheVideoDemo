//
//  LJVideoPlayerCache.h
//  CacheVideoDemo
//
//  Created by lijian on 2018/5/23.
//  Copyright © 2018年 lijian. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LJVideoPlayerCacheConfiguration : NSObject

/**
 * The maximum length of time to keep an video in the cache, in seconds
 */
@property (assign, nonatomic) NSInteger maxCacheAge;

/**
 * The maximum size of the cache, in bytes.
 * If the cache Beyond this value, it will delete the video file by the cache time automatic.
 */
@property (assign, nonatomic) NSUInteger maxCacheSize;

/**
 *  disable iCloud backup [defaults to YES]
 */
@property (assign, nonatomic) BOOL shouldDisableiCloud;

@end

typedef NS_ENUM(NSInteger, LJVideoPlayerCacheType)   {
    
    /**
     * The video wasn't available the LJVideoPlayer caches, but was downloaded from the web.
     */
    LJVideoPlayerCacheTypeNone,
    
    /**
     * The video was obtained on the disk cache, and the video is cache finished.
     */
    LJVideoPlayerCacheTypeFull,
    
    /**
     * The video was obtained on the disk cache, but the video does not cache finish.
     */
    LJVideoPlayerCacheTypeFragment,
    
    /**
     * A location video.
     */
    LJVideoPlayerCacheTypeLocation
};

typedef void(^LJVideoPlayerCacheQueryCompletion)(NSString * _Nullable videoPath, LJVideoPlayerCacheType cacheType);

typedef void(^LJVideoPlayerCheckCacheCompletion)(BOOL isInDiskCache);

typedef void(^LJVideoPlayerCalculateSizeCompletion)(NSUInteger fileCount, NSUInteger totalSize);

/**
 * LJVideoPlayerCache maintains a disk cache. Disk cache write operations are performed
 * asynchronous so it doesn’t add unnecessary latency to the UI.
 */
@interface LJVideoPlayerCache : NSObject

#pragma mark - Singleton and initialization

/**
 *  Cache Config object - storing all kind of settings.
 */
@property (nonatomic, readonly) LJVideoPlayerCacheConfiguration *cacheConfiguration;

/**
 * Init with given cacheConfig.
 *
 * @see `LJVideoPlayerCacheConfig`.
 */
- (instancetype)initWithCacheConfiguration:(LJVideoPlayerCacheConfiguration * _Nullable)cacheConfiguration NS_DESIGNATED_INITIALIZER;

/**
 * Returns global shared cache instance.
 *
 * @return LJVideoPlayerCache global instance.
 */
+ (instancetype)sharedCache;

# pragma mark - Query and Retrieve Options
/**
 * Async check if video exists in disk cache already (does not load the video).
 *
 * @param key             The key describing the url.
 * @param completion      The block to be executed when the check is done.
 * @note the completion block will be always executed on the main queue.
 */
- (void)diskVideoExistsWithKey:(NSString *)key
                    completion:(LJVideoPlayerCheckCacheCompletion _Nullable)completion;

/**
 * Operation that queries the cache asynchronously and call the completion when done.
 *
 * @param key        The unique key used to store the wanted video.
 * @param completion The completion block. Will not get called if the operation is cancelled.
 */
- (void)queryCacheOperationForKey:(NSString *)key
                       completion:(LJVideoPlayerCacheQueryCompletion _Nullable)completion;

/**
 * Async check if video exists in disk cache already (does not load the video).
 *
 * @param path The path need to check in disk.
 *
 * @return If the file is existed for given video path, return YES, return NO, otherwise.
 */
- (BOOL)diskVideoExistsOnPath:(NSString *)path;

# pragma mark - Clear Cache Events

/**
 * Remove the video data from disk cache asynchronously
 *
 * @param key         The unique video cache key.
 * @param completion  A block that should be executed after the video has been removed (optional).
 */
- (void)removeVideoCacheForKey:(NSString *)key
                    completion:(dispatch_block_t _Nullable)completion;

/**
 * Async remove all expired cached video from disk. Non-blocking method - returns immediately.
 *
 * @param completion A block that should be executed after cache expiration completes (optional)
 */
- (void)deleteOldFilesOnCompletion:(dispatch_block_t _Nullable)completion;

/**
 * Async clear all disk cached videos. Non-blocking method - returns immediately.
 *
 * @param completion    A block that should be executed after cache expiration completes (optional).
 */
- (void)clearDiskOnCompletion:(dispatch_block_t _Nullable)completion;

# pragma mark - Cache Info

/**
 * To check is have enough free size in disk to cache file with given size.
 *
 * @param fileSize  the need to cache size of file.
 *
 * @return if the disk have enough size to cache the given size file, return YES, return NO otherwise.
 */
- (BOOL)haveFreeSizeToCacheFileWithSize:(NSUInteger)fileSize;

/**
 * Get the free size of device.
 *
 * @return the free size of device.
 */
- (unsigned long long)getDiskFreeSize;

/**
 * Get the size used by the disk cache, synchronously.
 */
- (unsigned long long)getSize;

/**
 * Get the number of images in the disk cache, synchronously.
 */
- (NSUInteger)getDiskCount;

/**
 * Calculate the disk cache's size, asynchronously .
 */
- (void)calculateSizeOnCompletion:(LJVideoPlayerCalculateSizeCompletion _Nullable)completion;

@end

NS_ASSUME_NONNULL_END

