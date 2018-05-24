//
//  LJVideoPlayerCache.m
//  CacheVideoDemo
//
//  Created by lijian on 2018/5/23.
//  Copyright © 2018年 lijian. All rights reserved.
//

#import "LJVideoPlayerCache.h"
#include <sys/param.h>
#include <sys/mount.h>
#import <CommonCrypto/CommonDigest.h>
#import <pthread.h>
#import "LJSupportUtils.h"

static const NSInteger kDefaultCacheMaxCacheAge = 60*60*24*7; // 1 week
static const NSInteger kDefaultCacheMaxSize = 1000*1000*1000; // 1 GB

static NSString * const kLJVideoPlayerCachePath = @"/LJVideoPlayerCache";
static NSString * const kLJVideoPlayerCacheVideoFileExtension = @".mp4";
static NSString * const kLJVideoPlayerCacheVideoIndexExtension = @".index";

@implementation LJVideoPlayerCacheConfiguration

- (instancetype)init{
    self = [super init];
    if (self) {
        _maxCacheAge =  kDefaultCacheMaxCacheAge;
        _maxCacheSize = kDefaultCacheMaxSize;
    }
    return self;
}

@end

@interface LJVideoPlayerCache()

@property (nonatomic, strong, nonnull) dispatch_queue_t ioQueue;

@property (nonatomic, strong) NSFileManager *fileManager;

@end

static NSString *kJPVideoPlayerVersion2CacheHasBeenClearedKey = @"com.newpan.version2.cache.clear.key.www";
@implementation LJVideoPlayerCache

- (instancetype)initWithCacheConfiguration:(LJVideoPlayerCacheConfiguration *_Nullable)cacheConfiguration {
    self = [super init];
    if (self) {
        // Create IO serial queue
        _ioQueue = dispatch_queue_create("com.tantan.CacheVideoDemo", DISPATCH_QUEUE_SERIAL);
        LJVideoPlayerCacheConfiguration *configuration = cacheConfiguration;
        if (!configuration) {
            configuration = [[LJVideoPlayerCacheConfiguration alloc] init];
        }
        _cacheConfiguration = configuration;
        _fileManager = [NSFileManager defaultManager];
        
    }
    return self;
}

- (instancetype)init{
    NSAssert(NO, @"please use given init method");
    return [self initWithCacheConfiguration:nil];
}

+ (nonnull instancetype)sharedCache {
    static dispatch_once_t once;
    static id instance;
    dispatch_once(&once, ^{
        instance = [[self alloc] initWithCacheConfiguration:nil];
    });
    return instance;
}

#pragma mark - Query and Retrieve Options

- (NSString *)createvideoCachePathIfNeed {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *path = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).lastObject
                      stringByAppendingPathComponent:kLJVideoPlayerCachePath];
    if (![fileManager fileExistsAtPath:path]) {
        [fileManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return path;
}

- (NSString *)cachedFileNameForKey:(NSString *)key {
    NSParameterAssert(key);
    if(!key){
        return nil;
    }
    const char *str = key.UTF8String;
    if (str == NULL) str = "";
    unsigned char r[CC_MD5_DIGEST_LENGTH];
    CC_MD5(str, (CC_LONG)strlen(str), r);
    NSString *filename = [NSString stringWithFormat:@"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
                          r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9], r[10],
                          r[11], r[12], r[13], r[14], r[15]];
    return filename;
}

- (NSString *)videoCachePathForKey:(NSString *)key {
    if (!key) {
        return nil;
    }
    NSString *videoCachePath = [self createvideoCachePathIfNeed];
    NSString *filePath = [videoCachePath stringByAppendingPathComponent:[self cachedFileNameForKey:key]];
    filePath = [filePath stringByAppendingString:kLJVideoPlayerCacheVideoFileExtension];
    NSLog(@"filepath:%@",filePath);
    return filePath;
}

- (void)diskVideoExistsWithKey:(NSString *)key
                    completion:(LJVideoPlayerCheckCacheCompletion)completion {
    dispatch_async(_ioQueue, ^{
        BOOL exists = [self.fileManager fileExistsAtPath:[self videoCachePathForKey:key]];
        if (completion) {
            LJDispatchSyncOnMainQueue(^{
                completion(exists);
            });
        }
    });
}

