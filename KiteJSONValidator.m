//
//  KiteJSONValidator.m
//  MCode
//
//  Created by Sam Duke on 15/12/2013.
//  Copyright (c) 2013 Airsource Ltd. All rights reserved.
//

#import "KiteJSONValidator.h"

@implementation KiteJSONValidator



-(BOOL)validateJSONUnknown:(NSObject*)object withSchemaDict:(NSDictionary*)schema
{
    if (![self checkSchemaRef:schema]) {
        return FALSE;
    }
    if (schema[@"required"]) {
        if (![self checkRequired:schema forJSON:object]) {
            return FALSE;
        }
    }
    if (schema[@"type"]) {
        
    }
    return TRUE;
}

-(BOOL)validateJSONObject:(NSDictionary*)JSONDict withSchemaDict:(NSDictionary*)schema
{
    for (NSString * propertyKey in [schema keyEnumerator]) {
        if ([propertyKey isEqualToString:@"maxProperties"]) {
            
        } else if ([propertyKey isEqualToString:@"minProperties"]) {
            
        } else if ([propertyKey isEqualToString:@"required"]) {
            if (![self checkRequired:schema forJSON:JSONDict]) {
                return FALSE;
            }
        } else if ([propertyKey isEqualToString:@"additionalProperties"]) {
            //TODO: the properties validation needs to be mixed with schema selection for child validation. NOTE: "object member values may have to validate against more than one schema."
            NSMutableArray * s = [[JSONDict keysSortedByValueUsingSelector:nil] mutableCopy];
            if ([s count] == 0) {
                continue; //nothing to test
            }
            NSArray * p;
            if (schema[@"properties"])
            {
                if ([schema[@"properties"] isKindOfClass:[NSDictionary class]]) {
                    p = [schema[@"properties"] keysSortedByValueUsingSelector:nil];
                    //TODO: Each value of this object MUST be an object, and each object MUST be a valid JSON Schema.
                } else {
                    return FALSE; //invalid schema
                }
            } else {
                //If either "properties" or "patternProperties" are absent, they can be considered present with an empty object as a value.
                p = [NSArray new];
            }
            NSArray * pp;
            if (schema[@"patternProperties"]) {
                if ([schema[@"patternProperties"] isKindOfClass:[NSDictionary class]]) {
                    pp = [schema[@"patternProperties"] keysSortedByValueUsingSelector:nil];
                    //TODO: Each property name of this object SHOULD be a valid regular expression, according to the ECMA 262 regular expression dialect. Each property value of this object MUST be an object, and each object MUST be a valid JSON Schema.
                } else {
                    return FALSE; //invalid schema
                }
            } else {
                //If either "properties" or "patternProperties" are absent, they can be considered present with an empty object as a value.
                pp = [NSArray new];
            }
            
            //Step 1. remove from "s" all elements of "p", if any;
            [s removeObjectsInArray:p];
            if ([s count] == 0) {
                continue; //nothing left to test
            }
            
            //Step 2. for each regex in "pp", remove all elements of "s" which this regex matches.
            for (NSString * regexString in pp) {
                NSError * regexError;
                NSRegularExpression * regex = [NSRegularExpression regularExpressionWithPattern:regexString options:0 error:&regexError];
                if (regexError) {
                    //Each property name of this object SHOULD be a valid regular expression
                    //This one is not, so we just continue and ignore it.
                    continue;
                }
                for (NSString * propertyString in s) {
                    if ([regex numberOfMatchesInString:propertyString options:0 range:NSMakeRange(0, propertyString.length)] > 0) {
                        [s removeObject:propertyString]; //slightly worrisome changing the array while looping it....
                    }
                }
                if ([s count] == 0 ) {
                    break;
                }
            }
            
            //Validation of the instance succeeds if, after these two steps, set "s" is empty.
            if ([s count] > 0 ) {
                return FALSE; //invalid JSON dict
            }
        } else if ([propertyKey isEqualToString:@"dependencies"]) {
            
        }
    }
    return TRUE;
}

-(BOOL)checkRequired:(NSDictionary*)schema forJSON:(NSDictionary*)json
{
    if (![schema[@"required"] isKindOfClass:[NSArray class]]) {
        //The value of this keyword MUST be an array.
        return FALSE; //invalid schema
    }
    NSArray * requiredArray = schema[@"required"];
    if (![requiredArray count] > 0) {
        //This array MUST have at least one element.
        return  FALSE; //invalid schema
    }
    if (!([[NSSet setWithArray: requiredArray] count] == [requiredArray count])) {
        //Elements of this array MUST be unique.
        return FALSE; // invalid schema
    }
    for (NSObject * requiredProp in requiredArray) {
        if (![requiredProp isKindOfClass:[NSString class]]) {
            //Elements of this array MUST be strings.
            return FALSE; // invalid schema
        }
        NSString * requiredPropStr = (NSString*)requiredProp;
        if (![json valueForKey:requiredPropStr]) {
            return FALSE; //required not present. invalid JSON dict.
        }
    }
    return TRUE;
}

-(BOOL)checkSchemaRef:(NSDictionary*)schema
{
    NSArray * validSchemaArray = @[
                                   @"http://json-schema.org/schema#",
                                   //JSON Schema written against the current version of the specification.
                                   //@"http://json-schema.org/hyper-schema#",
                                   //JSON Schema written against the current version of the specification.
                                   @"http://json-schema.org/draft-04/schema#",
                                   //JSON Schema written against this version.
                                   @"http://json-schema.org/draft-04/hyper-schema#",
                                   //JSON Schema hyperschema written against this version.
                                   //@"http://json-schema.org/draft-03/schema#",
                                   //JSON Schema written against JSON Schema, draft v3 [json‑schema‑03].
                                   //@"http://json-schema.org/draft-03/hyper-schema#"
                                   //JSON Schema hyperschema written against JSON Schema, draft v3 [json‑schema‑03].
                                   ];
    
    if ([validSchemaArray containsObject:schema[@"$schema"]]) {
        return TRUE;
    } else {
        return FALSE; //invalid schema - although technically including $schema is only RECOMMENDED
    }
}

@end
