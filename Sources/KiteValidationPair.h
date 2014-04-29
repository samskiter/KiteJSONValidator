//
//  KiteValidationPair.h
//  Tests
//
//  Created by Sam Duke on 24/01/2014.
//
//

#import <Foundation/Foundation.h>

@interface KiteValidationPair : NSObject <NSCopying>
@property (nonatomic, readonly) NSObject<NSCopying>* left;
@property (nonatomic, readonly) NSObject<NSCopying>* right;
+ (instancetype) pairWithLeft:(id<NSCopying>)l right:(id<NSCopying>)r;
- (instancetype) initWithLeft:(id<NSCopying>)l right:(id<NSCopying>)r;

@end
