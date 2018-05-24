//
//  LJVideoPlayerCacheFile.m
//  CacheVideoDemo
//
//  Created by lijian on 2018/4/26.
//  Copyright © 2018年 lijian. All rights reserved.
//

#import "LJVideoPlayerCacheFile.h"
#import "LJSupportUtils.h"
#import <pthread.h>
#import <CommonCrypto/CommonDigest.h>
const NSRange LJInvalidRange = {NSNotFound, 0};

static NSString * const kLJVideoPlayerCachePath = @"/LJVideoPlayerCache";
static NSString * const kLJVideoPlayerCacheVideoFileExtension = @".mp4";
static NSString * const kLJVideoPlayerCacheVideoIndexExtension = @".index";

static const NSString *kLJVideoPlayerCacheFileZoneKey = @"kLJVideoPlayerCacheFileZoneKey";
static const NSString *kLJVideoPlayerCacheFileSizeKey = @"kLJVideoPlayerCacheFileSizeKey";
static const NSString *kLJVideoPlayerCacheFileResponseHeadersKey = @"kLJVideoPlayerCacheFileResponseHeadersKey";

@interface LJVideoPlayerCacheFile()

@property (nonatomic, strong) NSMutableArray<NSValue *> *internalFragmentRanges;

@property (nonatomic, strong) NSFileHandle *writeFileHandle;

@property (nonatomic, strong) NSFileHandle *readFileHandle;

@property(nonatomic, assign) BOOL completed;

@property (nonatomic, assign) NSUInteger fileLength;

@property (nonatomic, assign) NSUInteger readOffset;

@property (nonatomic, copy) NSDictionary *responseHeaders;

@property (nonatomic) pthread_mutex_t lock;

@end

@implementation LJVideoPlayerCacheFile

#pragma mark - Init
- (void)dealloc {
    [self.readFileHandle closeFile];
    [self.writeFileHandle closeFile];
    pthread_mutex_destroy(&_lock);
}

- (instancetype)init {
    NSAssert(NO, @"Please use given initializer method");
    return [self initCacheFileWithCustomURL:@""];
}

- (instancetype)initCacheFileWithCustomURL:(NSString *)customURLStr {
    if (!customURLStr || customURLStr.length == 0) {
        return nil;
    }
    self = [super init];
    if (self) {
        pthread_mutexattr_t mutexattr;
        pthread_mutexattr_init(&mutexattr);
        pthread_mutexattr_settype(&mutexattr, PTHREAD_MUTEX_RECURSIVE);
        pthread_mutex_init(&_lock, &mutexattr);
        _internalFragmentRanges = [[NSMutableArray alloc] init];
        _cacheFilePath = [self createCacheFilePathWithURL:customURLStr andSuffix:kLJVideoPlayerCacheVideoFileExtension];
        _indexFilePath = [self createCacheFilePathWithURL:customURLStr andSuffix:kLJVideoPlayerCacheVideoIndexExtension];
        _readFileHandle = [NSFileHandle fileHandleForReadingAtPath:_cacheFilePath];
        _writeFileHandle = [NSFileHandle fileHandleForWritingAtPath:_cacheFilePath];
        
        NSString *indexStr = [NSString stringWithContentsOfFile:self.indexFilePath encoding:NSUTF8StringEncoding error:nil];
        NSData *data = [indexStr dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *indexDictionary = [NSJSONSerialization JSONObjectWithData:data
                                                                        options:NSJSONReadingMutableContainers | NSJSONReadingAllowFragments
                                                                          error:nil];
        if (![self serializeIndex:indexDictionary]) {
            [self truncateFileWithFileLength:0];
        }
        [self checkIsCompleted];
    }
    return self;
}

- (NSString *)createCacheFilePathWithURL:(NSString *)urlStr andSuffix:(NSString *)suffixStr{
    NSString *videoCachePath = [self createvideoCachePathIfNeed];
    NSString *filePath = [videoCachePath stringByAppendingPathComponent:[self cachedFileNameForKey:urlStr]];
    filePath = [filePath stringByAppendingString:suffixStr];
    JPDebugLog(@"filepath222222:%@",filePath);
    if(!filePath){
        return nil;
    }
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:filePath]) {
        [fileManager createFileAtPath:filePath contents:nil attributes:nil];
    }
    return filePath;
}

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

#pragma mark - Properties
- (NSUInteger)cachedDataBound {
    if (self.internalFragmentRanges.count > 0) {
        NSRange range = [[self.internalFragmentRanges lastObject] rangeValue];
        return NSMaxRange(range);
    }
    return 0;
}

