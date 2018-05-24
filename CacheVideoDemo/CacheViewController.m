//
//  CacheViewController.m
//  CacheVideoDemo
//
//  Created by lijian on 2018/5/23.
//  Copyright © 2018年 lijian. All rights reserved.
//

#import "CacheViewController.h"
#import "LJVideoPlayerCache.h"

@interface CacheViewController ()
@property (weak, nonatomic) IBOutlet UIButton *clearButton;
@property (weak, nonatomic) IBOutlet UILabel *textLabel;

@end

@implementation CacheViewController

- (IBAction)clearButtonClick:(id)sender {
    __weak typeof(self) weakSelf = self;
    // Clear all cache.
    // 清空所有缓存
    [[LJVideoPlayerCache sharedCache] clearDiskOnCompletion:^{
        NSLog(@"clear disk finished, 清空磁盘完成");
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf calculateCacheMes];
    }];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Do any additional setup after loading the view from its nib.
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self calculateCacheMes];
}

- (void)calculateCacheMes{
    __weak typeof(self) weakSelf = self;
    
    // Count all cache size.
    // 计算缓存大小
    [[LJVideoPlayerCache sharedCache] calculateSizeOnCompletion:^(NSUInteger fileCount, NSUInteger totalSize) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        NSString *cacheStr = [NSString stringWithFormat:@"总缓存大小: %0.2fMB", (unsigned long) totalSize / 1024. / 1024.];
        
        strongSelf.textLabel.text = cacheStr;
    }];
}


@end
