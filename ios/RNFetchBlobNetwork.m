//
//  RNFetchBlobNetwork.m
//  RNFetchBlob
//
//  Created by wkh237 on 2016/6/6.
//  Copyright © 2016 wkh237. All rights reserved.
//


#import <Foundation/Foundation.h>
#import "RNFetchBlob.h"
#import "RNFetchBlobFS.h"
#import "RNFetchBlobNetwork.h"
#import "RNFetchBlobConst.h"
#import "RNFetchBlobReqBuilder.h"
#import "IOS7Polyfill.h"
#import <CommonCrypto/CommonDigest.h>
#import "RNFetchBlobProgress.h"
// #import "AppDelegate.h"
#if __has_include(<React/RCTAssert.h>)
#import <React/RCTRootView.h>
#import <React/RCTLog.h>
#import <React/RCTEventDispatcher.h>
#import <React/RCTBridge.h>
#else
#import "RCTRootView.h"
#import "RCTLog.h"
#import "RCTEventDispatcher.h"
#import "RCTBridge.h"
#endif

////////////////////////////////////////
//
//  HTTP request handler
//
////////////////////////////////////////

NSMapTable * taskTable;
NSMapTable * expirationTable;
NSMutableDictionary * progressTable;
NSMutableDictionary * uploadProgressTable;

__attribute__((constructor))
static void initialize_tables() {
    if(expirationTable == nil)
    {
        expirationTable = [[NSMapTable alloc] init];
    }
    if(taskTable == nil)
    {
        taskTable = [[NSMapTable alloc] init];
    }
    if(progressTable == nil)
    {
        progressTable = [[NSMutableDictionary alloc] init];
    }
    if(uploadProgressTable == nil)
    {
        uploadProgressTable = [[NSMutableDictionary alloc] init];
    }
}


typedef NS_ENUM(NSUInteger, ResponseFormat) {
    UTF8,
    BASE64,
    AUTO
};


@interface RNFetchBlobNetwork ()
{
    BOOL * respFile;
    BOOL isNewPart;
    BOOL * isIncrement;
    NSMutableData * partBuffer;
    NSString * destPath;
    NSOutputStream * writeStream;
    long bodyLength;
    NSMutableDictionary * respInfo;
    NSInteger respStatus;
    NSMutableArray * redirects;
    ResponseFormat responseFormat;
    BOOL * followRedirect;
    BOOL backgroundTask;
    BOOL uploadTask;
    BOOL downloadTask;
}

@end

@implementation RNFetchBlobNetwork

NSOperationQueue *taskQueue;
@synthesize taskId;
@synthesize expectedBytes;
@synthesize receivedBytes;
@synthesize respData;
@synthesize callback;
@synthesize bridge;
@synthesize options;
@synthesize fileTaskCompletionHandler;
@synthesize dataTaskCompletionHandler;
@synthesize error;


// constructor
- (id)init {
    self = [super init];
    if(taskQueue == nil) {
        taskQueue = [[NSOperationQueue alloc] init];
        taskQueue.maxConcurrentOperationCount = 10;
    }
    return self;
}

+ (void) enableProgressReport:(NSString *) taskId config:(RNFetchBlobProgress *)config
{
    if(progressTable == nil)
    {
        progressTable = [[NSMutableDictionary alloc] init];
    }
    [progressTable setValue:config forKey:taskId];
}

+ (void) enableUploadProgress:(NSString *) taskId config:(RNFetchBlobProgress *)config
{
    if(uploadProgressTable == nil)
    {
        uploadProgressTable = [[NSMutableDictionary alloc] init];
    }
    [uploadProgressTable setValue:config forKey:taskId];
}

// removing case from headers
+ (NSMutableDictionary *) normalizeHeaders:(NSDictionary *)headers
{

    NSMutableDictionary * mheaders = [[NSMutableDictionary alloc]init];
    for(NSString * key in headers) {
        [mheaders setValue:[headers valueForKey:key] forKey:[key lowercaseString]];
    }

    return mheaders;
}

