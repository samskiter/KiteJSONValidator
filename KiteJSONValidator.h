//
//  KiteJSONValidator.h
//  MCode
//
//  Created by Sam Duke on 15/12/2013.
//  Copyright (c) 2013 Airsource Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface KiteJSONValidator : NSObject

/**
 Validates json against a draft4 schema.
 @see http://tools.ietf.org/html/draft-zyp-json-schema-04
 
 @param json The JSON dictionary to be validated
 @param schema The draft4 JSON schema to validate against
 @return Whether the json is validated.
 */
-(BOOL)validateJSON:(NSDictionary*)json withSchema:(NSDictionary*)schema;

@end
