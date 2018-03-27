//
//  RNFetchBlob.h
//
//  Created by wkh237 on 2016/4/28.
//

//XXX: DO NO REMOVE THIS LINE IF YOU'RE USING IT ON RN > 0.40 PROJECT



#ifndef RNFetchBlob_h
#define RNFetchBlob_h


#if __has_include(<React/RCTAssert.h>)
#import <React/RCTLog.h>
#import <React/RCTRootView.h>
#import <React/RCTBridge.h>
#import <React/RCTEventDispatcher.h>
#import <React/RCTBridgeModule.h>
#else
#import "RCTBridgeModule.h"
#import "RCTLog.h"
#import "RCTRootView.h"
#import "RCTBridge.h"
#import "RCTEventDispatcher.h"
#endif

#import <UIKit/UIKit.h>


@interface RNFetchBlob : NSObject <RCTBridgeModule, UIDocumentInteractionControllerDelegate> {

    NSString * filePathPrefix;

}

@property (nonatomic) NSString * filePathPrefix;
@property (retain) UIDocumentInteractionController * documentController;

+ (RCTBridge *)getRCTBridge;

@end

#endif /* RNFetchBlob_h */