- (NSString *)md5:(NSString *)input {
    const char* str = [input UTF8String];
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5(str, (CC_LONG)strlen(str), result);

    NSMutableString *ret = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH*2];
    for(int i = 0; i<CC_MD5_DIGEST_LENGTH; i++) {
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
            callback:(_Nullable RCTResponseSenderBlock) callback
{
    self.taskId = taskId;
    self.respData = [[NSMutableData alloc] initWithLength:0];
    self.callback = callback;
    self.bridge = bridgeRef;
    self.expectedBytes = 0;
    self.receivedBytes = 0;
    self.options = options;
    
    backgroundTask = [options valueForKey:@"IOSBackgroundTask"] == nil ? NO : [[options valueForKey:@"IOSBackgroundTask"] boolValue];
    
     downloadTask = [options valueForKey:@"IOSDownloadTask"] == nil ? NO : [[options valueForKey:@"IOSDownloadTask"] boolValue];
    
     uploadTask = [options valueForKey:@"IOSUploadTask"] == nil ? NO : [[options valueForKey:@"IOSUploadTask"] boolValue];
    
    NSString * filepath = [options valueForKey:@"uploadFilePath"];
    
    followRedirect = [options valueForKey:@"followRedirect"] == nil ? YES : [[options valueForKey:@"followRedirect"] boolValue];
    isIncrement = [options valueForKey:@"increment"] == nil ? NO : [[options valueForKey:@"increment"] boolValue];
    redirects = [[NSMutableArray alloc] init];
    if(req.URL != nil)
        [redirects addObject:req.URL.absoluteString];

    // set response format
    NSString * rnfbResp = [req.allHTTPHeaderFields valueForKey:@"RNFB-Response"];
    if([[rnfbResp lowercaseString] isEqualToString:@"base64"])
        responseFormat = BASE64;
    else if([[rnfbResp lowercaseString] isEqualToString:@"utf8"])
        responseFormat = UTF8;
    else
        responseFormat = AUTO;

    NSString * path = [self.options valueForKey:CONFIG_FILE_PATH];
    NSString * ext = [self.options valueForKey:CONFIG_FILE_EXT];
	NSString * key = [self.options valueForKey:CONFIG_KEY];
   // __block NSURLSession * session;

    bodyLength = contentLength;

    // the session trust any SSL certification
    NSURLSessionConfiguration *defaultConfigObject;

    defaultConfigObject = [NSURLSessionConfiguration defaultSessionConfiguration];

    if(backgroundTask)
    {
        defaultConfigObject = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:taskId];
    }

    // set request timeout
    float timeout = [options valueForKey:@"timeout"] == nil ? -1 : [[options valueForKey:@"timeout"] floatValue];
    if(timeout > 0)
    {
        defaultConfigObject.timeoutIntervalForRequest = timeout/1000;
    }
    defaultConfigObject.HTTPMaximumConnectionsPerHost = 10;
    
    _session = [NSURLSession sessionWithConfiguration:defaultConfigObject delegate:self delegateQueue:taskQueue];
    
    if(path != nil || [self.options valueForKey:CONFIG_USE_TEMP]!= nil)
    {
        respFile = YES;

		NSString* cacheKey = taskId;
		if (key != nil) {
            cacheKey = [self md5:key];
			if (cacheKey == nil) {
				cacheKey = taskId;
			}

			destPath = [RNFetchBlobFS getTempPath:cacheKey withExtension:[self.options valueForKey:CONFIG_FILE_EXT]];
            if ([[NSFileManager defaultManager] fileExistsAtPath:destPath]) {
				callback(@[[NSNull null], RESP_TYPE_PATH, destPath]);
                return;
            }
		}

        if(path != nil)
            destPath = path;
        else
            destPath = [RNFetchBlobFS getTempPath:cacheKey withExtension:[self.options valueForKey:CONFIG_FILE_EXT]];
    }
    else
    {
        respData = [[NSMutableData alloc] init];
        respFile = NO;
    }

    
    if(uploadTask)
    {
        __block NSURLSessionUploadTask * task = [_session uploadTaskWithRequest:req fromFile:[NSURL URLWithString:filepath]];
        [taskTable setObject:task forKey:taskId];
        [task resume];
    }
    else if(downloadTask)
    {
        __block NSURLSessionDownloadTask * task = [_session downloadTaskWithRequest:req];
        [taskTable setObject:task forKey:taskId];
        [task resume];
    }
    else
    {
        __block NSURLSessionDataTask * task = [_session dataTaskWithRequest:req];
        [taskTable setObject:task forKey:taskId];
        [task resume];
    }
    


    // network status indicator
    if([[options objectForKey:CONFIG_INDICATOR] boolValue] == YES)
        [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
    __block UIApplication * app = [UIApplication sharedApplication];

}

// #115 Invoke fetch.expire event on those expired requests so that the expired event can be handled
+ (void) emitExpiredTasks
{
    NSEnumerator * emu =  [expirationTable keyEnumerator];
    NSString * key;

    while((key = [emu nextObject]))
    {
        RCTBridge * bridge = [RNFetchBlob getRCTBridge];
        NSData * args = @{ @"taskId": key };
        [bridge.eventDispatcher sendDeviceEventWithName:EVENT_EXPIRE body:args];

    }

    // clear expired task entries
    [expirationTable removeAllObjects];
    expirationTable = [[NSMapTable alloc] init];

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
    expectedBytes = [response expectedContentLength];

    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse*)response;
    NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
    NSString * respType = @"";
    respStatus = statusCode;
    if ([response respondsToSelector:@selector(allHeaderFields)])
    {
        NSDictionary *headers = [httpResponse allHeaderFields];
        NSString * respCType = [[RNFetchBlobReqBuilder getHeaderIgnoreCases:@"Content-Type" fromHeaders:headers] lowercaseString];
        if(self.isServerPush == NO)
        {
            self.isServerPush = [[respCType lowercaseString] RNFBContainsString:@"multipart/x-mixed-replace;"];
        }
        if(self.isServerPush)
        {
            if(partBuffer != nil)
            {
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
        }
        if(respCType != nil)
        {
            NSArray * extraBlobCTypes = [options objectForKey:CONFIG_EXTRA_BLOB_CTYPE];
            if([respCType RNFBContainsString:@"text/"])
            {
                respType = @"text";
            }
            else if([respCType RNFBContainsString:@"application/json"])
            {
                respType = @"json";
            }
            // If extra blob content type is not empty, check if response type matches
            else if( extraBlobCTypes !=  nil) {
                for(NSString * substr in extraBlobCTypes)
                {
                    if([respCType RNFBContainsString:[substr lowercaseString]])
                    {
                        respType = @"blob";
                        respFile = YES;
                        destPath = [RNFetchBlobFS getTempPath:taskId withExtension:nil];
                        break;
                    }
                }
            }
            else
            {
                respType = @"blob";
                // for XMLHttpRequest, switch response data handling strategy automatically
                if([options valueForKey:@"auto"] == YES) {
                    respFile = YES;
                    destPath = [RNFetchBlobFS getTempPath:taskId withExtension:@""];
                }
            }
        }
        else
            respType = @"text";
        respInfo = @{
                     @"taskId": taskId,
                     @"state": @"2",
                     @"headers": headers,
                     @"redirects": redirects,
                     @"respType" : respType,
                     @"timeout" : @NO,
                     @"status": [NSNumber numberWithInteger:statusCode]
                    };

#pragma mark - handling cookies
        // # 153 get cookies
        if(response.URL != nil)
        {
            NSHTTPCookieStorage * cookieStore = [NSHTTPCookieStorage sharedHTTPCookieStorage];
            NSArray<NSHTTPCookie *> * cookies = [NSHTTPCookie cookiesWithResponseHeaderFields: headers forURL:response.URL];
            if(cookies != nil && [cookies count] > 0) {
                [cookieStore setCookies:cookies forURL:response.URL mainDocumentURL:nil];
            }
        }

        [self.bridge.eventDispatcher
         sendDeviceEventWithName: EVENT_STATE_CHANGE
         body:respInfo
        ];
        headers = nil;
        respInfo = nil;

    }
    else
        NSLog(@"oops");

    /*
    if(respFile == YES)
    {
        @try{
            NSFileManager * fm = [NSFileManager defaultManager];
            NSString * folder = [destPath stringByDeletingLastPathComponent];
            if(![fm fileExistsAtPath:folder])
            {
                [fm createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:NULL error:nil];
            }
            BOOL overwrite = [options valueForKey:@"overwrite"] == nil ? YES : [[options valueForKey:@"overwrite"] boolValue];
            BOOL appendToExistingFile = [destPath RNFBContainsString:@"?append=true"];

            appendToExistingFile = !overwrite;

            // For solving #141 append response data if the file already exists
            // base on PR#139 @kejinliang
            if(appendToExistingFile)
            {
                destPath = [destPath stringByReplacingOccurrencesOfString:@"?append=true" withString:@""];
            }
            if (![fm fileExistsAtPath:destPath])
            {
                [fm createFileAtPath:destPath contents:[[NSData alloc] init] attributes:nil];
            }
            writeStream = [[NSOutputStream alloc] initToFileAtPath:destPath append:appendToExistingFile];
            [writeStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
            [writeStream open];
        }
        @catch(NSException * ex)
        {
            NSLog(@"write file error");
        }
    }
     
     */
    

    completionHandler(NSURLSessionResponseAllow);
}



// data download progress handler
- (void) URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data
{
    // For #143 handling multipart/x-mixed-replace response
    if(self.isServerPush)
    {
        [partBuffer appendData:data];
        return ;
    }

    
    if(respFile == NO)
    {
        
    NSNumber * received = [NSNumber numberWithLong:[data length]];
    receivedBytes += [received longValue];
    NSString * chunkString = @"";

    if(isIncrement == YES)
    {
        chunkString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }

        [respData appendData:data];
        
        RNFetchBlobProgress * pconfig = [progressTable valueForKey:taskId];
        if(expectedBytes == 0)
            return;
        NSNumber * now =[NSNumber numberWithFloat:((float)receivedBytes/(float)expectedBytes)];
        RCTLog(@"check the didReceiveData ----%f %f %@",(float)receivedBytes,(float)expectedBytes,taskId);
        if(pconfig != nil && [pconfig shouldReport:now])
        {
            [self.bridge.eventDispatcher
             sendDeviceEventWithName:EVENT_PROGRESS
             body:@{
                    @"taskId": taskId,
                    @"written": [NSString stringWithFormat:@"%d", receivedBytes],
                    @"total": [NSString stringWithFormat:@"%d", expectedBytes],
                    @"chunk": chunkString
                    }
             ];
        }
        received = nil;
    }
   

}
#pragma mark -
#pragma mark NSURLSessionDownloadTask delegate methods
#pragma mark -

  #pragma mark - download progress handler

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {

    
    
        
        RNFetchBlobProgress * pconfig = [progressTable valueForKey:taskId];
        if(totalBytesWritten == 0)
            return;
        NSNumber * now =[NSNumber numberWithFloat:((double)bytesWritten/(double)totalBytesWritten)];
        RCTLog(@"check the now ----%f %f %@",(double)bytesWritten,(double)totalBytesWritten,taskId);
        if(pconfig != nil && [pconfig shouldReport:now])
        {
            [self.bridge.eventDispatcher
             sendDeviceEventWithName:EVENT_PROGRESS
             body:@{
                    @"taskId": taskId,
                    @"written": [NSString stringWithFormat:@"%d", totalBytesWritten],
                    @"total": [NSString stringWithFormat:@"%d", totalBytesExpectedToWrite]
                    }
             ];
        }
        
 
}

 #pragma mark - handling didFinishDownloadingToURL

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location {
    

   /*
    @try{
        NSFileManager * fm = [NSFileManager defaultManager];
        NSString * folder = [destPath stringByDeletingLastPathComponent];
        if(![fm fileExistsAtPath:folder])
        {
            [fm createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:NULL error:nil];
        }
        BOOL overwrite = [options valueForKey:@"overwrite"] == nil ? YES : [[options valueForKey:@"overwrite"] boolValue];
        BOOL appendToExistingFile = [destPath RNFBContainsString:@"?append=true"];
        
        appendToExistingFile = !overwrite;
        
        // For solving #141 append response data if the file already exists
        // base on PR#139 @kejinliang
        if(appendToExistingFile)
        {
            destPath = [destPath stringByReplacingOccurrencesOfString:@"?append=true" withString:@""];
        }
        if (![fm fileExistsAtPath:destPath])
        {
            [fm createFileAtPath:destPath contents:[[NSData alloc] init] attributes:nil];
        }
        writeStream = [[NSOutputStream alloc] initToFileAtPath:destPath append:appendToExistingFile];
        [writeStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
        [writeStream open];
    }
    @catch(NSException * ex)
    {
        NSLog(@"write file error");
    }
    */
    
    @try{
        NSLog(@"file path : %@", destPath);
        if ([[NSFileManager defaultManager] fileExistsAtPath:destPath]) {
            //Remove the old file from directory
            [[NSFileManager defaultManager] removeItemAtPath:destPath error:NULL];
            
        }
        NSError *error;
        NSURL *documentURL = [NSURL fileURLWithPath:destPath];
        
        [[NSFileManager defaultManager] moveItemAtURL:location
                                                toURL:documentURL
                                                error:&error];
        if (!error){
            
            //Handle error here
            
        }
    }
    @catch(NSException * ex)
    {
        NSLog(@"write file error");
    }
    
    
   
    
}

#pragma mark - URLSessionDidFinishEventsForBackgroundURLSession

/* XXX TODO not entirely sure how to fix AppDelegate reference without hardcoding project in header paths.
- (void) URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session
{
    NSLog(@"sess done in background");
    
    AppDelegate *appDelegate = (AppDelegate*)[[UIApplication sharedApplication]delegate];
    
    // Check if all download tasks have been finished.
    [self.session getTasksWithCompletionHandler:^(NSArray *dataTasks, NSArray *uploadTasks, NSArray *downloadTasks) {
        if ([downloadTasks count] == 0) {
            if (appDelegate.backgroundTransferCompletionHandler != nil) {
                // Copy locally the completion handler.
                void(^completionHandler)() = appDelegate.backgroundTransferCompletionHandler;
                
                // Make nil the backgroundTransferCompletionHandler.
                appDelegate.backgroundTransferCompletionHandler = nil;
                
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    // Call the completion handler to tell the system that there are no other background transfers.
                    completionHandler();
                    
                    // Show a local notification when all downloads are over.
                    UILocalNotification *localNotification = [[UILocalNotification alloc] init];
                    localNotification.alertBody = @"All files have been downloaded!";
                    [[UIApplication sharedApplication] presentLocalNotificationNow:localNotification];
                }];
            }
        }
    }];   
}
*/


   #pragma mark - Complete and Error callback
- (void) URLSession:(NSURLSession *)session didBecomeInvalidWithError:(nullable NSError *)error
{
    if([session isEqual:session])
        session = nil;
}


- (void) URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{

    self.error = error;
    NSString * errMsg = [NSNull null];
    NSString * respStr = [NSNull null];
    NSString * rnfbRespType = @"";

    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];

    if(respInfo == nil)
    {
        respInfo = [NSNull null];
    }

    if(error != nil)
    {
        errMsg = [error localizedDescription];
    }

    if(respFile == YES)
    {
        [writeStream close];
        rnfbRespType = RESP_TYPE_PATH;
        respStr = destPath;
    }
    // base64 response
    else {
        // #73 fix unicode data encoding issue :
        // when response type is BASE64, we should first try to encode the response data to UTF8 format
        // if it turns out not to be `nil` that means the response data contains valid UTF8 string,
        // in order to properly encode the UTF8 string, use URL encoding before BASE64 encoding.
        NSString * utf8 = [[NSString alloc] initWithData:respData encoding:NSUTF8StringEncoding];

        if(responseFormat == BASE64)
        {
            rnfbRespType = RESP_TYPE_BASE64;
            respStr = [respData base64EncodedStringWithOptions:0];
        }
        else if (responseFormat == UTF8)
        {
            rnfbRespType = RESP_TYPE_UTF8;
            respStr = utf8;
        }
        else
        {
            if(utf8 != nil)
            {
                rnfbRespType = RESP_TYPE_UTF8;
                respStr = utf8;
            }
            else
            {
                rnfbRespType = RESP_TYPE_BASE64;
                respStr = [respData base64EncodedStringWithOptions:0];
            }
        }
    }


    callback(@[ errMsg, rnfbRespType, respStr]);

    @synchronized(taskTable, uploadProgressTable, progressTable)
    {
        if([taskTable objectForKey:taskId] == nil)
            NSLog(@"object released by ARC.");
        else
            [taskTable removeObjectForKey:taskId];
        [uploadProgressTable removeObjectForKey:taskId];
        [progressTable removeObjectForKey:taskId];
    }

    respData = nil;
    receivedBytes = 0;
    [session finishTasksAndInvalidate];

}

