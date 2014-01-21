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
    if (schema[@"type"]) {
        
    }
    return TRUE;
}

+(BOOL)propertyIsInteger:(id)property
{
    return [property isMemberOfClass:[NSNumber class]] &&
           [property isEqualToNumber:[NSNumber numberWithInteger:[property integerValue]]];
}

+(BOOL)propertyIsPositiveInteger:(id)property
{
    return [KiteJSONValidator propertyIsInteger:property] &&
           [property longLongValue] >= 0;
}

-(BOOL)validateJSON:(id)json withSchemaDict:(NSDictionary *)schema
{
    //need to make sure the validation of schema doesn't infinitely recurse (self references)
    // therefore should not expand any subschemas, and ensure schema are only checked on a 'top' level.
    //first validate the schema against the root schema then validate against the original
    NSString *rootSchemaPath = [[NSBundle bundleForClass:[self class]] pathForResource:@"schema"
                                                                                ofType:@""];
    //TODO: error out if the path is nil
    NSData *rootSchemaData = [NSData dataWithContentsOfFile:rootSchemaPath];
    NSError *error = nil;
    NSDictionary * rootSchema = [NSJSONSerialization JSONObjectWithData:rootSchemaData
                                                                options:kNilOptions
                                                                  error:&error];
    NSLog(@"Root Schema: %@", rootSchema);
    if (![self _validateJSON:schema withSchemaDict:rootSchema])
    {
        return FALSE; //error: invalid schema
    }
    else if (![self _validateJSON:json withSchemaDict:[schema mutableCopy]])
    {
        return FALSE;
    }
    else
    {
        return TRUE;
    }
}
-(BOOL)_validateJSON:(id)json withSchemaDict:(NSDictionary *)schema
{
    //TODO: replace all top level refs
    
    static NSArray * dictionaryKeywords;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dictionaryKeywords = @[@"enum", @"type", @"allOf", @"anyOf", @"oneOf", @"not", @"definitions"];
    });
    /*"title" and "description"
     6.1.1.  Valid values
     6.1.2.  Purpose
     6.2.  "default"
     format <- optional*/
    
    
    //TODO: extract the types first before the check (if there is no type specified, we'll never hit the checking code
    for (NSString * keyword in dictionaryKeywords) {
        if (schema[keyword] != nil) {
            if ([keyword isEqualToString:@"enum"]) {
                if (![schema[keyword] containsObject:json]) { return FALSE; }
            } else if ([keyword isEqualToString:@"type"]) {
                if ([schema[keyword] isEqualToString:@"array"]) {
                    if (![json isKindOfClass:[NSArray class]]) { return FALSE; }
                } else if ([schema[keyword] isEqualToString:@"boolean"]) {
                    //boolean checking is limited, but we'll ensure its an integer and it is 1 or 0;
                    if (![json isKindOfClass:[NSNumber class]]) {
                        return FALSE;
                    } else {
                        double num = [json doubleValue];
                        if ((num - floor(num)) != 0.0 || (num != 1.0 || num != 0.0)) {
                            return FALSE;
                        }
                    }
                } else if ([schema[keyword] isEqualToString:@"integer"]) {
                    if (![json isKindOfClass:[NSNumber class]]) {
                        return FALSE;
                    } else {
                        double num = [json doubleValue];
                        if ((num - floor(num)) != 0.0) {
                            return FALSE;
                        }
                    }
                } else if ([schema[keyword] isEqualToString:@"null"]) {
                    if (![json isKindOfClass:[NSNull class]]) { return FALSE; }
                } else if ([schema[keyword] isEqualToString:@"number"]) {
                    if (![json isKindOfClass:[NSNumber class]]) { return FALSE; }
                } else if ([schema[keyword] isEqualToString:@"object"]) {
                    if (![json isKindOfClass:[NSDictionary class]]) { return FALSE; }
                } else if ([schema[keyword] isEqualToString:@"string"]) {
                    if (![json isKindOfClass:[NSString class]]) { return FALSE; }
                }
            } else if ([keyword isEqualToString:@"allOf"]) {
                
            } else if ([keyword isEqualToString:@"anyOf"]) {
            } else if ([keyword isEqualToString:@"oneOf"]) {
            } else if ([keyword isEqualToString:@"not"]) {
            } else if ([keyword isEqualToString:@"definitions"]) {
            }
        }
    }
    return FALSE;
}

