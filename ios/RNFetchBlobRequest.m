//
//  RNFetchBlobRequest.m
//  RNFetchBlob
//
//  Created by Artur Chrusciel on 15.01.18.
//  Copyright © 2018 wkh237.github.io. All rights reserved.
//

#import "RNFetchBlobRequest.h"

#import "RNFetchBlobFS.h"
#import "RNFetchBlobConst.h"
#import "RNFetchBlobReqBuilder.h"
#if __has_include(<React/RCTLog.h>)
#import <React/RCTLog.h>
#else
#import "RCTLog.h"
#endif

#import "IOS7Polyfill.h"
#import <CommonCrypto/CommonDigest.h>

NSMapTable * taskTable;

__attribute__((constructor))
static void initialize_tables() {
    if(taskTable == nil)
    {
        taskTable = [[NSMapTable alloc] init];
    }
}

typedef NS_ENUM(NSUInteger, ResponseFormat) {
    UTF8,
    BASE64,
    AUTO
};

@interface RNFetchBlobRequest ()
{
    BOOL respFile;
    BOOL isNewPart;
    BOOL isIncrement;
    NSMutableData * partBuffer;
    NSString * destPath;
    NSOutputStream * writeStream;
    long bodyLength;
    NSInteger respStatus;
    NSMutableArray * redirects;
    ResponseFormat responseFormat;
    BOOL followRedirect;
    BOOL backgroundTask;
    BOOL uploadTask;
}

@end

@implementation RNFetchBlobRequest

@synthesize taskId;
@synthesize expectedBytes;
@synthesize receivedBytes;
@synthesize respData;
@synthesize callback;
@synthesize bridge;
@synthesize options;
@synthesize error;


- (NSString *)md5:(NSString *)input {
    const char* str = [input UTF8String];
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5(str, (CC_LONG)strlen(str), result);
    
    NSMutableString *ret = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH*2];
    for (int i = 0; i<CC_MD5_DIGEST_LENGTH; i++) {
        [ret appendFormat:@"%02x",result[i]];
    }
    return ret;
}