// upload progress handler
- (void) URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didSendBodyData:(int64_t)bytesSent totalBytesSent:(int64_t)totalBytesWritten totalBytesExpectedToSend:(int64_t)totalBytesExpectedToWrite
{
    RNFetchBlobProgress * pconfig = [uploadProgressTable valueForKey:taskId];
    if(totalBytesExpectedToWrite == 0)
        return;
    NSNumber * now = [NSNumber numberWithFloat:((float)totalBytesWritten/(float)totalBytesExpectedToWrite)];
    if(pconfig != nil && [pconfig shouldReport:now]) {
        [self.bridge.eventDispatcher
         sendDeviceEventWithName:EVENT_PROGRESS_UPLOAD
         body:@{
                @"taskId": taskId,
                @"written": [NSString stringWithFormat:@"%d", totalBytesWritten],
                @"total": [NSString stringWithFormat:@"%d", totalBytesExpectedToWrite]
                }
         ];
    }
}

+ (void) cancelRequest:(NSString *)taskId
{
    NSURLSessionDataTask * task = [taskTable objectForKey:taskId];
    if(task != nil && task.state == NSURLSessionTaskStateRunning)
        [task cancel];
}




   #pragma mark - Authentication methods

- (void) URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable credantial))completionHandler
{
    BOOL trusty = [options valueForKey:CONFIG_TRUSTY];
    if(!trusty)
    {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust]);
    }
    else
    {
        completionHandler(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust]);
    }
}

- (void) URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler
{

    if(followRedirect)
    {
        if(request.URL != nil)
            [redirects addObject:[request.URL absoluteString]];
        completionHandler(request);
    }
    else
    {
        completionHandler(nil);
    }
}


@end
