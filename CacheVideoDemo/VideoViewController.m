//
//  ViewController.m
//  CacheVideoDemo
//
//  Created by lijian on 2018/4/17.
//  Copyright © 2018年 lijian. All rights reserved.
//

#import "VideoViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <AFNetworking.h>
#import "LJResourceLoaderDelegate.h"
#import "LJSupportUtils.h"

@interface VideoViewController () <AVAssetResourceLoaderDelegate>

@property (nonatomic, strong) NSMutableArray<AVAssetResourceLoadingRequest *> *loadingRequests;

@property (nonatomic, strong) AVAssetResourceLoadingRequest *runningLoadingRequest;

@property (nonatomic, strong) LJResourceLoaderDelegate *resourceLoaderDelegate;

@property (nonatomic, strong) AVURLAsset *asset;

@property (nonatomic, strong) AVPlayerItem *playerItem;

@property (nonatomic, strong) AVPlayer *player;

@property (nonatomic, strong) AVQueuePlayer *queuePlayer;

@property (nonatomic, strong) AVPlayerLayer *playerLayer;

@property (nonatomic, strong) AVPlayerViewController *playerVC;

@end

@implementation VideoViewController

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self reset];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSURL *url = [NSURL URLWithString: @"http://wvideo.spriteapp.cn/video/2016/0328/56f8ec01d9bfe_wpd.mp4"];
    
    NSURL *assetURL = [NSURL URLWithString:[@"_test_" stringByAppendingString:[url absoluteString]]];
    self.resourceLoaderDelegate = [[LJResourceLoaderDelegate alloc] initWithCustomURL:url];
    self.asset = [AVURLAsset URLAssetWithURL:assetURL options:nil];
    [self.asset.resourceLoader setDelegate:self.resourceLoaderDelegate queue:dispatch_get_global_queue(0, 0)];
    self.playerItem = [AVPlayerItem playerItemWithAsset:self.asset];

    
//    AVPlayerItem *item1 = [AVPlayerItem playerItemWithURL:[NSURL URLWithString:@"http://p11s9kqxf.bkt.clouddn.com/english.mp4"]];
    NSArray *items = @[self.playerItem];
    self.queuePlayer = [[AVQueuePlayer alloc] initWithItems:items];
    
    //    self.player = [AVPlayer playerWithPlayerItem:self.playerItem];
    self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.queuePlayer];
    self.playerLayer.frame = self.view.bounds;
    [self.view.layer addSublayer:self.playerLayer];
    
    self.playerVC = [[AVPlayerViewController alloc] init];
    self.playerVC.player = self.queuePlayer;
    self.playerVC.videoGravity = AVLayerVideoGravityResizeAspect;
    self.playerVC.showsPlaybackControls = YES;
    self.playerVC.view.frame = self.view.bounds;
    [self addChildViewController:self.playerVC];
    [self.view addSubview:self.playerVC.view];
    [self.playerVC.player play];
    
//    [item1 addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
    //    [item2 addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
    
    //
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // (metadata 在尾部）
   
    
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    AVPlayerItem *playerItem = (AVPlayerItem *)object;
    NSLog(@"duration:%d--%lld",playerItem.duration.timescale,playerItem.duration.value);
    if ([keyPath isEqualToString:@"status"]) {
        if (playerItem.status == AVPlayerItemStatusReadyToPlay) {
            NSLog(@"bbbb---status:%ld 可以播放了",(long)playerItem.status);
            [self.playerVC.player play];
//            [self.queuePlayer insertItem:self.playerItem afterItem:self.queuePlayer.items.lastObject];
        }
    }
}

- (void)reset {
    self.resourceLoaderDelegate = nil;
    self.asset = nil;
    self.playerItem = nil;
    self.queuePlayer = nil;
    self.playerVC = nil;
}
@end
