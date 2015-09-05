//
//  NetworkManager.h
//  NetworkManager
//
//  Created by maru on 2015/08/29.
//  Copyright (c) 2015年 maru. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AFHTTPSessionManager.h"

/**
    通信マネージャーのシングルトンクラス
 */
@interface NetworkManager : AFHTTPSessionManager
+ (NetworkManager*)shared;
- (void)requestRefresh:(void (^)(BOOL isSuccess, NSError* error))completionBlock;
- (void)requestResult:(void (^)(BOOL isSuccess, NSError* error))completionBlock;
@end
