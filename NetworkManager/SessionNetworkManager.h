//
//  SessionNetworkManager.h
//  NetworkManager
//
//  Created by maru on 2015/08/30.
//  Copyright (c) 2015年 maru. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SessionNetworkManager : NSObject 

@property (nonatomic, assign) BOOL allowInvalidCertification;
@property (nonatomic, strong) NSString* baseURL;

+ (SessionNetworkManager*)shared;
- (void)requestRefresh:(void (^)(BOOL isSuccess, NSError* error))completionBlock;
- (void)requestResult:(void (^)(BOOL isSuccess, NSError* error))completionBlock;

@end
