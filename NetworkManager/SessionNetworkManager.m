//
//  SessionNetworkManager.m
//  NetworkManager
//
//  Created by maru on 2015/08/30.
//  Copyright (c) 2015年 maru. All rights reserved.
//

#import "SessionNetworkManager.h"
#import "Reachability.h"


static NSString* const refreshPath = @"refresh";
static NSString* const resultPath  = @"result";

typedef void (^retryBlock_t)(NSURLSessionDataTask* task, NSError* error);
typedef void (^refreshBlock_t)(NSURLSessionDataTask* task, NSError* error);

@interface SessionNetworkManager () <NSURLSessionDelegate>

@property (nonatomic, strong) NSURLSession* session;
@property (nonatomic) Reachability *reachability;

- (NSURLSessionDataTask*)requestUrlWithRetryCount:(NSInteger)retryCount
                                    retryInterval:(NSInteger)retryInteval
                          refreshWhenTokenExpired:(BOOL)refreshWhenTokenExpired
                                       taskCreate:(NSURLSessionDataTask *(^)(retryBlock_t, refreshBlock_t))taskCreate failure:(void(^)(NSURLSessionDataTask *, NSError *))failure;

@end

@implementation SessionNetworkManager 

static SessionNetworkManager* sharedInstance = nil;

+ (SessionNetworkManager*)shared {
    
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        sharedInstance = [[SessionNetworkManager alloc] init];
        sharedInstance.allowInvalidCertification = YES;
        sharedInstance.baseURL = @"http://localhost:4567";
    });
    
    return sharedInstance;
}

- (instancetype)init {
//    self = [super initWithBaseURL:[NSURL URLWithString:@"http://localhost:4567"]];
//    if (self) {
//        self.requestSerializer = [AFHTTPRequestSerializer serializer];
//        self.responseSerializer = [AFJSONResponseSerializer serializer];
//    }
    
    self = [super init];
    if (self) {
        NSURLSessionConfiguration* configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        self.session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
        self.reachability  = [Reachability reachabilityForInternetConnection];
    }
    return self;
}


- (void)requestRefresh:(void (^)(BOOL isSuccess, NSError* error))completionBlock {
    
    [self requestUrlWithRetryCount:0 retryInterval:0 refreshWhenTokenExpired:NO taskCreate:^NSURLSessionDataTask* (retryBlock_t retryBlock, refreshBlock_t refreshBlock) {
        
        return [self POST:refreshPath parameters:nil success:^(NSURLSessionDataTask* refreshTask, id refreshResponse) {
            
            NSDictionary* jsonObject = [NSJSONSerialization JSONObjectWithData:refreshResponse options:NSJSONReadingAllowFragments error:nil];
            
            if (jsonObject[@"error_cd"]) {
                
                completionBlock(NO, [[NSError alloc] initWithDomain:@"system_error" code:1 userInfo:nil]);
                
                return;
            }
            
            completionBlock(YES, nil);
            
        } failure:retryBlock];
        
    } failure:^(NSURLSessionDataTask* task, NSError* error){
        
        completionBlock(NO, error);
        
    }];
    
}

- (void)requestResult:(void (^)(BOOL isSuccess, NSError* error))completionBlock  {
    
    NetworkStatus networkStatus = [_reachability currentReachabilityStatus];
    if (networkStatus == NotReachable) {
        completionBlock(NO, [[NSError alloc] initWithDomain:@"network connection error" code:1 userInfo:nil]);
        return;
    }
    
    [self requestUrlWithRetryCount:10 retryInterval:1 refreshWhenTokenExpired:YES taskCreate:^NSURLSessionDataTask* (retryBlock_t retryBlock, refreshBlock_t refreshBlock) {
        
        return [self POST:resultPath parameters:nil success:^(NSURLSessionDataTask* resultTask, id resultResponse) {
            
            NSLog(@"result ok -> %@", resultResponse);
            
            NSDictionary* jsonObject = [NSJSONSerialization JSONObjectWithData:resultResponse options:NSJSONReadingAllowFragments error:nil];
            NSLog(@"json: %@", jsonObject);
            
            if ([jsonObject[@"error_cd"] isEqualToString:@"401"]) {
                
                NSLog(@"token_error");
                refreshBlock(resultTask, [[NSError alloc] initWithDomain:@"token_error" code:1 userInfo:nil]);
                
                return;
            }
            
            completionBlock(YES, nil);
            
        } failure:retryBlock];
        
    } failure:^(NSURLSessionDataTask* task, NSError* error){
        
        NSLog(@"error: %@", error);
        
    }];
    
}

