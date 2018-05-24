//
//  LJVideoPlayerCacheFile.h
//  CacheVideoDemo
//
//  Created by lijian on 2018/4/26.
//  Copyright © 2018年 lijian. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LJVideoPlayerCacheFile : NSObject

@property (nonatomic, copy, readonly) NSString *cacheFilePath;

@property (nonatomic, copy, readonly, nullable) NSString *indexFilePath;

@property (nonatomic, assign, readonly) NSUInteger fileLength;

@property (nonatomic, copy, readonly, nullable) NSDictionary *responseHeaders;

@property (nonatomic, assign, readonly) NSUInteger readOffset;

@property (nonatomic, strong, readonly, nullable) NSArray<NSValue *> *fragmentRanges;

@property (nonatomic, readonly) BOOL isCompeleted;

@property (nonatomic, readonly) BOOL isEOF;

@property (nonatomic, readonly) BOOL isFileLengthValid;

@property (nonatomic, readonly) NSUInteger cachedDataBound;

#pragma mark - Init
- (instancetype)initCacheFileWithCustomURL:(NSString *)customURLStr NS_DESIGNATED_INITIALIZER;

- (BOOL)synchronize;

#pragma mark - Store
- (BOOL)storeVideoData:(NSData *)data atOffset:(NSUInteger)offset;

- (BOOL)storeResponse:(NSHTTPURLResponse *)response;

- (NSRange)cachedRangeForRange:(NSRange)range;

#pragma mark - Read
- (NSData * _Nullable)readDataWithLength:(NSUInteger)length;

- (NSData *)dataWithRange:(NSRange)range;

#pragma mark - Range
- (NSRange)firstNotCachedRangeFromPosition:(NSUInteger)position;

@end
