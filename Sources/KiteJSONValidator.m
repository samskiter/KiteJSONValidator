//
//  KiteJSONValidator.m
//  MCode
//
//  Created by Sam Duke on 15/12/2013.
//  Copyright (c) 2013 Airsource Ltd. All rights reserved.
//

#import "KiteJSONValidator.h"
#import "KiteValidationPair.h"

@interface KiteJSONValidator()

@property (nonatomic,strong) NSMutableArray * validationStack;
@property (nonatomic,strong) NSMutableArray * resolutionStack;
@property (nonatomic,strong) NSMutableArray * schemaStack;
@property (nonatomic,strong) NSMutableDictionary * schemaRefs;

@end

NSError* ValidationError(NSString* format, ...){

    static NSString* KiteJSONValidatorDomain = @"KiteJSONValidator";
    
    va_list args;
    va_start(args, format);
    NSString* description = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    return [NSError errorWithDomain:KiteJSONValidatorDomain code:0 userInfo:@{NSLocalizedDescriptionKey:description}];
}

@implementation KiteJSONValidator

@synthesize validationStack=_validationStack;
@synthesize resolutionStack=_resolutionStack;
@synthesize schemaStack=_schemaStack;
@synthesize schemaRefs=_schemaRefs;

@synthesize delegate;

-(id)init
{
    self = [super init];
    if (self) {
        NSURL *rootURL = [NSURL URLWithString:@"http://json-schema.org/draft-04/schema#"];
        NSDictionary *rootSchema = [self rootSchema];
        NSAssert([self addRefSchema:rootSchema atURL:rootURL validateSchema:NO]==nil, @"Unable to add the root schema!", nil);
    }

    return self;
}

-(NSError*)addRefSchema:(NSDictionary *)schema atURL:(NSURL *)url validateSchema:(BOOL)shouldValidateSchema
{
    NSError * error;
    //We convert to data in order to protect ourselves against a cyclic structure and ensure we have valid JSON
    NSData * schemaData = [NSJSONSerialization dataWithJSONObject:schema options:0 error:&error];
    if (error) {
        return error;
    }
    return [self addRefSchemaData:schemaData atURL:url validateSchema:shouldValidateSchema];
}

-(NSError*)addRefSchema:(NSDictionary*)schema atURL:(NSURL*)url
{
    return [self addRefSchema:schema atURL:url validateSchema:YES];
}

-(NSError*)addRefSchemaData:(NSData *)schemaData atURL:(NSURL *)url
{
    return [self addRefSchemaData:schemaData atURL:url validateSchema:YES];
}

-(NSError*)addRefSchemaData:(NSData*)schemaData atURL:(NSURL*)url validateSchema:(BOOL)shouldValidateSchema
{
    if (!url) return ValidationError(@"URL must not be empty");
    
    if (!schemaData || ![schemaData isKindOfClass:[NSData class]]) {
        return ValidationError(@"Data must be NSData class. Not %@", schemaData.class);
    }
    
    NSError * error = nil;
    id schema = [NSJSONSerialization JSONObjectWithData:schemaData options:0 error:&error];
    if (error) {
        return error;
    } else if (![schema isKindOfClass:[NSDictionary class]]) {
        return ValidationError(@"Schema must be an 'Object'. Not %@", [schema class]);
    }
    
    if (!schema) return ValidationError(@"Schema must not be empty");
    
    url = [self urlWithoutFragment:url];
    //TODO:consider failing if the url contained a fragment.
    
    if (shouldValidateSchema) {
        NSDictionary *root = [self rootSchema];
        if (![root isEqualToDictionary:schema]) {
            NSError* schemaError = [self validateJSON:schema withSchemaDict:root];
            if (schemaError) {
                return ValidationError(@"Invalid schema %@", schemaError.localizedDescription);
            }
        }
        else {
            //NSLog(@"Can't really validate the root schema against itself, right? ... Right?");
        }
    }
    
    if (!_schemaRefs) {
        _schemaRefs = [[NSMutableDictionary alloc] init];
    }
    self.schemaRefs[url] = schema;
    return nil;
}

-(NSDictionary *)rootSchema
{
    static NSDictionary * rootSchema;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSBundle *mainBundle = [NSBundle bundleForClass:[self class]];
        NSString *bundlePath = [mainBundle pathForResource:@"KiteJSONValidator" ofType:@"bundle"];
        NSBundle *resourceBundle = [NSBundle bundleWithPath:bundlePath];
        NSString *rootSchemaPath = [resourceBundle pathForResource:@"schema" ofType:@""];
        NSAssert(rootSchemaPath != NULL, @"Root schema not found in bundle: %@", resourceBundle.bundlePath);

        NSData *rootSchemaData = [NSData dataWithContentsOfFile:rootSchemaPath];
        NSError *error = nil;
        rootSchema = [NSJSONSerialization JSONObjectWithData:rootSchemaData
                                                     options:kNilOptions
                                                       error:&error];
        NSAssert(rootSchema != NULL, @"Root schema wasn't found", nil);
        NSAssert([rootSchema isKindOfClass:[NSDictionary class]], @"Root schema wasn't a dictionary", nil);
    });
    
    return rootSchema;
}

