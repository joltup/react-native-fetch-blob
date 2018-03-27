//
//  RNFetchBlobReqBuilder.h
//  RNFetchBlob
//
//  Created by Ben Hsieh on 2016/7/9.
//  Copyright © 2016年 wkh237. All rights reserved.
//

#ifndef RNFetchBlobReqBuilder_h
#define RNFetchBlobReqBuilder_h

#import <Foundation/Foundation.h>

@interface RNFetchBlobReqBuilder : NSObject;

+(void) buildMultipartRequest:(NSDictionary *)options
                       taskId:(NSString *)taskId
                       method:(NSString *)method
                          url:(NSString *)url
                      headers:(NSDictionary *)headers
                         form:(NSArray *)form
                   onComplete:(void(^)(NSURLRequest * req, long bodyLength))onComplete;

+(void) buildOctetRequest:(NSDictionary *)options
                   taskId:(NSString *)taskId
                   method:(NSString *)method
                      url:(NSString *)url
                  headers:(NSDictionary *)headers
                     body:(NSString *)body
               onComplete:(void(^)(NSURLRequest * req, long bodyLength))onComplete;

+(NSString *) getHeaderIgnoreCases:(NSString *)field fromHeaders:(NSDictionary *) headers;


@end

#endif /* RNFetchBlobReqBuilder_h */
