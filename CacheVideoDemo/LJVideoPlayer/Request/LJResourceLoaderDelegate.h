//
//  LJResourceLoaderDelegate.h
//  CacheVideoDemo
//
//  Created by lijian on 2018/4/25.
//  Copyright © 2018年 lijian. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface LJResourceLoaderDelegate : NSObject <AVAssetResourceLoaderDelegate>

@property (nonatomic, strong, readonly) NSURL *customURL;

- (instancetype)initWithCustomURL:(NSURL *)customURL NS_DESIGNATED_INITIALIZER;


@end