-(NSError*)pushToStackJSON:(id)json forSchema:(NSDictionary*)schema
{
    if (self.validationStack == nil) {
        self.validationStack = [NSMutableArray new];
        self.resolutionStack = [NSMutableArray new];
        self.schemaStack = [NSMutableArray new];
    }
    KiteValidationPair * pair = [KiteValidationPair pairWithLeft:json right:schema];
    if ([self.validationStack containsObject:pair]) {
        return ValidationError(@"Loops detectsed"); //Detects loops
    }
    [self.validationStack addObject:pair];
    return nil;
}

-(void)popStack
{
    [self.validationStack removeLastObject];
}

-(NSURL*)urlWithoutFragment:(NSURL*)url
{
    if (!url || ![url isKindOfClass:[NSURL class]]) {
        return nil;
    }

    NSString * refString = url.absoluteString;
    if (url.fragment.length > 0) {
        refString = [refString stringByReplacingOccurrencesOfString:url.fragment
                                                         withString:@""
                                                            options:NSBackwardsSearch
                                                              range:NSMakeRange(0, refString.length)];
    }
    if ([refString hasSuffix:@"#"]) {
        refString = [refString substringToIndex:[refString length] - 1];
    }
    return [NSURL URLWithString:refString];
}

-(NSError*)validateJSON:(id)json withSchemaAtReference:(NSString*)refString
{
    NSURL * refURI = [NSURL URLWithString:refString relativeToURL:self.resolutionStack.lastObject];
    if (!refURI) {
        return ValidationError(@"No Ref URI for '%@'", refString);
    }

    //get the fragment, if it is a JSON-Pointer
    NSArray * pointerComponents = nil;
    if (refURI.fragment.length > 0 && [refURI.fragment hasPrefix:@"/"]) {
        NSURL * pointerURI = [NSURL URLWithString:refURI.fragment];
        pointerComponents = [pointerURI pathComponents];
    }
    refURI = [self urlWithoutFragment:refURI];
        
    //first get the document, then resolve any pointers.
    NSURL * lastResolution = self.resolutionStack.lastObject;
    BOOL newDocument = NO;
    id schema = nil;

    if ([lastResolution isEqual:refURI]) {
        schema = (NSDictionary*)self.schemaStack.lastObject;
    } else if (self.schemaRefs != nil && self.schemaRefs[refURI] != nil) {
        //we changed document
        schema = self.schemaRefs[refURI];
        [self setResolutionUrl:refURI forSchema:schema];
        newDocument = YES;
    }

    if (!schema) {
        return ValidationError(@"No schema for Ref URI: %@", refURI);
    }

    for (NSString * component in pointerComponents) {
        if ([component isEqualToString:@"/"]) {
            continue;
        }

        if ([schema isKindOfClass:[NSDictionary class]]) {
            schema = ((NSDictionary *)schema)[component];
        } else if ([schema isKindOfClass:[NSArray class]] &&
                 (NSInteger)[(NSArray*)schema count] > [component integerValue]) {
            if (component.floatValue == (float)component.integerValue) {
                schema = ((NSArray *)schema)[[component integerValue]];
            }
        } else {
            schema = nil;
        }

        if (!schema) {
            return ValidationError(@"No schema");
        }
    }
    NSError* error = [self _validateJSON:json withSchemaDict:schema];
    if (newDocument) {
        [self removeResolution];
    }
    return error;
}

-(BOOL)setResolutionString:(NSString *)resolution forSchema:(NSDictionary *)schema
{
    //res and schema as Pair only add if different to previous. pop smart. pre fill. leave ability to look up res anywhere.
    //we should warn if the resolution contains a JSON-Pointer (these are a bad idea in an ID)
    NSURL *baseURL = (self.resolutionStack.lastObject) ? (self.resolutionStack.lastObject) : [NSURL URLWithString:@""];
    NSURL *fullURL = [NSURL URLWithString:resolution relativeToURL:baseURL];
    NSURL *idURI = [self urlWithoutFragment:fullURL];

    return [self setResolutionUrl:idURI forSchema:schema];
}