#pragma mark - Store data
- (BOOL)truncateFileWithFileLength:(NSUInteger)fileLength {
    JPDebugLog(@"Truncate file to length: %u", fileLength);
    if (!self.writeFileHandle) {
        return NO;
    }
    self.fileLength = fileLength;
    @try {
        [self.writeFileHandle truncateFileAtOffset:self.fileLength * sizeof(Byte)];
        unsigned long long end = [self.writeFileHandle seekToEndOfFile];
        if (end != self.fileLength) {
            return NO;
        }
    }
    @catch (NSException * e) {
        JPErrorLog(@"Truncate file raise a exception: %@", e);
        return NO;
    }
    return YES;
}

- (BOOL)storeVideoData:(NSData *)data atOffset:(NSUInteger)offset {
    @try {
        [self.writeFileHandle seekToFileOffset:offset];
        [self.writeFileHandle lj_safeWriteData:data];
    }
    @catch (NSException * e) {
        JPErrorLog(@"Write file raise a exception: %@", e);
    }
    
    [self addRange:NSMakeRange(offset, [data length])];
    [self synchronize];
}

- (BOOL)storeResponse:(NSHTTPURLResponse *)response {
    BOOL success = YES;
    if (![self isFileLengthValid]) {
        success = [self truncateFileWithFileLength:(NSUInteger)response.lj_fileLength];
    }
    self.responseHeaders = [[response allHeaderFields] copy];
    success = success && [self synchronize];
    return success;
}

#pragma mark - range

- (NSRange)firstNotCachedRangeFromPosition:(NSUInteger)position {
    if (position >= self.fileLength) {
        return LJInvalidRange;
    }
    
    NSRange targetRange = LJInvalidRange;
    NSUInteger start = position;
    for (int i = 0; i < self.internalFragmentRanges.count; ++i) {
        NSRange range = [self.internalFragmentRanges[i] rangeValue];
        if (NSLocationInRange(start, range)) {
            start = NSMaxRange(range);
        }
        else {
            if (start >= NSMaxRange(range)) {
                continue;
            }
            else {
                targetRange = NSMakeRange(start, range.location - start);
            }
        }
    }
    
    if (start < self.fileLength) {
        targetRange = NSMakeRange(start, self.fileLength - start);
    }
    return targetRange;
}

- (NSRange)cachedRangeForRange:(NSRange)range {
    return range;
}

- (void)addRange:(NSRange)range {
    if (range.length == 0 || range.location >= self.fileLength) {
        return;
    }
    
    LJDispatchSyncOnMainQueue(^{
        int lock = pthread_mutex_trylock(&self->_lock);
        BOOL inserted = NO;
        for (int i = 0; i < self.internalFragmentRanges.count; ++i) {
            NSRange currentRange = [self.internalFragmentRanges[i] rangeValue];
            if (currentRange.location >= range.location) {
                [self.internalFragmentRanges insertObject:[NSValue valueWithRange:range] atIndex:i];
                inserted = YES;
                break;
            }
        }
        if (!inserted) {
            [self.internalFragmentRanges addObject:[NSValue valueWithRange:range]];
        }
        if (!lock) {
            pthread_mutex_unlock(&self->_lock);
        }
        for (int i = 0; i < self.internalFragmentRanges.count; i++) {
//            JPDebugLog(@"ttt---addrange--%@",self.internalFragmentRanges[i]);
        }
        [self mergeRangesIfNeed];
        for (int i = 0; i < self.internalFragmentRanges.count; i++) {
//            JPDebugLog(@"ttt-----merge--%@",self.internalFragmentRanges[i]);
        }
        [self checkIsCompleted];
        
    });
}

- (void)mergeRangesIfNeed {
    int lock = pthread_mutex_trylock(&_lock);
    for (int i = 0; i < self.internalFragmentRanges.count; ++i) {
        if ((i + 1) < self.internalFragmentRanges.count) {
            NSRange currentRange = [self.internalFragmentRanges[i] rangeValue];
            NSRange nextRange = [self.internalFragmentRanges[i + 1] rangeValue];
            if (LJRangeCanMerge(currentRange, nextRange)) {
                [self.internalFragmentRanges removeObjectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(i, 2)]];
                [self.internalFragmentRanges insertObject:[NSValue valueWithRange:NSUnionRange(currentRange, nextRange)] atIndex:i];
                i -= 1;
            }
        }
    }
    if (!lock) {
        pthread_mutex_unlock(&_lock);
    }
}

BOOL LJRangeCanMerge(NSRange range1, NSRange range2) {
    return (NSMaxRange(range1) == range2.location) || (NSMaxRange(range2) == range1.location) || NSIntersectionRange(range1, range2).length > 0;
}

