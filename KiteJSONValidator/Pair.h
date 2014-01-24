//
//  Pair.h
//  Tests
//
//  Created by Sam Duke on 24/01/2014.
//
//

#import <Foundation/Foundation.h>

@interface Pair : NSObject <NSCopying>
@property (nonatomic, readonly) NSObject<NSCopying>* left;
@property (nonatomic, readonly) NSObject<NSCopying>* right;
+ (id) pairWithLeft:(id<NSCopying>)l right:(id<NSCopying>)r;
- (id) initWithLeft:(id<NSCopying>)l right:(id<NSCopying>)r;

@end
