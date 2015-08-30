//
//  NetworkManager.m
//  NetworkManager
//
//  Created by maru on 2015/08/29.
//  Copyright (c) 2015年 maru. All rights reserved.
//

#import "NetworkManager.h"


static NSString* const refreshPath = @"refresh";
static NSString* const resultPath = @"result";

typedef void (^retryBlock_t)(NSURLSessionDataTask* task, NSError* error);
typedef void (^refreshBlock_t)(NSURLSessionDataTask* task, NSError* error);

@interface NetworkManager ()

- (NSURLSessionDataTask*)requestUrlWithRetryCount:(NSInteger)retryCount retryInterval:(NSInteger)retryInteval refreshWhenTokenExpired:(BOOL)refreshWhenTokenExpired taskCreate:(NSURLSessionDataTask *(^)(retryBlock_t, refreshBlock_t))taskCreate failure:(void(^)(NSURLSessionDataTask *, NSError *))failure;

@end

@implementation NetworkManager

static NetworkManager* sharedInstance = nil;

+ (NetworkManager*)shared {
    
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        sharedInstance = [[NetworkManager alloc] init];
    });
    
    return sharedInstance;
}

- (instancetype)init {
    self = [super initWithBaseURL:[NSURL URLWithString:@"http://localhost:4567"]];
    if (self) {
        self.requestSerializer = [AFHTTPRequestSerializer serializer];
        self.responseSerializer = [AFJSONResponseSerializer serializer];
    }
    return self;
}


- (void)requestRefresh:(void (^)(BOOL isSuccess, NSError* error))completionBlock {
    
    [self requestUrlWithRetryCount:0 retryInterval:0 refreshWhenTokenExpired:NO taskCreate:^NSURLSessionDataTask* (retryBlock_t retryBlock, refreshBlock_t refreshBlock) {
        
        return [self POST:refreshPath parameters:nil success:^(NSURLSessionDataTask* refreshTask, id refreshResponse) {
            
            if (refreshResponse[@"error_cd"]) {
                
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
            
            if ([resultResponse[@"error_cd"] isEqualToString:@"401"]) {
                
                refreshBlock(resultTask, [[NSError alloc] initWithDomain:@"token_error" code:1 userInfo:nil]);
                
                return;
            }
            
        } failure:retryBlock];
        
    } failure:^(NSURLSessionDataTask* task, NSError* error){
    
        NSLog(@"error: %@", error);
        
    }];
    
}


- (NSURLSessionDataTask*)requestUrlWithRetryCount:(NSInteger)retryCount retryInterval:(NSInteger)retryInteval refreshWhenTokenExpired:(BOOL)refreshWhenTokenExpired taskCreate:(NSURLSessionDataTask *(^)(retryBlock_t, refreshBlock_t))taskCreate failure:(void(^)(NSURLSessionDataTask *, NSError *))failure {
    
    id createCopy = [taskCreate copy];
    
    retryBlock_t retryBlock = ^(NSURLSessionDataTask *task, NSError *originError) {
        
        if (retryCount > 0) {
            
            void (^addRetryOperation)() = ^{
                [self requestUrlWithRetryCount:retryCount - 1 retryInterval:retryInteval refreshWhenTokenExpired:refreshWhenTokenExpired taskCreate:createCopy failure:failure];
            };
            
            if (retryInteval > 0) {
                NSLog(@"retry remaining... %ld", retryCount);
                dispatch_time_t delay = dispatch_time(0, (int64_t)(retryInteval * NSEC_PER_SEC));
                dispatch_after(delay, dispatch_get_main_queue(), ^(void){
                    addRetryOperation();
                });
            } else {
                NSLog(@"retry remaining... %ld", retryCount);
                addRetryOperation();
            }
        } else {
            
            NSLog(@"retry count = 0");
            failure(task, originError);
        }
    };
    
    refreshBlock_t refreshBlock = ^(NSURLSessionDataTask *task, NSError *originError) {
        
        [self requestRefresh:^(BOOL isSuccess, NSError* refreshError) {
            
            if (isSuccess && refreshWhenTokenExpired) {
                
                void (^addRetryOperation)() = ^{
                    [self requestUrlWithRetryCount:retryCount retryInterval:retryInteval refreshWhenTokenExpired:NO taskCreate:createCopy failure:failure];
                };
                
                NSLog(@"refresh ok: retry remaining... %ld", retryCount);
                addRetryOperation();
                
            } else if (isSuccess && !refreshWhenTokenExpired) {
                
                NSLog(@"refresh error: %@", originError);
                failure(task, originError);
                
            } else {
                failure(task, refreshError);
            }
            
        }];
    
    };
    
    NSURLSessionDataTask* task = taskCreate(retryBlock, refreshBlock);
    
    return task;
}

@end