//for number and integer
-(BOOL)_validateJSONNumeric:(NSNumber*)JSONNumber withSchemaDict:(NSDictionary*)schema
{
    static NSArray * dictionaryKeywords;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dictionaryKeywords = @[@"multipleOf", @"maximum",/* @"exclusiveMaximum",*/ @"minimum",/* @"exclusiveMinimum"*/];
    });
    
    for (NSString * keyword in dictionaryKeywords) {
        if (schema[keyword] != nil) {
            if ([keyword isEqualToString:@"multipleOf"]) {
                //A numeric instance is valid against "multipleOf" if the result of the division of the instance by this keyword's value is an integer.
                double divResult = [JSONNumber doubleValue] / [schema[keyword] doubleValue];
                if ((divResult - floor(divResult)) != 0.0) {
                    return FALSE;
                }
            } else if ([keyword isEqualToString:@"maximum"]) {
                if (schema[@"exclusiveMaximum"]) {
                    if (![JSONNumber doubleValue] < [schema[keyword] doubleValue]) {
                        //if "exclusiveMaximum" has boolean value true, the instance is valid if it is strictly lower than the value of "maximum".
                        return FALSE;
                    }
                } else {
                    if (![JSONNumber doubleValue] <= [schema[keyword] doubleValue]) {
                        //if "exclusiveMaximum" is not present, or has boolean value false, then the instance is valid if it is lower than, or equal to, the value of "maximum"
                        return FALSE;
                    }
                }
            } else if ([keyword isEqualToString:@"minimum"]) {
                if (schema[@"exclusiveMinimum"]) {
                    if (![JSONNumber doubleValue] > [schema[keyword] doubleValue]) {
                        //if "exclusiveMinimum" is present and has boolean value true, the instance is valid if it is strictly greater than the value of "minimum".
                        return FALSE;
                    }
                } else {
                    if (![JSONNumber doubleValue] >= [schema[keyword] doubleValue]) {
                        //if "exclusiveMinimum" is not present, or has boolean value false, then the instance is valid if it is greater than, or equal to, the value of "minimum"
                        return FALSE;
                    }
                }
            }
        }
    }
    return TRUE;
}

-(BOOL)_validateJSONString:(NSString*)JSONString withSchemaDict:(NSDictionary*)schema
{
    static NSArray * dictionaryKeywords;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dictionaryKeywords = @[@"maxLength", @"minLength", @"pattern"];
    });
    
    for (NSString * keyword in dictionaryKeywords) {
        if (schema[keyword] != nil) {
            if ([keyword isEqualToString:@"maxLength"]) {
                //A string instance is valid against this keyword if its length is less than, or equal to, the value of this keyword.
                if (!JSONString.length <= [schema[keyword] intValue]) { return FALSE; }
            } else if ([keyword isEqualToString:@"minLength"]) {
                //A string instance is valid against this keyword if its length is greater than, or equal to, the value of this keyword.
                if (!JSONString.length >= [schema[keyword] intValue]) { return FALSE; }
            } else if ([keyword isEqualToString:@"pattern"]) {
                //A string instance is considered valid if the regular expression matches the instance successfully. Recall: regular expressions are not implicitly anchored.
                //This string SHOULD be a valid regular expression, according to the ECMA 262 regular expression dialect.
                //NOTE: this regex uses ICU which has some differences to ECMA-262 (such as look-behind)
                NSError * error;
                NSRegularExpression * regex = [NSRegularExpression regularExpressionWithPattern:schema[keyword] options:0 error:&error];
                if (error) {
                    continue;
                }
                if (NSEqualRanges([regex rangeOfFirstMatchInString:JSONString options:0 range:NSMakeRange(0, JSONString.length)], NSMakeRange(NSNotFound, 0))) {
                    //A string instance is considered valid if the regular expression matches the instance successfully. Recall: regular expressions are not implicitly anchored.
                    return FALSE;
                }
            }
        }
    }
    return TRUE;
}