// send HTTP request
- (void) sendRequest:(__weak NSDictionary  * _Nullable )options
       contentLength:(long) contentLength
              bridge:(RCTBridge * _Nullable)bridgeRef
              taskId:(NSString * _Nullable)taskId
         withRequest:(__weak NSURLRequest * _Nullable)req
  taskOperationQueue:(NSOperationQueue * _Nonnull)operationQueue
            callback:(_Nullable RCTResponseSenderBlock) callback
{
    self.taskId = taskId;
    self.respData = [[NSMutableData alloc] initWithLength:0];
    self.callback = callback;
    self.bridge = bridgeRef;
    self.expectedBytes = 0;
    self.receivedBytes = 0;
    self.options = options;
    
    backgroundTask = [[options valueForKey:@"IOSBackgroundTask"] boolValue];
    uploadTask = [options valueForKey:@"IOSUploadTask"] == nil ? NO : [[options valueForKey:@"IOSUploadTask"] boolValue];
    
    NSString * filepath = [options valueForKey:@"uploadFilePath"];

    if (uploadTask && ![[NSFileManager defaultManager] fileExistsAtPath:[NSURL URLWithString:filepath].path]) {
        RCTLog(@"[RNFetchBlobRequest] sendRequest uploadTask file doesn't exist %@", filepath);
        callback(@[@"uploadTask file doesn't exist", @"", [NSNull null]]);
        return;
    }
    
    // when followRedirect not set in options, defaults to TRUE
    followRedirect = [options valueForKey:@"followRedirect"] == nil ? YES : [[options valueForKey:@"followRedirect"] boolValue];
    isIncrement = [[options valueForKey:@"increment"] boolValue];
    redirects = [[NSMutableArray alloc] init];
    
    if (req.URL) {
        [redirects addObject:req.URL.absoluteString];
    }
    
    // set response format
    NSString * rnfbResp = [req.allHTTPHeaderFields valueForKey:@"RNFB-Response"];
    
    if ([[rnfbResp lowercaseString] isEqualToString:@"base64"]) {
        responseFormat = BASE64;
    } else if ([[rnfbResp lowercaseString] isEqualToString:@"utf8"]) {
        responseFormat = UTF8;
    } else {
        responseFormat = AUTO;
    }
    
    NSString * path = [self.options valueForKey:CONFIG_FILE_PATH];
    NSString * key = [self.options valueForKey:CONFIG_KEY];
    
    bodyLength = contentLength;
    
    // the session trust any SSL certification
    NSURLSessionConfiguration *defaultConfigObject;
    
    defaultConfigObject = [NSURLSessionConfiguration defaultSessionConfiguration];
    
    if (backgroundTask) {
        defaultConfigObject = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:taskId];
    }
    
    
    // request timeout, -1 if not set in options
    float timeout = [options valueForKey:@"timeout"] == nil ? -1 : [[options valueForKey:@"timeout"] floatValue];
    
    if (timeout > 0) {
        defaultConfigObject.timeoutIntervalForRequest = timeout/1000;
    }
    
    defaultConfigObject.HTTPMaximumConnectionsPerHost = 10;
    _session = [NSURLSession sessionWithConfiguration:defaultConfigObject delegate:self delegateQueue:operationQueue];
    
    if (path || [self.options valueForKey:CONFIG_USE_TEMP]) {
        respFile = YES;
        
        NSString* cacheKey = taskId;
        if (key) {
            cacheKey = [self md5:key];
            
            if (!cacheKey) {
                cacheKey = taskId;
            }
            
            destPath = [RNFetchBlobFS getTempPath:cacheKey withExtension:[self.options valueForKey:CONFIG_FILE_EXT]];
            
            if ([[NSFileManager defaultManager] fileExistsAtPath:destPath]) {
                callback(@[[NSNull null], RESP_TYPE_PATH, destPath]);
                
                return;
            }
        }
        
        if (path) {
            destPath = path;
        } else {
            destPath = [RNFetchBlobFS getTempPath:cacheKey withExtension:[self.options valueForKey:CONFIG_FILE_EXT]];
        }
    } else {
        respData = [[NSMutableData alloc] init];
        respFile = NO;
    }
    
    __block NSURLSessionTask * task;
    
    if(uploadTask)
    {
        task = [_session uploadTaskWithRequest:req fromFile:[NSURL URLWithString:filepath]];
    }
    else
    {
        task = [_session dataTaskWithRequest:req];
    }
    
    [taskTable setObject:task forKey:taskId];
    [task resume];
    
    // network status indicator
    if ([[options objectForKey:CONFIG_INDICATOR] boolValue]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
        });
    }
}

////////////////////////////////////////
//
//  NSURLSession delegates
//
////////////////////////////////////////


#pragma mark NSURLSession delegate methods


