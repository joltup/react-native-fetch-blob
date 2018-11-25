//
//  RNFetchBlobProgress.h
//  RNFetchBlob
//
//  Created by Ben Hsieh on 2016/9/25.
//  Copyright © 2016年 wkh237.github.io. All rights reserved.
//

#ifndef RNFetchBlobProgress_h
#define RNFetchBlobProgress_h

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, ProgressType) {
    ProgressTypeDownload,
    ProgressTypeUpload,
};

@interface RNFetchBlobProgress : NSObject

@property (nonatomic) NSInteger count;
@property (nonatomic) float interval;
@property (nonatomic) ProgressType type;

- (id)initWithType:(ProgressType)type interval:(float)interval count:(NSInteger)count;
- (BOOL)shouldReportProgress:(float)nextProgress;

@end

#endif /* RNFetchBlobProgress_h */
