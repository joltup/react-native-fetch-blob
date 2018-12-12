//
//  RNFetchBlobProgress.m
//  RNFetchBlob
//
//  Created by Ben Hsieh on 2016/9/25.
//  Copyright © 2016年 wkh237.github.io. All rights reserved.
//

#import "RNFetchBlobProgress.h"

@interface RNFetchBlobProgress ()
{
@private
    int currentCount;
    double lastTick;
}
@end

@implementation RNFetchBlobProgress

- (id)initWithType:(ProgressType)type interval:(float)interval count:(NSInteger)count
{
    self = [super init];
    self.count = count;
    self.interval = interval / 1000;
    self.type = type;
    lastTick = 0;
    currentCount = 0;
    return self;
}

- (BOOL)shouldReportProgress:(float)nextProgress
{
    if (self.count > 0 && nextProgress < (float)currentCount / self.count) {
        return NO;
    }
    NSTimeInterval timeStamp = [[NSDate date] timeIntervalSince1970];
    if (self.interval > 0 && timeStamp - lastTick < self.interval) {
        return NO;
    }
    currentCount++;
    lastTick = timeStamp;
    return YES;
}

@end
