//
//  KiteJSONValidator.h
//  MCode
//
//  Created by Sam Duke on 15/12/2013.
//  Copyright (c) 2013 Airsource Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol KiteJSONSchemaRefDelegate;

@interface KiteJSONValidator : NSObject

@property (nonatomic, weak) id<KiteJSONSchemaRefDelegate> delegate;

/**
 Validates json against a draft4 schema.
 @see http://tools.ietf.org/html/draft-zyp-json-schema-04
 
 @param json The JSON to be validated
 @param schema The draft4 JSON schema to validate against
 @return Whether the json is validated.
 */
-(BOOL)validateJSONData:(NSData*)jsonData withSchemaData:(NSData*)schemaData;
-(BOOL)validateJSONInstance:(id)json withSchema:(NSDictionary*)schema;

/**
 Used for adding an ENTIRE document to the list of reference schemas - the URL should therefore be fragmentless.
 @param schemaData the data for the document to be converted to JSON
 @param url the fragmentless URL for this document
 */
-(void)addRefSchemaData:(NSData*)schemaData atURL:(NSURL*)url;
-(void)addRefSchema:(NSDictionary*)schema atURL:(NSURL*)url;

@end

@protocol KiteJSONSchemaRefDelegate <NSObject>

-(NSData*)schemaValidator:(KiteJSONValidator*)validator requiresSchemaDataForRefURL:(NSURL*)refURL;
-(NSDictionary*)schemaValidator:(KiteJSONValidator*)validator requiresSchemaForRefURL:(NSURL*)refURL;

@end