- (void)queryCacheOperationForKey:(NSString *)key
                       completion:(LJVideoPlayerCacheQueryCompletion _Nullable)completion {
    if (!key) {
        if (completion) {
            LJDispatchSyncOnMainQueue(^{
                completion(nil, LJVideoPlayerCacheTypeNone);
            });
        }
        return;
    }
    
    dispatch_async(self.ioQueue, ^{
        @autoreleasepool {
            BOOL exists = [self.fileManager fileExistsAtPath:[self videoCachePathForKey:key]];
            if(!exists){
                if (completion) {
                    LJDispatchSyncOnMainQueue(^{
                        completion(nil, LJVideoPlayerCacheTypeNone);
                    });
                }
                return;
            }
            
            // we will remove index file when cache video finished, so we can judge video is cached finished or not by index file existed or not.
            BOOL isCacheFull = ![self.fileManager fileExistsAtPath:[self videoCachePathForKey:key]];
            if(isCacheFull){
                if (completion) {
                    LJDispatchSyncOnMainQueue(^{
                        completion([self videoCachePathForKey:key], LJVideoPlayerCacheTypeFull);
                    });
                }
                return;
            }
            
            if (completion) {
                LJDispatchSyncOnMainQueue(^{
                    completion([self videoCachePathForKey:key], LJVideoPlayerCacheTypeFragment);
                });
            }
        }
    });
}

- (BOOL)diskVideoExistsOnPath:(NSString *)path {
    return [self.fileManager fileExistsAtPath:path];
}

#pragma mark - Clear Cache Events

- (void)removeVideoCacheForKey:(NSString *)key
                    completion:(dispatch_block_t _Nullable)completion {
    dispatch_async(self.ioQueue, ^{
        if ([self.fileManager fileExistsAtPath:[self videoCachePathForKey:key]]) {
            [self.fileManager removeItemAtPath:[self videoCachePathForKey:key] error:nil];
            [self.fileManager removeItemAtPath:[self videoCachePathForKey:key] error:nil];
            LJDispatchSyncOnMainQueue(^{
                if (completion) {
                    completion();
                }
            });
        }
    });
}

- (void)deleteOldFilesOnCompletion:(dispatch_block_t _Nullable)completion {
    dispatch_async(self.ioQueue, ^{
        NSURL *diskCacheURL = [NSURL fileURLWithPath:[self createvideoCachePathIfNeed] isDirectory:YES];
        NSArray<NSString *> *resourceKeys = @[NSURLIsDirectoryKey, NSURLContentModificationDateKey, NSURLTotalFileAllocatedSizeKey];
        
        // This enumerator prefetches useful properties for our cache files.
        NSDirectoryEnumerator *fileEnumerator = [self.fileManager enumeratorAtURL:diskCacheURL
                                                       includingPropertiesForKeys:resourceKeys
                                                                          options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                     errorHandler:NULL];
        
        NSDate *expirationDate = [NSDate dateWithTimeIntervalSinceNow:-self.cacheConfiguration.maxCacheAge];
        NSMutableDictionary<NSURL *, NSDictionary<NSString *, id> *> *cacheFiles = [NSMutableDictionary dictionary];
        NSUInteger currentCacheSize = 0;
        
        // Enumerate all of the files in the cache directory.  This loop has two purposes:
        //
        //  1. Removing files that are older than the expiration date.
        //  2. Storing file attributes for the size-based cleanup pass.
        NSMutableArray<NSURL *> *urlsToDelete = [[NSMutableArray alloc] init];
        
        @autoreleasepool {
            for (NSURL *fileURL in fileEnumerator) {
                NSError *error;
                NSDictionary<NSString *, id> *resourceValues = [fileURL resourceValuesForKeys:resourceKeys error:&error];
                
                // Skip directories and errors.
                if (error || !resourceValues || [resourceValues[NSURLIsDirectoryKey] boolValue]) {
                    continue;
                }
                
                // Remove files that are older than the expiration date;
                NSDate *modificationDate = resourceValues[NSURLContentModificationDateKey];
                if ([[modificationDate laterDate:expirationDate] isEqualToDate:expirationDate]) {
                    [urlsToDelete addObject:fileURL];
                    continue;
                }
                
                // Store a reference to this file and account for its total size.
                NSNumber *totalAllocatedSize = resourceValues[NSURLTotalFileAllocatedSizeKey];
                currentCacheSize += totalAllocatedSize.unsignedIntegerValue;
                cacheFiles[fileURL] = resourceValues;
            }
        }
        
        for (NSURL *fileURL in urlsToDelete) {
            [self.fileManager removeItemAtURL:fileURL error:nil];
        }
        
        // If our remaining disk cache exceeds a configured maximum size, perform a second
        // size-based cleanup pass.  We delete the oldest files first.
        if (self.cacheConfiguration.maxCacheSize > 0 && currentCacheSize > self.cacheConfiguration.maxCacheSize) {
            // Target half of our maximum cache size for this cleanup pass.
            const NSUInteger desiredCacheSize = self.cacheConfiguration.maxCacheSize / 2;
            
            // Sort the remaining cache files by their last modification time (oldest first).
            NSArray<NSURL *> *sortedFiles = [cacheFiles keysSortedByValueWithOptions:NSSortConcurrent
                                                                     usingComparator:^NSComparisonResult(id obj1, id obj2) {
                                                                         return [obj1[NSURLContentModificationDateKey] compare:obj2[NSURLContentModificationDateKey]];
                                                                     }];
            
            // Delete files until we fall below our desired cache size.
            for (NSURL *fileURL in sortedFiles) {
                if ([self.fileManager removeItemAtURL:fileURL error:nil]) {
                    NSDictionary<NSString *, id> *resourceValues = cacheFiles[fileURL];
                    NSNumber *totalAllocatedSize = resourceValues[NSURLTotalFileAllocatedSizeKey];
                    currentCacheSize -= totalAllocatedSize.unsignedIntegerValue;
                    
                    if (currentCacheSize < desiredCacheSize) {
                        break;
                    }
                }
            }
        }
        if (completion) {
            LJDispatchSyncOnMainQueue(^{
                completion();
            });
        }
    });
}