- (NSURLSessionDataTask *)POST:(NSString *)URLString
                    parameters:(id)parameters
                       success:(void (^)(NSURLSessionDataTask *task, id responseObject))success
                       failure:(void (^)(NSURLSessionDataTask *task, NSError *error))failure
{
    
    NSURL* url = [NSURL URLWithString:URLString relativeToURL:[NSURL URLWithString:self.baseURL]];
    
    NSLog(@"url: %@", [url absoluteString]);
    NSMutableURLRequest* request = [[NSMutableURLRequest alloc] initWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData timeoutInterval:30.0];
    
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSURLSessionDataTask *dataTask = [self.session dataTaskWithRequest:request
                                                completionHandler:^(NSData * data, NSURLResponse * __unused response, NSError *error) {
                                                    
                                                    NSLog(@"error");
                                                    if (error) {
                                                        if (failure) {
                                                            failure(dataTask, error);
                                                        }
                                                    } else {
                                                        if (success) {
                                                            success(dataTask, data);
                                                        }
                                                    }
                                           
                                                }];
    
    [dataTask resume];
    return dataTask;
}


- (NSURLSessionDataTask*)requestUrlWithRetryCount:(NSInteger)retryCount retryInterval:(NSInteger)retryInteval refreshWhenTokenExpired:(BOOL)refreshWhenTokenExpired taskCreate:(NSURLSessionDataTask *(^)(retryBlock_t, refreshBlock_t))taskCreate failure:(void(^)(NSURLSessionDataTask *, NSError *))failure {
    
    id createCopy = [taskCreate copy];
    
    retryBlock_t retryBlock = ^(NSURLSessionDataTask *task, NSError *originError) {
        
        if (retryCount > 0) {
            
            void (^runRetryAction)() = ^{
                [self requestUrlWithRetryCount:retryCount - 1 retryInterval:retryInteval refreshWhenTokenExpired:refreshWhenTokenExpired taskCreate:createCopy failure:failure];
            };
            
            if (retryInteval > 0) {
                NSLog(@"retry remaining... %ld", retryCount);
                dispatch_time_t delay = dispatch_time(0, (int64_t)(retryInteval * NSEC_PER_SEC));
                dispatch_after(delay, dispatch_get_main_queue(), ^(void){
                    runRetryAction();
                });
            } else {
                NSLog(@"retry remaining... %ld", retryCount);
                runRetryAction();
            }
        } else {
            
            NSLog(@"retry count = 0");
            failure(task, originError);
        }
    };
    
    refreshBlock_t refreshBlock = ^(NSURLSessionDataTask *task, NSError *originError) {
        
        if (!refreshWhenTokenExpired) {
            NSLog(@"refresh error: %@", originError);
            failure(task, originError);
            return;
        }
        
        [self requestRefresh:^(BOOL isSuccess, NSError* refreshError) {
            
            if (isSuccess) {
                
                void (^runRetryAction)() = ^{
                    [self requestUrlWithRetryCount:retryCount retryInterval:retryInteval refreshWhenTokenExpired:NO taskCreate:createCopy failure:failure];
                };
                
                NSLog(@"refresh ok: retry remaining... %ld", retryCount);
                runRetryAction();
                
            } else {
                failure(task, refreshError);
            }
            
        }];
        
    };
    
    NSURLSessionDataTask* task = taskCreate(retryBlock, refreshBlock);
    
    return task;
}

- (void) URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler {
    
    NSString *authMethod = challenge.protectionSpace.authenticationMethod;
    if ([authMethod isEqualToString: NSURLAuthenticationMethodServerTrust]) {
        SecTrustRef secTrustRef = challenge.protectionSpace.serverTrust;
        if (secTrustRef != NULL) {
            SecTrustResultType result;
            OSErr er = SecTrustEvaluate( secTrustRef, &result );
            if ( er != noErr) {
                completionHandler(NSURLSessionAuthChallengeRejectProtectionSpace, nil);
            }
            
            // 自己証明書の場合
            if ( result == kSecTrustResultRecoverableTrustFailure ) {
                NSLog( @"---SecTrustResultRecoverableTrustFailure" );
                
                // 自己証明書を許可しない場合は、通信をキャンセルする。
                if (!self.allowInvalidCertification) {
           
                    [session invalidateAndCancel];
                    return;
                }
            }
        }
        
        NSURLCredential *credential = [NSURLCredential credentialForTrust: secTrustRef];
        completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
    }
}

@end
