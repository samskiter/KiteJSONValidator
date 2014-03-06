//
//  Pair.m
//  Tests
//
//  Created by Sam Duke on 24/01/2014.
//
//

#import "Pair.h"

@implementation Pair

@synthesize left, right;

+ (id) pairWithLeft:(NSObject<NSCopying>*)l right:(NSObject<NSCopying>*)r {
    return [[[self class] alloc] initWithLeft:l right:r];
}

- (id) initWithLeft:(NSObject<NSCopying>*)l right:(NSObject<NSCopying>*)r {
    if (self = [super init]) {
        left = [l copy];
        right = [r copy];
    }
    return self;
}

- (void) finalize {
    left = nil;
    right = nil;
    [super finalize];
}

- (void) dealloc {
    left = nil;
    right = nil;
}

- (id) copyWithZone:(NSZone *)zone {
    Pair * copy = [[[self class] alloc] initWithLeft:[self left] right:[self right]];
    return copy;
}

- (BOOL) isEqual:(id)other {
    if ([other isKindOfClass:[Pair class]] == NO) { return NO; }
    return ([[self left] isEqual:[other left]] && [[self right] isEqual:[other right]]);
}

- (NSUInteger) hash {
    //perhaps not "hashish" enough, but probably good enough
    return [[self left] hash] + [[self right] hash];
}

@end
