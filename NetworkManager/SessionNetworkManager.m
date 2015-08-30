//
//  SessionNetworkManager.m
//  NetworkManager
//
//  Created by maru on 2015/08/30.
//  Copyright (c) 2015年 maru. All rights reserved.
//

#import "SessionNetworkManager.h"


static NSString* const refreshPath = @"refresh";
static NSString* const resultPath = @"result";

typedef void (^retryBlock_t)(NSURLSessionDataTask* task, NSError* error);
typedef void (^refreshBlock_t)(NSURLSessionDataTask* task, NSError* error);

@interface SessionNetworkManager ()

- (NSURLSessionDataTask*)requestUrlWithRetryCount:(NSInteger)retryCount retryInterval:(NSInteger)retryInteval refreshWhenTokenExpired:(BOOL)refreshWhenTokenExpired taskCreate:(NSURLSessionDataTask *(^)(retryBlock_t, refreshBlock_t))taskCreate failure:(void(^)(NSURLSessionDataTask *, NSError *))failure;

@end

@implementation SessionNetworkManager

static SessionNetworkManager* sharedInstance = nil;

+ (SessionNetworkManager*)shared {
    
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        sharedInstance = [[SessionNetworkManager alloc] init];
    });
    
    return sharedInstance;
}

- (instancetype)init {
//    self = [super initWithBaseURL:[NSURL URLWithString:@"http://localhost:4567"]];
//    if (self) {
//        self.requestSerializer = [AFHTTPRequestSerializer serializer];
//        self.responseSerializer = [AFJSONResponseSerializer serializer];
//    }
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
    
    NSURL* url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/%@",@"http://localhost:4567", URLString]];
    NSLog(@"url: %@", [url absoluteString]);
    NSMutableURLRequest* request = [[NSMutableURLRequest alloc] initWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData timeoutInterval:30.0];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSURLSessionConfiguration* configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession* session = [NSURLSession sessionWithConfiguration:configuration delegate:nil delegateQueue:nil];
    
    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                                completionHandler:^(NSData * data, NSURLResponse * __unused response, NSError *error) {
                                                    
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

@end