- (void)checkIsCompleted {
    int lock = pthread_mutex_trylock(&_lock);
    self.completed = NO;
    if (self.internalFragmentRanges && self.internalFragmentRanges.count == 1) {
        NSRange range = [self.internalFragmentRanges[0] rangeValue];
        if (range.location == 0 && (range.length == self.fileLength)) {
            self.completed = YES;
            JPDebugLog(@"check--range--%ld,%ld",range.location,range.length);
//            [NSFileManager.defaultManager removeItemAtPath:self.indexFilePath error:nil];
        }
    }
    
    if (!lock) {
        pthread_mutex_unlock(&_lock);
    }
}

#pragma mark - read data
- (NSData *)dataWithRange:(NSRange)range {
    if (!LJValidFileRange(range)) {
        return nil;
    }
    
    if (self.readOffset != range.location) {
        [self seekToPosition:range.location];
    }
    
    return [self readDataWithLength:range.length];
}

- (NSData *)readDataWithLength:(NSUInteger)length {
    NSRange range = [self cachedRangeForRange:NSMakeRange(self.readOffset, length)];
    if (LJValidFileRange(range)) {
        int lock = pthread_mutex_trylock(&_lock);
        NSData *data = [self.readFileHandle readDataOfLength:range.length];
        self.readOffset += [data length];
        if (!lock) {
            pthread_mutex_unlock(&_lock);
        }
        return data;
    }
    return nil;
}

#pragma mark - seek data
- (void)seekToPosition:(NSUInteger)position {
    int lock = pthread_mutex_trylock(&_lock);
    [self.readFileHandle seekToFileOffset:position];
    self.readOffset = (NSUInteger)self.readFileHandle.offsetInFile;
    if (!lock) {
        pthread_mutex_unlock(&_lock);
    }
}

- (void)seekToEnd {
    int lock = pthread_mutex_trylock(&_lock);
    [self.readFileHandle seekToEndOfFile];
    self.readOffset = (NSUInteger)self.readFileHandle.offsetInFile;
    if (!lock) {
        pthread_mutex_unlock(&_lock);
    }
}

#pragma mark - synchronize
- (NSString *)unserializeIndex {
    int lock = pthread_mutex_trylock(&_lock);
    NSMutableArray *rangeArray = [[NSMutableArray alloc] init];
    for (NSValue *range in self.internalFragmentRanges) {
        [rangeArray addObject:NSStringFromRange([range rangeValue])];
    }
    NSMutableDictionary *dict = [@{
                                   kLJVideoPlayerCacheFileSizeKey: @(self.fileLength),
                                   kLJVideoPlayerCacheFileZoneKey: rangeArray
                                   } mutableCopy];
    
    if (self.responseHeaders) {
        dict[kLJVideoPlayerCacheFileResponseHeadersKey] = self.responseHeaders;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
    if (data) {
        NSString *dataString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!lock) {
            pthread_mutex_unlock(&_lock);
        }
        return dataString;
    }
    if (!lock) {
        pthread_mutex_unlock(&_lock);
    }
    return nil;
}

- (BOOL)serializeIndex:(NSDictionary *)indexDictionary {
    if (![indexDictionary isKindOfClass:[NSDictionary class]]) {
        return NO;
    }
    
    int lock = pthread_mutex_trylock(&_lock);
    NSNumber *fileSize = indexDictionary[kLJVideoPlayerCacheFileSizeKey];
    if (fileSize && [fileSize isKindOfClass:[NSNumber class]]) {
        self.fileLength = [fileSize unsignedIntegerValue];
    }
    
    if (self.fileLength == 0) {
        if (!lock) {
            pthread_mutex_unlock(&_lock);
        }
        return NO;
    }
    
    [self.internalFragmentRanges removeAllObjects];
    NSMutableArray *rangeArray = indexDictionary[kLJVideoPlayerCacheFileZoneKey];
    for (NSString *rangeStr in rangeArray) {
        NSRange range = NSRangeFromString(rangeStr);
        [self.internalFragmentRanges addObject:[NSValue valueWithRange:range]];
    }
    self.responseHeaders = indexDictionary[kLJVideoPlayerCacheFileResponseHeadersKey];
    if (!lock) {
        pthread_mutex_unlock(&_lock);
    }
    return YES;
}

- (BOOL)synchronize {
    NSString *indexString = [self unserializeIndex];
    int lock = pthread_mutex_trylock(&_lock);
//    JPDebugLog(@"Did synchronize index file");
    [self.writeFileHandle synchronizeFile];
    BOOL synchronize = YES;
    if (!self.isCompeleted) {
        synchronize = [indexString writeToFile:self.indexFilePath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }
    if (!lock) {
        pthread_mutex_unlock(&_lock);
    }
    return synchronize;
}
@end