-(BOOL)_validateJSONObject:(NSDictionary*)JSONDict withSchemaDict:(NSDictionary*)schema
{
    static NSArray * dictionaryKeywords;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dictionaryKeywords = @[@"maxProperties", @"minProperties", @"required", @"properties",/* @"patternProperties", @"additionalProperties",*/ @"dependencies"];
    });
    
    NSMutableDictionary * propertySchema = [NSMutableDictionary dictionaryWithSharedKeySet:[NSDictionary sharedKeySetForKeys:[JSONDict allKeys]]];
    for (NSString * keyword in dictionaryKeywords) {
        if (schema[keyword] != nil) {
            if ([keyword isEqualToString:@"maxProperties"]) {
                //An object instance is valid against "maxProperties" if its number of properties is less than, or equal to, the value of this keyword.
                if ([JSONDict count] > [schema[keyword] intValue]) { return FALSE; /*invalid JSON dict*/ }
            } else if ([keyword isEqualToString:@"minProperties"]) {
                //An object instance is valid against "minProperties" if its number of properties is greater than, or equal to, the value of this keyword.
                if ([JSONDict count] < [schema[keyword] intValue]) { return FALSE; /*invalid JSON dict*/ }
            } else if ([keyword isEqualToString:@"required"]) {
                NSArray * requiredArray = schema[keyword];
                for (NSObject * requiredProp in requiredArray) {
                    NSString * requiredPropStr = (NSString*)requiredProp;
                    if (![JSONDict valueForKey:requiredPropStr]) {
                        return FALSE; //required not present. invalid JSON dict.
                    }
                }
            } else if ([keyword isEqualToString:@"properties"]) {
                /** calculating children schemas **/
                //The calculation of the children schemas is combined with the checking of present keys
                NSSet * p = [NSSet setWithArray:[schema[@"properties"] allKeys]];
                NSArray * pp = [schema[@"patternProperties"] allKeys];
                NSSet * allKeys = [NSSet setWithArray:[JSONDict allKeys]];
                NSMutableDictionary * testSchemas = [NSMutableDictionary dictionaryWithCapacity:allKeys.count];
                
                NSMutableSet * ps = [NSMutableSet setWithSet:allKeys];
                //If set "p" contains value "m", then the corresponding schema in "properties" is added to "s".
                [ps intersectSet:p];
                for (id m in ps) {
                    testSchemas[m] = [NSMutableArray arrayWithObject:[schema[@"properties"] objectForKey:m]];
                }
                
                //we loop the regexes so each is only created once
                //For each regex in "pp", if it matches "m" successfully, the corresponding schema in "patternProperties" is added to "s".
                for (NSString * regexString in pp) {
                    //Each property name of this object SHOULD be a valid regular expression, according to the ECMA 262 regular expression dialect.
                    //NOTE: this regex uses ICU which has some differences to ECMA-262 (such as look-behind)
                    NSError * error;
                    NSRegularExpression * regex = [NSRegularExpression regularExpressionWithPattern:regexString options:0 error:&error];
                    if (error) {
                        continue;
                    }
                    for (NSString * m in allKeys) {
                        if (!NSEqualRanges([regex rangeOfFirstMatchInString:m options:0 range:NSMakeRange(0, m.length)], NSMakeRange(NSNotFound, 0))) {
                            if (testSchemas[m] == NULL) {
                                testSchemas[m] = [NSMutableArray arrayWithObject:[schema[@"patternProperties"] objectForKey:regexString]];
                            } else {
                                [testSchemas[m] addObject:[schema[@"patternProperties"] objectForKey:regexString]];
                            }
                        }
                    }
                }
                assert(testSchemas.count <= allKeys.count);
                
                //Successful validation of an object instance against these three keywords depends on the value of "additionalProperties":
                //    if its value is boolean true or a schema, validation succeeds;
                //    if its value is boolean false, the algorithm to determine validation success is described below.
                if (!schema[@"additionalProperties"]) { //value must therefore be boolean false
                    //Because we have built a set of schemas/keys up (rather than down), the following test is equivalent to the requirement:
                    //Validation of the instance succeeds if, after these two steps, set "s" is empty.
                    if (testSchemas.count < allKeys.count) {
                        return FALSE;
                    }
                } else {
                    //find keys from allkeys that are not in testSchemas and add additionalProperties
                    NSDictionary * additionalPropsSchema;
                    //In addition, boolean value true for "additionalItems" is considered equivalent to an empty schema.
                    if ([schema[@"additionalProperties"] isKindOfClass:[NSNumber class]]) { //TODO: better check for bool?
                        additionalPropsSchema = [NSDictionary new];
                    } else {
                        additionalPropsSchema = schema[@"additionalProperties"];
                    }
                    NSMutableSet * additionalKeys = [allKeys mutableCopy];
                    [additionalKeys minusSet:[testSchemas keysOfEntriesPassingTest:^BOOL(id key, id obj, BOOL *stop) { return YES; }]];
                    for (NSString * key in additionalKeys) {
                        testSchemas[key] = additionalPropsSchema;
                    }
                }
                
                //TODO: run the tests on the testSchemas
                for (NSString * property in [testSchemas keyEnumerator]) {
                    NSArray * subschemas = testSchemas[property];
                    for (NSDictionary * subschema in subschemas) {
                        //TODO: call private validator
                        if (![self validateJSON:JSONDict[property] withSchemaDict:subschema]) {
                            return FALSE;
                        }
                    }
                }
            } else if ([keyword isEqualToString:@"dependencies"]) {
                NSSet * properties = [JSONDict keysOfEntriesPassingTest:^BOOL(id key, id obj, BOOL *stop) { return YES; }];
                NSDictionary * dependencies = schema[keyword];
                for (NSString * name in [dependencies allKeys]) {
                    if ([properties containsObject:name]) {
                        id dependency = dependencies[name];
                        if ([dependency isKindOfClass:[NSDictionary class]]) {
                            NSDictionary * schemaDependency = dependency;
                            //For all (name, schema) pair of schema dependencies, if the instance has a property by this name, then it must also validate successfully against the schema.
                            //Note that this is the instance itself which must validate successfully, not the value associated with the property name.
                            //TODO:(should probably call private validator)
                            if (![self validateJSON:JSONDict withSchemaDict:schemaDependency[name]]) {
                                return FALSE;
                            }
                        } else if ([dependency isKindOfClass:[NSArray class]]) {
                            NSArray * propertyDependency = dependency;
                            //For each (name, propertyset) pair of property dependencies, if the instance has a property by this name, then it must also have properties with the same names as propertyset.
                            NSSet * propertySet = [NSSet setWithArray:propertyDependency];
                            if (![propertySet isSubsetOfSet:propertySet]) {
                                return FALSE;
                            }
                        }
                    }
                }
            }
        }
    }
    return TRUE;
}