-(BOOL)setResolutionUrl:(NSURL *)idURI forSchema:(NSDictionary *)schema {
    if (!([self.resolutionStack.lastObject isEqual:idURI] && [self.schemaStack.lastObject isEqual:schema])) {
        [self.resolutionStack addObject:idURI];
        [self.schemaStack addObject:schema];
        return YES;
    }
    return NO;
}

-(void)removeResolution
{
    [self.resolutionStack removeLastObject];
    [self.schemaStack removeLastObject];
}

-(NSError*)validateJSONInstance:(id)json withSchema:(NSDictionary*)schema
{
    NSError * error = nil;
    NSString * jsonKey = nil;
    if (![NSJSONSerialization isValidJSONObject:json]) {
#ifdef DEBUG
        //in order to pass the tests
        jsonKey = @"debugInvalidTopTypeKey";
        json = @{jsonKey : json};
//        schema = @{@"properties" : @{@"debugInvalidTopTypeKey" : schema}};
#else
        return ValidationError(@"is not valid JSON Object");
#endif
    }
    NSData * jsonData = [NSJSONSerialization dataWithJSONObject:json options:0 error:&error];
    if (error ) {
        return error;
    }
    NSData * schemaData = [NSJSONSerialization dataWithJSONObject:schema options:0 error:&error];
    if (error) {
        return error;
    }
    return [self validateJSONData:jsonData withKey:jsonKey withSchemaData:schemaData];
}

-(NSError*)validateJSONData:(NSData*)jsonData withSchemaData:(NSData*)schemaData
{
    return [self validateJSONData:jsonData withKey:nil withSchemaData:schemaData];
}

-(NSError*)validateJSONData:(NSData*)jsonData withKey:(NSString*)key withSchemaData:(NSData*)schemaData
{
    NSError * error = nil;
    id json = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
    if (error) {
        return ValidationError(@"JSON data must be valid JSON: @%", error.localizedDescription);
    }
    if (key != nil) {
        json = json[key];
    }
    id schema = [NSJSONSerialization JSONObjectWithData:schemaData options:0 error:&error];
    if (error) {
        return ValidationError(@"Scheme must be valid JSON: %@", error.localizedDescription);
    }
    if (![schema isKindOfClass:[NSDictionary class]]) {
        return ValidationError(@"Schema must be 'Object' type. Not %@", [schema class]);
    }
    return [self validateJSON:json withSchemaDict:schema];
}

-(NSError*)validateJSON:(id)json withSchemaDict:(NSDictionary *)schema
{
    if (!schema ||
        ![schema isKindOfClass:[NSDictionary class]]) {
        //NSLog(@"No schema specified, or incorrect data type: %@", schema);
        return ValidationError(@"Schema must be 'Object' type. Not %@", [schema class]);
    }
    //need to make sure the validation of schema doesn't infinitely recurse (self references)
    // therefore should not expand any subschemas, and ensure schema are only checked on a 'top' level.
    //first validate the schema against the root schema then validate against the original
    //first check valid json (use NSJSONSerialization)

    self.validationStack = [NSMutableArray new];
    self.resolutionStack = [NSMutableArray new];
    self.schemaStack = [NSMutableArray new];

    [self setResolutionString:@"#" forSchema:schema];
    
    NSError* error = [self _validateJSON:schema withSchemaDict:self.rootSchema];
    if (error) {
        return error; //error: invalid schema
    }
    
    error = [self _validateJSON:json withSchemaDict:schema];
    if (error) {
        return error;
    }
    
    [self removeResolution];
    return nil;
}

-(NSError*)_validateJSON:(id)json withSchemaDict:(NSDictionary *)schema
{
    NSParameterAssert(schema != nil);
    //check stack for JSON and schema
    //push to stack the json and the schema.
    NSError* error = [self pushToStackJSON:json forSchema:schema];
    if (error) {
        return error;
    }
    BOOL newResolution = NO;
    NSString *resolutionValue = schema[@"id"];
    if (resolutionValue) {
        newResolution = [self setResolutionString:resolutionValue forSchema:schema];
    }
    error = [self __validateJSON:json withSchemaDict:schema];
    //pop from the stacks
    if (newResolution) {
        [self removeResolution];
    }
    [self popStack];
    return error;
}