- (void)clearDiskOnCompletion:(nullable dispatch_block_t)completion{
    dispatch_async(self.ioQueue, ^{
        [self.fileManager removeItemAtPath:[self createvideoCachePathIfNeed] error:nil];
        LJDispatchSyncOnMainQueue(^{
            if (completion) {
                completion();
            }
        });
    });
}

#pragma mark - Cache Info

- (BOOL)haveFreeSizeToCacheFileWithSize:(NSUInteger)fileSize{
    unsigned long long freeSizeOfDevice = [self getDiskFreeSize];
    if (fileSize > freeSizeOfDevice) {
        return NO;
    }
    return YES;
}

- (unsigned long long)getSize {
    __block unsigned long long size = 0;
    NSString *videoCachePath = [self createvideoCachePathIfNeed];
    @autoreleasepool {
        NSDirectoryEnumerator *fileEnumerator_video = [self.fileManager enumeratorAtPath:videoCachePath];
        for (NSString *fileName in fileEnumerator_video) {
            NSString *filePath = [videoCachePath stringByAppendingPathComponent:fileName];
            NSDictionary<NSString *, id> *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
            size += [attrs fileSize];
        }
    }
    return size;
}

- (NSUInteger)getDiskCount{
    __block NSUInteger count = 0;
    NSString *videoCachePath = [self createvideoCachePathIfNeed];
    NSDirectoryEnumerator *fileEnumerator_video = [self.fileManager enumeratorAtPath:videoCachePath];
    count += fileEnumerator_video.allObjects.count;
    return count;
}

- (void)calculateSizeOnCompletion:(LJVideoPlayerCalculateSizeCompletion _Nullable)completion {
    NSString *videoFilePath = [self createvideoCachePathIfNeed];
    NSURL *diskCacheURL_video = [NSURL fileURLWithPath:videoFilePath isDirectory:YES];
    
    dispatch_async(self.ioQueue, ^{
        NSUInteger fileCount = 0;
        NSUInteger totalSize = 0;
        
        NSDirectoryEnumerator *fileEnumerator_video = [self.fileManager enumeratorAtURL:diskCacheURL_video includingPropertiesForKeys:@[NSFileSize] options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:NULL];
        for (NSURL *fileURL in fileEnumerator_video) {
            NSNumber *fileSize;
            [fileURL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:NULL];
            totalSize += fileSize.unsignedIntegerValue;
            fileCount += 1;
        }
        
        if (completion) {
            LJDispatchSyncOnMainQueue(^{
                completion(fileCount, totalSize);
            });
        }
    });
}

- (unsigned long long)getDiskFreeSize{
    struct statfs buf;
    unsigned long long freespace = -1;
    if(statfs("/var", &buf) >= 0){
        freespace = (long long)(buf.f_bsize * buf.f_bfree);
    }
    return freespace;
}

#pragma mark - Private

- (void)deleteOldFiles {
    [self deleteOldFilesOnCompletion:nil];
}

@end
