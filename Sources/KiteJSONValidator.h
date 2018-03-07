//
//  KiteJSONValidator.h
//  MCode
//
//  Created by Sam Duke on 15/12/2013.
//  Copyright (c) 2013 Airsource Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol KiteJSONSchemaRefDelegate;

@interface KiteJSONValidator : NSObject

@property (nonatomic, weak, nullable) id<KiteJSONSchemaRefDelegate> delegate;

/**
 Validates json against a draft4 schema.
 @see http://tools.ietf.org/html/draft-zyp-json-schema-04
 
 @param jsonData The JSON to be validated
 @param schemaData The draft4 JSON schema to validate against
 @return Whether the json is validated.
 */
-(BOOL)validateJSONData:(NSData*)jsonData withSchemaData:(NSData*)schemaData error:(NSError **)error;
-(BOOL)validateJSONInstance:(id)json withSchema:(NSDictionary*)schema error:(NSError **)error;
-(BOOL)validateJSONInstance:(id)json withSchemaData:(NSData*)schemaData error:(NSError **)error;
//TODO:add an interface to add a schema with a key, allowing a schema to only be validated once and then reused

/**
 Used for adding an ENTIRE document to the list of reference schemas - the URL should therefore be fragmentless.
 
 @param schemaData The data for the document to be converted to JSON
 @param url        The fragmentless URL for this document
 
 @return Whether the reference schema was successfully added.
 */
-(BOOL)addRefSchemaData:(NSData*)schemaData atURL:(NSURL*)url error:(NSError **)error;

/**
 Used for adding an ENTIRE document to the list of reference schemas - the URL should therefore be fragmentless.
 
 @param schemaData           The data for the document to be converted to JSON
 @param url                  The fragmentless URL for this document
 @param shouldValidateSchema Whether the new reference schema should be validated against the "root" schema.
 
 @return Whether the reference schema was successfully added.
 */
-(BOOL)addRefSchemaData:(NSData*)schemaData atURL:(NSURL*)url validateSchema:(BOOL)shouldValidateSchema error:(NSError **)error;

/**
 Used for adding an ENTIRE document to the list of reference schemas - the URL should therefore be fragmentless.
 
 @param schema The dictionary representation of the JSON schema (the JSON was therefore valid).
 @param url    The fragmentless URL for this document
 
 @return Whether the reference schema was successfully added.
 */
-(BOOL)addRefSchema:(NSDictionary*)schema atURL:(NSURL*)url error:(NSError **)error;

/**
 Used for adding an ENTIRE document to the list of reference schemas - the URL should therefore be fragmentless.
 
 @param schema               The dictionary representation of the JSON schema (the JSON was therefore valid).
 @param url                  The fragmentless URL for this document
 @param shouldValidateSchema Whether the new reference schema should be validated against the "root" schema.
 
 @return Whether the reference schema was successfully added.
 */
-(BOOL)addRefSchema:(NSDictionary *)schema atURL:(NSURL *)url validateSchema:(BOOL)shouldValidateSchema error:(NSError **)error;

@end

@protocol KiteJSONSchemaRefDelegate <NSObject>

@optional
-(nullable NSData*)schemaValidator:(KiteJSONValidator*)validator requiresSchemaDataForRefURL:(NSURL*)refURL;
-(nullable NSDictionary*)schemaValidator:(KiteJSONValidator*)validator requiresSchemaForRefURL:(NSURL*)refURL;

@end

NS_ASSUME_NONNULL_END