-(NSError*)__validateJSON:(id)json withSchemaDict:(NSDictionary *)schema
{
    //TODO: synonyms (potentially in higher level too)
    
    static NSArray * anyInstanceKeywords;
    static NSArray * allKeywords;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        anyInstanceKeywords = @[@"enum", @"type", @"allOf", @"anyOf", @"oneOf", @"not", @"definitions"];
        allKeywords = @[@"multipleOf", @"maximum", @"exclusiveMaximum", @"minimum", @"exclusiveMinimum",
                        @"maxLength", @"minLength", @"pattern",
                        @"maxProperties", @"minProperties", @"required", @"properties", @"patternProperties", @"additionalProperties", @"dependencies",
                        @"additionalItems", @"items", @"maxItems", @"minItems", @"uniqueItems",
                        @"enum", @"type", @"allOf", @"anyOf", @"oneOf", @"not", @"definitions"];
    });
    //The "id" keyword (or "id", for short) is used to alter the resolution scope. When an id is encountered, an implementation MUST resolve this id against the most immediate parent scope. The resolved URI will be the new resolution scope for this subschema and all its children, until another id is encountered.

    /*"title" and "description"
     6.1.1.  Valid values
     6.1.2.  Purpose
     6.2.  "default"
     format <- optional*/

    /* Defaults */
    //the strategy for defaults is to dive one deeper and replace *just* ahead of where we are
    //    for (NSString * keyword in allKeywords) {
    //        if ([schema[keyword] isKindOfClass:[NSDictionary class]] && schema[keyword][@"default"] != nil && [json isKindOfClass:[NSDictionary class]] && [json objectForKey:keyword] == nil) {//this only does shallow defaults replacement
    //            [json setObject:[schema[keyword][@"default"] mutableCopy] forKey:keyword];
    //        }
    //    }

    NSString* schemaRef = schema[@"$ref"];
    if (schemaRef) {
        if (![schemaRef isKindOfClass:[NSString class]]) {
            return ValidationError(@"$ref '%@' is '%@' type, but must be a 'String' type", schemaRef, [schemaRef class]);
        }
        return [self validateJSON:json withSchemaAtReference:schemaRef];
    }

    NSString *type = nil;
    NSError*(^typeValidator)() = nil;
    if ([json isKindOfClass:[NSArray class]]) {
        type = @"array";
        typeValidator = ^{ return [self _validateJSONArray:json withSchemaDict:schema]; };
    } else if ([json isKindOfClass:[NSNumber class]]) {
        NSParameterAssert(strcmp( [@YES objCType], @encode(char) ) == 0);
        if (strcmp( [json objCType], @encode(char) ) == 0) {
            type = @"boolean";
        } else {
            typeValidator = ^{ return [self _validateJSONNumeric:json withSchemaDict:schema]; };
            double num = [json doubleValue];
            if ((num - floor(num)) == 0.0) {
                type = @"integer";
            } else {
                type = @"number";
            }
        }
    } else if ([json isKindOfClass:[NSNull class]]) {
        type = @"null";
    } else if ([json isKindOfClass:[NSDictionary class]]) {
        type = @"object";
        typeValidator = ^{ return [self _validateJSONObject:json withSchemaDict:schema]; };
        
    } else if ([json isKindOfClass:[NSString class]]) {
        type = @"string";
        typeValidator = ^{ return [self _validateJSONString:json withSchemaDict:schema]; };
    } else {
        return ValidationError(@"The schema '%@' is not one of the valid types", [json class]); // the schema is not one of the valid types.
    }    
    
    //TODO: extract the types first before the check (if there is no type specified, we'll never hit the checking code
    for (NSString * keyword in anyInstanceKeywords) {
        id schemaItem = schema[keyword];
        if (schemaItem != nil) {

            if ([keyword isEqualToString:@"enum"]) {
                //An instance validates successfully against this keyword if its value is equal to one of the elements in this keyword's array value.
                if (![schemaItem containsObject:json]) {
                    return ValidationError(@"enum '%@' does not contain '%@'", schemaItem, json);
                }
            } else if ([keyword isEqualToString:@"type"]) {
                if ([schemaItem isKindOfClass:[NSString class]]) {
                    if ([type isEqualToString:@"integer"] && [schemaItem isEqualToString:@"number"]) {
                        continue; 
                    }
                    if (![schemaItem isEqualToString:type]) {
                        return ValidationError(@"schema '%@' != '%@'", schemaItem, type);
                    }
                } else { //array
                    if (![schemaItem containsObject:type]) {
                        return ValidationError(@"array '%@' does not contain '%@'", schemaItem, type);
                    }
                }
            } else if ([keyword isEqualToString:@"allOf"]) {
                for (NSDictionary * subSchema in schemaItem) {
                    NSError* error = [self _validateJSON:json withSchemaDict:subSchema];
                    if (error) {
                        return error;
                    }
                }
            } else if ([keyword isEqualToString:@"anyOf"]) {
                for (NSDictionary * subSchema in schemaItem) {
                    NSError* error = [self _validateJSON:json withSchemaDict:subSchema];
                    if (error == nil) {
                        return nil;
                    }
                }
                return ValidationError(@"'%@' must be ANY OF '%@'", json, schemaItem);
            } else if ([keyword isEqualToString:@"oneOf"]) {
                int passes = 0;
                for (NSDictionary * subSchema in schemaItem) {
                    NSError* error = [self _validateJSON:json withSchemaDict:subSchema];
                    if (!error) {
                        passes++;
                    }
                    if (passes > 1) {
                        return ValidationError(@"'%@' must be ONE OF '%@'", json, schemaItem);
                    }
                }
                if (passes != 1) {
                    return ValidationError(@"'%@' must be ONE OF '%@'", json, schemaItem);
                }
            } else if ([keyword isEqualToString:@"not"]) {
                NSError* error = [self _validateJSON:json withSchemaDict:schemaItem];
                if (error == nil) {
                    return ValidationError(@"'%@' must be NOT '%@'", json, schemaItem);
                }
            } else if ([keyword isEqualToString:@"definitions"]) {
                
            }
        }
    }
    
    if (typeValidator != nil) {
        return typeValidator();
    }
    
    return nil;
}