#pragma mark - Received Response
// set expected content length on response received
- (void) URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler
{
    NSLog(@"sess didReceiveResponse");
    expectedBytes = [response expectedContentLength];
    
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse*)response;
    NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
    NSString * respType = @"";
    respStatus = statusCode;
    
    if ([response respondsToSelector:@selector(allHeaderFields)])
    {
        NSDictionary *headers = [httpResponse allHeaderFields];
        NSString * respCType = [[RNFetchBlobReqBuilder getHeaderIgnoreCases:@"Content-Type" fromHeaders:headers] lowercaseString];
        
        if (self.isServerPush) {
            if (partBuffer) {
                [self.bridge.eventDispatcher
                 sendDeviceEventWithName:EVENT_SERVER_PUSH
                 body:@{
                        @"taskId": taskId,
                        @"chunk": [partBuffer base64EncodedStringWithOptions:0],
                        }
                 ];
            }
            
            partBuffer = [[NSMutableData alloc] init];
            completionHandler(NSURLSessionResponseAllow);
            
            return;
        } else {
            self.isServerPush = [[respCType lowercaseString] RNFBContainsString:@"multipart/x-mixed-replace;"];
        }
        
        if(respCType)
        {
            NSArray * extraBlobCTypes = [options objectForKey:CONFIG_EXTRA_BLOB_CTYPE];
            
            if ([respCType RNFBContainsString:@"text/"]) {
                respType = @"text";
            } else if ([respCType RNFBContainsString:@"application/json"]) {
                respType = @"json";
            } else if(extraBlobCTypes) { // If extra blob content type is not empty, check if response type matches
                for (NSString * substr in extraBlobCTypes) {
                    if ([respCType RNFBContainsString:[substr lowercaseString]]) {
                        respType = @"blob";
                        respFile = YES;
                        destPath = [RNFetchBlobFS getTempPath:taskId withExtension:nil];
                        break;
                    }
                }
            } else {
                respType = @"blob";
                
                // for XMLHttpRequest, switch response data handling strategy automatically
                if ([options valueForKey:@"auto"]) {
                    respFile = YES;
                    destPath = [RNFetchBlobFS getTempPath:taskId withExtension:@""];
                }
            }
        } else {
            respType = @"text";
        }
        
#pragma mark - handling cookies
        // # 153 get cookies
        if (response.URL) {
            NSHTTPCookieStorage * cookieStore = [NSHTTPCookieStorage sharedHTTPCookieStorage];
            NSArray<NSHTTPCookie *> * cookies = [NSHTTPCookie cookiesWithResponseHeaderFields: headers forURL:response.URL];
            if (cookies.count) {
                [cookieStore setCookies:cookies forURL:response.URL mainDocumentURL:nil];
            }
        }
        
        [self.bridge.eventDispatcher
         sendDeviceEventWithName: EVENT_STATE_CHANGE
         body:@{
                @"taskId": taskId,
                @"state": @"2",
                @"headers": headers,
                @"redirects": redirects,
                @"respType" : respType,
                @"timeout" : @NO,
                @"status": [NSNumber numberWithInteger:statusCode]
                }
         ];
    } else {
        NSLog(@"oops");
    }
    
    completionHandler(NSURLSessionResponseAllow);
}


