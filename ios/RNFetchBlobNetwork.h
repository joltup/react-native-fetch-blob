//
//  RNFetchBlobNetwork.h
//  RNFetchBlob
//
//  Created by wkh237 on 2016/6/6.
//  Copyright © 2016 wkh237. All rights reserved.
//

#ifndef RNFetchBlobNetwork_h
#define RNFetchBlobNetwork_h

#import <Foundation/Foundation.h>
#import "RNFetchBlobProgress.h"
#import "RNFetchBlobFS.h"
#import "RNFetchBlobRequest.h"

#if __has_include(<React/RCTAssert.h>)
#import <React/RCTBridgeModule.h>
#else
#import "RCTBridgeModule.h"
#endif


@interface RNFetchBlobNetwork : NSObject  <NSURLSessionDelegate, NSURLSessionTaskDelegate, NSURLSessionDataDelegate>

@property(nonnull, nonatomic) NSOperationQueue *taskQueue;
@property(nonnull, nonatomic) NSMapTable<NSString*, RNFetchBlobRequest*> * requestsTable;

+ (RNFetchBlobNetwork* _Nullable)sharedInstance;
+ (NSMutableDictionary  * _Nullable ) normalizeHeaders:(NSDictionary * _Nullable)headers;
+ (void) emitExpiredTasks;

- (nullable id) init;
- (void) sendRequest:(NSDictionary  * _Nullable )options
       contentLength:(long)contentLength
              bridge:(RCTBridge * _Nullable)bridgeRef
              taskId:(NSString * _Nullable)taskId
         withRequest:(NSURLRequest * _Nullable)req
            callback:(_Nullable RCTResponseSenderBlock) callback;
- (void) cancelRequest:(NSString * _Nonnull)taskId;
- (void) enableProgressReport:(NSString * _Nonnull) taskId config:(RNFetchBlobProgress * _Nullable)config;
- (void) enableUploadProgress:(NSString * _Nonnull) taskId config:(RNFetchBlobProgress * _Nullable)config;


@end


#endif /* RNFetchBlobNetwork_h */