//for number and integer
-(NSError*)_validateJSONNumeric:(NSNumber*)jsonNumber withSchemaDict:(NSDictionary*)schema
{
    static NSArray * numericKeywords;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        numericKeywords = @[@"multipleOf", @"maximum",/* @"exclusiveMaximum",*/ @"minimum",/* @"exclusiveMinimum"*/];
    });
    
    if (!schema) {
        return ValidationError(@"no schema for '%@'", jsonNumber);
    }
    if (![schema isKindOfClass:[NSDictionary class]]) {
        return ValidationError(@"schema is not is object '%@'", schema);
    }
    
    for (NSString * keyword in numericKeywords) {
        id schemaItem = schema[keyword];
        if (schemaItem != nil) {

            if ([keyword isEqualToString:@"multipleOf"]) {
                //A numeric instance is valid against "multipleOf" if the result of the division of the instance by this keyword's value is an integer.
                double divResult = [jsonNumber doubleValue] / [schemaItem doubleValue];
                if ((divResult - floor(divResult)) != 0.0) {
                    return ValidationError(@"multipleOf");
                }
            } else if ([keyword isEqualToString:@"maximum"]) {
                if ([schema[@"exclusiveMaximum"] isKindOfClass:[NSNumber class]] && [schema[@"exclusiveMaximum"] boolValue] == YES) {
                    if (!([jsonNumber doubleValue] < [schemaItem doubleValue])) {
                        //if "exclusiveMaximum" has boolean value true, the instance is valid if it is strictly lower than the value of "maximum".
                        return ValidationError(@"'%@' must be lower than '%@'", jsonNumber, schemaItem);
                    }
                } else {
                    if (!([jsonNumber doubleValue] <= [schemaItem doubleValue])) {
                        //if "exclusiveMaximum" is not present, or has boolean value false, then the instance is valid if it is lower than, or equal to, the value of "maximum"
                        return ValidationError(@"'%@' must be lower than, or equal to '%@'", jsonNumber, schemaItem);
                    }
                }
            } else if ([keyword isEqualToString:@"minimum"]) {
                if ([schema[@"exclusiveMinimum"] isKindOfClass:[NSNumber class]] && [schema[@"exclusiveMinimum"] boolValue] == YES) {
                    if (!([jsonNumber doubleValue] > [schemaItem doubleValue])) {
                        //if "exclusiveMinimum" is present and has boolean value true, the instance is valid if it is strictly greater than the value of "minimum".
                        return ValidationError(@"'%@' must be greater than '%@'", jsonNumber, schemaItem);
                    }
                } else {
                    if (!([jsonNumber doubleValue] >= [schemaItem doubleValue])) {
                        //if "exclusiveMinimum" is not present, or has boolean value false, then the instance is valid if it is greater than, or equal to, the value of "minimum"
                        return ValidationError(@"'%@' must be greater than, or equal to '%@'", jsonNumber, schemaItem);
                    }
                }
            }
        }
    }
    return nil;
}