// download progress handler
- (void) URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data
{
    // For #143 handling multipart/x-mixed-replace response
    if (self.isServerPush)
    {
        [partBuffer appendData:data];
        
        return ;
    }
    
    NSNumber * received = [NSNumber numberWithLong:[data length]];
    receivedBytes += [received longValue];
    NSString * chunkString = @"";
    
    if (isIncrement) {
        chunkString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    
    [respData appendData:data];
    
    if (expectedBytes == 0) {
        return;
    }
    
    float progress = (float)receivedBytes / (float)expectedBytes;
    
    if ([self.progressConfig shouldReportProgress:progress]) {
        [self.bridge.eventDispatcher
         sendDeviceEventWithName:EVENT_PROGRESS
         body:@{
                @"taskId": taskId,
                @"written": [NSString stringWithFormat:@"%lld", (long long) receivedBytes],
                @"total": [NSString stringWithFormat:@"%lld", (long long) expectedBytes],
                @"chunk": chunkString
                }
         ];
    }
}

- (void) cancelRequest:(NSString *)taskId
{
    NSURLSessionDataTask * task = [taskTable objectForKey:taskId];
    if(task != nil && task.state == NSURLSessionTaskStateRunning)
        [task cancel];
}

- (void) URLSession:(NSURLSession *)session didBecomeInvalidWithError:(nullable NSError *)error
{
    RCTLog(@"[RNFetchBlobRequest] session didBecomeInvalidWithError %@", [error description]);
    if ([session isEqual:session]) {
        session = nil;
    }
}


- (void) URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    RCTLog(@"[RNFetchBlobRequest] session didCompleteWithError %@", [error description]);
    self.error = error;
    NSString * errMsg;
    NSString * respStr;
    NSString * rnfbRespType;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
    });
    
    if (error) {
        if (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled) {
            errMsg = @"task cancelled";
        } else {
            errMsg = [error localizedDescription];
        }
    }
    
    if (respFile) {
        [writeStream close];
        rnfbRespType = RESP_TYPE_PATH;
        respStr = destPath;
    } else { // base64 response
        // #73 fix unicode data encoding issue :
        // when response type is BASE64, we should first try to encode the response data to UTF8 format
        // if it turns out not to be `nil` that means the response data contains valid UTF8 string,
        // in order to properly encode the UTF8 string, use URL encoding before BASE64 encoding.
        NSString * utf8 = [[NSString alloc] initWithData:respData encoding:NSUTF8StringEncoding];
        
        if (responseFormat == BASE64) {
            rnfbRespType = RESP_TYPE_BASE64;
            respStr = [respData base64EncodedStringWithOptions:0];
        } else if (responseFormat == UTF8) {
            rnfbRespType = RESP_TYPE_UTF8;
            respStr = utf8;
        } else {
            if (utf8) {
                rnfbRespType = RESP_TYPE_UTF8;
                respStr = utf8;
            } else {
                rnfbRespType = RESP_TYPE_BASE64;
                respStr = [respData base64EncodedStringWithOptions:0];
            }
        }
    }
    
    
    callback(@[
               errMsg ?: [NSNull null],
               rnfbRespType ?: @"",
               respStr ?: [NSNull null]
               ]);
    
    @synchronized(taskTable)
    {
        if([taskTable objectForKey:taskId] == nil)
            NSLog(@"object released by ARC.");
        else
            [taskTable removeObjectForKey:taskId];
    }
    
    respData = nil;
    receivedBytes = 0;
    [session finishTasksAndInvalidate];
}

// upload progress handler
- (void) URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didSendBodyData:(int64_t)bytesSent totalBytesSent:(int64_t)totalBytesWritten totalBytesExpectedToSend:(int64_t)totalBytesExpectedToWrite
{
    if (totalBytesExpectedToWrite == 0) {
        return;
    }
    
    float progress = (float)totalBytesWritten / (float) totalBytesExpectedToWrite;
    
    if ([self.uploadProgressConfig shouldReportProgress:progress]) {
        [self.bridge.eventDispatcher
         sendDeviceEventWithName:EVENT_PROGRESS_UPLOAD
         body:@{
                @"taskId": taskId,
                @"written": [NSString stringWithFormat:@"%ld", (long) totalBytesWritten],
                @"total": [NSString stringWithFormat:@"%ld", (long) totalBytesExpectedToWrite]
                }
         ];
    }
}


- (void) URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable credantial))completionHandler
{
    if ([[options valueForKey:CONFIG_TRUSTY] boolValue]) {
        completionHandler(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust]);
    } else {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust]);
    }
}


- (void) URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session
{
    RCTLog(@"[RNFetchBlobRequest] session done in background");
    dispatch_async(dispatch_get_main_queue(), ^{
        id<UIApplicationDelegate> appDelegate = [UIApplication sharedApplication].delegate;
        SEL selector = NSSelectorFromString(@"backgroundTransferCompletionHandler");
        if ([appDelegate respondsToSelector:selector]) {
            void(^completionHandler)() = [appDelegate performSelector:selector];
            if (completionHandler != nil) {
                completionHandler();
                completionHandler = nil;
            }
        }
        
    });
}

- (void) URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler
{
    
    if (followRedirect) {
        if (request.URL) {
            [redirects addObject:[request.URL absoluteString]];
        }
        
        completionHandler(request);
    } else {
        completionHandler(nil);
    }
}


@end