-(BOOL)_validateJSONArray:(NSArray*)JSONArray withSchemaDict:(NSDictionary*)schema
{
    static NSArray * dictionaryKeywords;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dictionaryKeywords = @[@"additionalItems@",/* @"items",*/ @"maxItems", @"minItems", @"uniqueItems"];
    });
    
    for (NSString * keyword in dictionaryKeywords) {
        if (schema[keyword] != nil) {
            if ([keyword isEqualToString:@"additionalItems"]) {
                id additionalItems = schema[keyword];
                if ([additionalItems isKindOfClass:[NSNumber class]] && [additionalItems boolValue] == TRUE) { //TODO: better test for boolean?
                    additionalItems = [NSDictionary new];
                }
                id items = schema[@"items"];
                for (int index = 0; index < [JSONArray count]; index++) {
                    id child = JSONArray[index];
                    if ([items isKindOfClass:[NSDictionary class]]) {
                        //If items is a schema, then the child instance must be valid against this schema, regardless of its index, and regardless of the value of "additionalItems".
                        if (![self validateJSON:JSONArray[index] withSchemaDict:items]) {
                            return FALSE;
                        }
                    } else if ([items isKindOfClass:[NSArray class]]) {
                        if (index < [items count]) {
                            if (![self validateJSON:child withSchemaDict:items[index]]) {
                                return FALSE;
                            }
                        } else {
                            if ([additionalItems isKindOfClass:[NSNumber class]] && [additionalItems boolValue] == FALSE) {
                                //if the value of "additionalItems" is boolean value false and the value of "items" is an array, the instance is valid if its size is less than, or equal to, the size of "items".
                                return FALSE;
                            } else {
                                if (![self validateJSON:child withSchemaDict:additionalItems]) {
                                    return FALSE;
                                }
                            }
                        }
                    }
                }
            } else if ([keyword isEqualToString:@"maxItems"]) {
                //An array instance is valid against "maxItems" if its size is less than, or equal to, the value of this keyword.
                if ([JSONArray count] > [schema[keyword] intValue]) { return FALSE; }
                //An array instance is valid against "minItems" if its size is greater than, or equal to, the value of this keyword.
            } else if ([keyword isEqualToString:@"minItems"]) {
                if ([JSONArray count] < [schema[keyword] intValue]) { return FALSE; }
            } else if ([keyword isEqualToString:@"uniqueItems"]) {
                if (schema[keyword]) {
                    //If it has boolean value true, the instance validates successfully if all of its elements are unique.
                    NSSet * items = [NSSet setWithArray:JSONArray];
                    if ([items count] < [JSONArray count]) { return FALSE; }
                }
            }
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