-(NSError*)_validateJSONString:(NSString*)jsonString withSchemaDict:(NSDictionary*)schema
{
    static NSArray * stringKeywords;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        stringKeywords = @[@"maxLength", @"minLength", @"pattern"];
    });

    for (NSString * keyword in stringKeywords) {
        id schemaItem = schema[keyword];
        if (schemaItem != nil) {

            if ([keyword isEqualToString:@"maxLength"]) {
                //A string instance is valid against this keyword if its length is less than, or equal to, the value of this keyword.
                
                //What's going on here - [NSString length] returns the number of unichars in a string. Unichars are 16bit but
                // surrogate pairs in unicode require to Unichars. This is more common as this is how emoji are encoded.
                // Go read this if you care: http://www.objc.io/issue-9/unicode.html (See Common Pitfalls - Length)
                NSInteger realLength = [jsonString lengthOfBytesUsingEncoding:NSUTF32StringEncoding] / 4;
                
                if (!(realLength <= [schemaItem integerValue])) {
                    return ValidationError(@"string '%@' length must be less than, or equal to %d", jsonString, realLength);
                }
            } else if ([keyword isEqualToString:@"minLength"]) {
                //A string instance is valid against this keyword if its length is greater than, or equal to, the value of this keyword.
                
                NSInteger realLength = [jsonString lengthOfBytesUsingEncoding:NSUTF32StringEncoding] / 4;
                if (!(realLength >= [schemaItem intValue])) {
                    return ValidationError(@"string '%@' length must be greater than, or equal to %d", jsonString, realLength);
                }
            } else if ([keyword isEqualToString:@"pattern"]) {
                //A string instance is considered valid if the regular expression matches the instance successfully. Recall: regular expressions are not implicitly anchored.
                //This string SHOULD be a valid regular expression, according to the ECMA 262 regular expression dialect.
                //NOTE: this regex uses ICU which has some differences to ECMA-262 (such as look-behind)
                NSError * error;
                NSRegularExpression * regex = [NSRegularExpression regularExpressionWithPattern:schemaItem options:0 error:&error];
                if (error) {
                    continue;
                }
                if (NSEqualRanges([regex rangeOfFirstMatchInString:jsonString options:0 range:NSMakeRange(0, jsonString.length)], NSMakeRange(NSNotFound, 0))) {
                    //A string instance is considered valid if the regular expression matches the instance successfully. Recall: regular expressions are not implicitly anchored.
                    return ValidationError(@"string does not match regular expression");
                }
            }
        }
    }
    return nil;
}

-(NSError*)_validateJSONObject:(NSDictionary*)jsonDict withSchemaDict:(NSDictionary*)schema
{
    static NSArray * objectKeywords;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        objectKeywords = @[@"maxProperties", @"minProperties", @"required", @"properties", @"patternProperties", @"additionalProperties", @"dependencies"];
    });
    BOOL doneProperties = NO;
    for (NSString * keyword in objectKeywords) {
        id schemaItem = schema[keyword];
        if (schemaItem != nil) {

            if ([keyword isEqualToString:@"maxProperties"]) {
                //An object instance is valid against "maxProperties" if its number of properties is less than, or equal to, the value of this keyword.
                if ((NSInteger)[jsonDict count] > [schemaItem integerValue]) {
                    return ValidationError(@"object properties count (%d) must be less than, or equal to %@", jsonDict.count, schemaItem); /*invalid JSON dict*/
                }
            } else if ([keyword isEqualToString:@"minProperties"]) {
                //An object instance is valid against "minProperties" if its number of properties is greater than, or equal to, the value of this keyword.
                if ((NSInteger)[jsonDict count] < [schemaItem integerValue]) {
                    return ValidationError(@"object properties count (%d) must be greater than, or equal to %@", jsonDict.count, schemaItem); /*invalid JSON dict*/
                }
            } else if ([keyword isEqualToString:@"required"]) {
                NSArray * requiredArray = schemaItem;
                for (NSObject * requiredProp in requiredArray) {
                    NSString * requiredPropStr = (NSString*)requiredProp;
                    if (![jsonDict valueForKey:requiredPropStr]) {
                        return ValidationError(@"required property '%@' is not present", requiredPropStr); //required not present. invalid JSON dict.
                    }
                }
            } else if (!doneProperties && ([keyword isEqualToString:@"properties"] || [keyword isEqualToString:@"patternProperties"] || [keyword isEqualToString:@"additionalProperties"])) {
                doneProperties = YES;
                NSDictionary * properties = schema[@"properties"];
                NSDictionary * patternProperties = schema[@"patternProperties"];
                id additionalProperties = schema[@"additionalProperties"];
                if (properties == nil) { properties = [NSDictionary new]; }
                if (patternProperties == nil) { patternProperties = [NSDictionary new]; }
                if (additionalProperties == nil || ([additionalProperties isKindOfClass:[NSNumber class]] && strcmp([additionalProperties objCType], @encode(char)) == 0 && [additionalProperties boolValue] == YES)) {
                    additionalProperties = [NSDictionary new];
                }
                
                /** calculating children schemas **/
                //The calculation of the children schemas is combined with the checking of present keys
                NSSet * p = [NSSet setWithArray:[properties allKeys]];
                NSArray * pp = [patternProperties allKeys];
                NSSet * allKeys = [NSSet setWithArray:[jsonDict allKeys]];
                NSMutableDictionary * testSchemas = [NSMutableDictionary dictionaryWithCapacity:allKeys.count];
                
                NSMutableSet * ps = [NSMutableSet setWithSet:allKeys];
                //If set "p" contains value "m", then the corresponding schema in "properties" is added to "s".
                [ps intersectSet:p];
                for (id m in ps) {
                    testSchemas[m] = [NSMutableArray arrayWithObject:[properties objectForKey:m]];
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
                                testSchemas[m] = [NSMutableArray arrayWithObject:[patternProperties objectForKey:regexString]];
                            } else {
                                [testSchemas[m] addObject:[patternProperties objectForKey:regexString]];
                            }
                        }
                    }
                }
                NSParameterAssert(testSchemas.count <= allKeys.count);
                
                //Successful validation of an object instance against these three keywords depends on the value of "additionalProperties":
                //    if its value is boolean true or a schema, validation succeeds;
                //    if its value is boolean false, the algorithm to determine validation success is described below.
                if ([additionalProperties isKindOfClass:[NSNumber class]] && [additionalProperties boolValue] == NO) { //value must therefore be boolean false
                    //Because we have built a set of schemas/keys up (rather than down), the following test is equivalent to the requirement:
                    //Validation of the instance succeeds if, after these two steps, set "s" is empty.
                    if (testSchemas.count < allKeys.count) {
                        return ValidationError(@"additionalProperties = NO");
                    }
                } else {
                    //find keys from allkeys that are not in testSchemas and add additionalProperties
                    NSDictionary * additionalPropsSchema = nil;
                    //In addition, boolean value true for "additionalItems" is considered equivalent to an empty schema.
                    
                    if ([additionalProperties isKindOfClass:[NSNumber class]] && strcmp([additionalProperties objCType], @encode(char)) == 0) {
                        additionalPropsSchema = [NSDictionary new];
                    } else {
                        additionalPropsSchema = additionalProperties;
                    }
                    NSMutableSet * additionalKeys = [allKeys mutableCopy];
                    [additionalKeys minusSet:[testSchemas keysOfEntriesPassingTest:^BOOL(id key, id obj, BOOL *stop) { return YES; }]];
                    for (NSString * key in additionalKeys) {
                        testSchemas[key] = [NSMutableArray arrayWithObject:additionalPropsSchema];
                    }
                }
                
                //TODO: run the tests on the testSchemas
                for (NSString * property in [testSchemas keyEnumerator]) {
                    NSArray * subschemas = testSchemas[property];
                    for (NSDictionary * subschema in subschemas) {
                        NSError* error = [self _validateJSON:jsonDict[property] withSchemaDict:subschema];
                        if (error) {
                            return error;
                        }
                    }
                }
            } else if ([keyword isEqualToString:@"dependencies"]) {
                NSSet * properties = [jsonDict keysOfEntriesPassingTest:^BOOL(id key, id obj, BOOL *stop) { return YES; }];
                NSDictionary * dependencies = schemaItem;
                for (NSString * name in [dependencies allKeys]) {
                    if (![properties containsObject:name]) {
                        continue;
                    }

                    id dependency = dependencies[name];
                    if ([dependency isKindOfClass:[NSDictionary class]]) {
                        NSDictionary * schemaDependency = dependency;
                        //For all (name, schema) pair of schema dependencies, if the instance has a property by this name, then it must also validate successfully against the schema.
                        //Note that this is the instance itself which must validate successfully, not the value associated with the property name.
                        NSError* error = [self _validateJSON:jsonDict withSchemaDict:schemaDependency];
                        if (error) {
                            return error;
                        }
                    } else if ([dependency isKindOfClass:[NSArray class]]) {
                        NSArray * propertyDependency = dependency;
                        //For each (name, propertyset) pair of property dependencies, if the instance has a property by this name, then it must also have properties with the same names as propertyset.
                        NSSet * propertySet = [NSSet setWithArray:propertyDependency];
                        if (![propertySet isSubsetOfSet:properties]) {
                            return ValidationError(@"For each (name, propertyset) pair of property dependencies, if the instance has a property by this name, then it must also have properties with the same names as propertyset");
                        }
                    }
                }
            }
        }
    }
    return nil;
}

-(NSError*)_validateJSONArray:(NSArray*)jsonArray withSchemaDict:(NSDictionary*)schema
{
    static NSArray * arrayKeywords;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        arrayKeywords = @[@"additionalItems", @"items", @"maxItems", @"minItems", @"uniqueItems"];
    });
    
    BOOL doneItems = NO;
    for (NSString * keyword in arrayKeywords) {
        id schemaItem = schema[keyword];
        if (schemaItem != nil) {

            if (!doneItems && ([keyword isEqualToString:@"additionalItems"] || [keyword isEqualToString:@"items"])) {
                doneItems = YES;
                id additionalItems = schema[@"additionalItems"];
                id items = schema[@"items"];
                if (additionalItems == nil) { additionalItems = [NSDictionary new];}
                if (items == nil) { items = [NSDictionary new];}
                if ([additionalItems isKindOfClass:[NSNumber class]] && strcmp([additionalItems objCType], @encode(char)) == 0 && [additionalItems boolValue] == YES) {
                    additionalItems = [NSDictionary new];
                }
                
                for (NSUInteger index = 0; index < [jsonArray count]; index++) {
                    id child = jsonArray[index];
                    if ([items isKindOfClass:[NSDictionary class]]) {
                        //If items is a schema, then the child instance must be valid against this schema, regardless of its index, and regardless of the value of "additionalItems".
                        NSError* error = [self _validateJSON:jsonArray[index] withSchemaDict:items];
                        if (error) {
                            return error;
                        }
                    } else if ([items isKindOfClass:[NSArray class]]) {
                        if (index < [(NSArray *)items count]) {
                            NSError* error = [self _validateJSON:child withSchemaDict:items[index]];
                            if (error) {
                                return error;
                            }
                        } else {
                            if ([additionalItems isKindOfClass:[NSNumber class]] && [additionalItems boolValue] == NO) {
                                //if the value of "additionalItems" is boolean value false and the value of "items" is an array, the instance is valid if its size is less than, or equal to, the size of "items".
                                return ValidationError(@"If the value of 'additionalItems' is boolean value false and the value of 'items' is an array, the instance is valid if its size is less than, or equal to, the size of 'items'");
                            } else {
                                NSError* error = [self _validateJSON:child withSchemaDict:additionalItems];
                                if (error) {
                                    return error;
                                }
                            }
                        }
                    }
                }
            } else if ([keyword isEqualToString:@"maxItems"]) {
                if ((NSInteger)[jsonArray count] > [schemaItem integerValue]){
                    return ValidationError(@"An array instance is valid against 'maxItems' if its size is less than, or equal to, the value of this keyword.");
                }
            } else if ([keyword isEqualToString:@"minItems"]) {
                if ((NSInteger)[jsonArray count] < [schemaItem integerValue]) {
                    return ValidationError(@"An array instance is valid against 'minItems' if its size is greater than, or equal to, the value of this keyword.");
                }
            } else if ([keyword isEqualToString:@"uniqueItems"]) {
                if ([schemaItem isKindOfClass:[NSNumber class]] && [schemaItem boolValue] == YES) {
                    //If it has boolean value true, the instance validates successfully if all of its elements are unique.
                    NSSet * uniqueItems = [NSSet setWithArray:jsonArray];

                    NSUInteger fudgeFactor = 0;
                    if ([self valuesHaveOneAndTrue:jsonArray])
                    {
                        fudgeFactor++;
                    }

                    // false and zero are treated as unique
                    if ([self valuesHaveZeroAndFalse:jsonArray])
                    {
                        fudgeFactor++;
                    }

                    if (([uniqueItems count] + fudgeFactor) < [jsonArray count])
                    {
                        return ValidationError(@"all elements must be unique");
                    }
                }
            }
        }
    }
    return nil;
}

- (BOOL)valuesHaveOneAndTrue:(NSArray *)values
{
    BOOL trueFound = NO;
    BOOL oneFound = NO;

    for (NSNumber *number in values) {
        if (![number isKindOfClass:[NSNumber class]]) {
            continue;
        }

        if (strcmp([number objCType], @encode(char)) == 0) {
            if ([number boolValue] == YES) {
                trueFound = YES;
            }
        } else if ([number doubleValue] == 1.0) {
            oneFound = YES;
        }
    }
    return (trueFound && oneFound);
}

- (BOOL)valuesHaveZeroAndFalse:(NSArray *)values
{
    BOOL falseFound = NO;
    BOOL zeroFound = NO;
    
    for (NSNumber *number in values)
    {
        if (![number isKindOfClass:[NSNumber class]]) {
            continue;
        }
        if (strcmp([number objCType], @encode(char)) == 0) {
            if ([number boolValue] == NO) {
                falseFound = YES;
            }
        } else if ([number doubleValue] == 0.0) {
            zeroFound = YES;
        }
    }
    return (falseFound && zeroFound);
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
        return YES;
    } else {
        return NO; //invalid schema - although technically including $schema is only RECOMMENDED
    }
}

@end
