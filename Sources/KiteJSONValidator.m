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
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-variable"
        BOOL success = [self addRefSchema:rootSchema atURL:rootURL validateSchema:NO error:nil];
#pragma clang diagnostic pop
        NSAssert(success == YES, @"Unable to add the root schema!", nil);
    }

    return self;
}

-(BOOL)addRefSchema:(NSDictionary *)schema atURL:(NSURL *)url validateSchema:(BOOL)shouldValidateSchema error:(NSError **)error
{
    //We convert to data in order to protect ourselves against a cyclic structure and ensure we have valid JSON
    NSError *detailedError = nil;
    NSData * schemaData = [NSJSONSerialization dataWithJSONObject:schema options:0 error:&detailedError];
    if (schemaData == nil) {
        if (error) {
            *error = [self validationErrorWithDescription:@"Schema data is not valid JSON data" forURL:url detailedError:detailedError];
        }
        return NO;
    }
    return [self addRefSchemaData:schemaData atURL:url validateSchema:shouldValidateSchema error:error];
}

-(BOOL)addRefSchema:(NSDictionary*)schema atURL:(NSURL*)url error:(NSError **)error
{
    return [self addRefSchema:schema atURL:url validateSchema:YES error:error];
}

-(BOOL)addRefSchemaData:(NSData *)schemaData atURL:(NSURL *)url error:(NSError **)error
{
    return [self addRefSchemaData:schemaData atURL:url validateSchema:YES error:error];
}

-(BOOL)addRefSchemaData:(NSData*)schemaData atURL:(NSURL*)url validateSchema:(BOOL)shouldValidateSchema error:(NSError **)error
{
    if (!schemaData || ![schemaData isKindOfClass:[NSData class]]) {
        if (error) {
            *error = [self validationErrorWithDescription:@"Schema data is nil or no instance of NSData" forURL:url detailedError:nil];
        }
        return NO;
    }
    
    NSError*detailedError = nil;
    id schema = [NSJSONSerialization JSONObjectWithData:schemaData options:0 error:&detailedError];
    if (schema == nil) {
        if (error) {
            *error = [self validationErrorWithDescription:@"Schema data could not be converted to json object" forURL:url detailedError:detailedError];
        }
        return NO;
    } else if (![schema isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [self validationErrorWithDescription:@"Schema data does not have a root level dictionary" forURL:url detailedError:nil];
        }
        return NO;
    }
    
    NSAssert(url != NULL, @"URL must not be empty", nil);
    NSAssert(schema != NULL, @"Schema must not be empty", nil);
    
    if (!url || !schema)
    {
        if (error) {
            *error = [self validationErrorWithDescription:@"URL or schema is not defined" forURL:nil detailedError:nil];
        }
        return NO;
    }
    url = [self urlWithoutFragment:url];
    //TODO:consider failing if the url contained a fragment.
    
    if (shouldValidateSchema)
    {
        NSDictionary *root = [self rootSchema];
        if (![root isEqualToDictionary:schema])
        {
            BOOL isValidSchema = [self validateJSON:schema withSchemaDict:root error:&detailedError];
            NSAssert(isValidSchema == YES, @"Invalid schema", nil);
            if (!isValidSchema) {
                if (error) {
                    *error = [self validationErrorWithDescription:@"Supplied schema is not valid according to the root level schema specification" forURL:url detailedError:detailedError];
                }
                return NO;
            }
        }
        else
        {
            //NSLog(@"Can't really validate the root schema against itself, right? ... Right?");
        }
    }
    
    @synchronized(self)
    {
        if (!_schemaRefs)
        {
            _schemaRefs = [[NSMutableDictionary alloc] init];
        }
        self.schemaRefs[url] = schema;
        return YES;
    }
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

-(BOOL)pushToStackJSON:(id)json forSchema:(NSDictionary*)schema
{
    if (self.validationStack == nil) {
        self.validationStack = [NSMutableArray new];
        self.resolutionStack = [NSMutableArray new];
        self.schemaStack = [NSMutableArray new];
    }
    KiteValidationPair * pair = [KiteValidationPair pairWithLeft:json right:schema];
    if ([self.validationStack containsObject:pair]) {
        return NO; //Detects loops
    }
    [self.validationStack addObject:pair];
    return YES;
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

-(BOOL)validateJSON:(id)json withSchemaAtReference:(NSString*)refString error:(NSError **)error
{
    NSURL * refURI = [NSURL URLWithString:refString relativeToURL:self.resolutionStack.lastObject];
    if (!refURI)
    {
        if (error) {
            *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"Reference could not be converted to a correct URL. Failed ref='%@', base url='%@'", refString, self.resolutionStack.lastObject] forURL:nil detailedError:nil];
        }
        return NO;
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
    } else if (refURI != nil) {
        schema = [self resolveSchemaRefURI:refURI withError:error];
        if (schema == nil) {
            return NO;
        }
        [self setResolutionUrl:refURI forSchema:schema];
        newDocument = YES;
    }

    if (!schema) {
        if (error) {
            *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"No schema could be resolved for URL: %@", refURI] forURL:refURI detailedError:nil];
        }
        return NO;
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
            if (error) {
                *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"Schema fragment could be resolved for pointer: %@", pointerComponents] forURL:refURI detailedError:nil];
            }
            return NO;
        }
    }
    BOOL result = [self _validateJSON:json withSchemaDict:schema error:error];
    if (newDocument) {
        [self removeResolution];
    }
    return result;
}

- (NSDictionary *)resolveSchemaRefURI:(NSURL *)refURI withError:(NSError **)error {
    NSDictionary *schema = self.schemaRefs[refURI];
    
    if (schema == nil) {
        if ([self.delegate respondsToSelector:@selector(schemaValidator:requiresSchemaForRefURL:)]) {
            schema = [self.delegate schemaValidator:self requiresSchemaForRefURL:refURI];
        }
        
        if (schema == nil && [self.delegate respondsToSelector:@selector(schemaValidator:requiresSchemaDataForRefURL:)]) {
            NSData *data = [self.delegate schemaValidator:self requiresSchemaDataForRefURL:refURI];
            if (data == nil) {
                if (error) {
                    *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"Delegate returned no schema data for reference: %@", refURI] forURL:refURI detailedError:nil];
                }
                return nil;
            }
            NSError *detailedError = nil;
            schema = [NSJSONSerialization JSONObjectWithData:data options:0 error:&detailedError];
            if (schema == nil) {
                if (error) {
                    *error = [self validationErrorWithDescription:@"Schema data could not be converted to json object" forURL:refURI detailedError:detailedError];
                }
                return nil;
            } else if (![schema isKindOfClass:[NSDictionary class]]) {
                if (error) {
                    *error = [self validationErrorWithDescription:@"Schema data does not have a root level dictionary" forURL:refURI detailedError:nil];
                }
                return nil;
            }
        }
    }
    if (schema == nil && error != nil) {
        *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"Schema reference could not be resolved: %@", refURI] forURL:refURI detailedError:nil];
    }
    return schema;
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

-(BOOL)validateJSONInstance:(id)json withSchemaData:(NSData*)schemaData error:(NSError **)error
{
    NSString * jsonKey = nil;
    if (![NSJSONSerialization isValidJSONObject:json]) {
#ifdef DEBUG
        //in order to pass the tests
        jsonKey = @"debugInvalidTopTypeKey";
        json = @{jsonKey : json};
        //        schema = @{@"properties" : @{@"debugInvalidTopTypeKey" : schema}};
#else
        if (error) {
            *error = [self validationErrorWithDescription:@"Supplied object is not a valid JSON object" forURL:nil detailedError:nil];
        }
        return NO;
#endif
    }
    NSError * detailedError = nil;
    NSData * jsonData = [NSJSONSerialization dataWithJSONObject:json options:0 error:&detailedError];
    if (jsonData == nil) {
        if (error) {
            *error = [self validationErrorWithDescription:@"Supplied object could not be converted to json data" forURL:nil detailedError:detailedError];
        }
        return NO;
    }
    return [self validateJSONData:jsonData withKey:jsonKey withSchemaData:schemaData error:error];
}

-(BOOL)validateJSONInstance:(id)json withSchema:(NSDictionary*)schema error:(NSError **)error
{
    NSError * detailedError = nil;
    NSString * jsonKey = nil;
    if (![NSJSONSerialization isValidJSONObject:json]) {
#ifdef DEBUG
        //in order to pass the tests
        jsonKey = @"debugInvalidTopTypeKey";
        json = @{jsonKey : json};
//        schema = @{@"properties" : @{@"debugInvalidTopTypeKey" : schema}};
#else
        if (error) {
            *error = [self validationErrorWithDescription:@"Supplied object is not a valid JSON object" forURL:nil detailedError:nil];
        }
        return NO;
#endif
    }
    NSData * jsonData = [NSJSONSerialization dataWithJSONObject:json options:0 error:&detailedError];
    if (jsonData == nil) {
        if (error) {
            *error = [self validationErrorWithDescription:@"Supplied object could not be converted to json data" forURL:nil detailedError:detailedError];
        }
        return NO;
    }
    NSData * schemaData = [NSJSONSerialization dataWithJSONObject:schema options:0 error:&detailedError];
    if (schemaData == nil) {
        if (error) {
            *error = [self validationErrorWithDescription:@"Supplied schema dictionary is not valid json data" forURL:nil detailedError:detailedError];
        }
        return NO;
    }
    return [self validateJSONData:jsonData withKey:jsonKey withSchemaData:schemaData error:error];
}

-(BOOL)validateJSONData:(NSData*)jsonData withSchemaData:(NSData*)schemaData error:(NSError **)error
{
    return [self validateJSONData:jsonData withKey:nil withSchemaData:schemaData error:error];
}

-(BOOL)validateJSONData:(NSData*)jsonData withKey:(NSString*)key withSchemaData:(NSData*)schemaData error:(NSError **)error
{
    NSError * detailedError = nil;
    id json = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&detailedError];
    if (json == nil) {
        if (error) {
            *error = [self validationErrorWithDescription:@"Supplied jsonData could not be decoded as valid JSON object" forURL:nil detailedError:detailedError];
        }
        return NO;
    }
    if (key != nil) {
        json = json[key];
    }
    id schema = [NSJSONSerialization JSONObjectWithData:schemaData options:0 error:&detailedError];
    if (schema == nil) {
        if (error) {
            *error = [self validationErrorWithDescription:@"Supplied schemaData could not be decoded as valid JSON object" forURL:nil detailedError:detailedError];
        }
        return NO;
    }
    if (![self validateJSON:json withSchemaDict:schema error:&detailedError]) {
        if (error) {
            *error = [self validationErrorWithDescription:@"Supplied json is not valid according to schema" forURL:nil detailedError:detailedError];
        }
        return NO;
    }
    return YES;
}

-(BOOL)validateJSON:(id)json withSchemaDict:(NSDictionary *)schema error:(NSError **)error
{
    @synchronized(self)
    {
        if (!schema ||
            ![schema isKindOfClass:[NSDictionary class]]) {
            if (error) {
                *error = [self validationErrorWithDescription:@"Supplied schema does not have a root level dictionary" forURL:nil detailedError:nil];
            }
            return NO;
        }

        //need to make sure the validation of schema doesn't infinitely recurse (self references)
        // therefore should not expand any subschemas, and ensure schema are only checked on a 'top' level.
        //first validate the schema against the root schema then validate against the original
        //first check valid json (use NSJSONSerialization)

        self.validationStack = [NSMutableArray new];
        self.resolutionStack = [NSMutableArray new];
        self.schemaStack = [NSMutableArray new];
        
        NSError *detailedError = nil;

        [self setResolutionString:@"#" forSchema:schema];
        
        if (![self _validateJSON:schema withSchemaDict:self.rootSchema error:&detailedError]) {
            if (error) {
                *error = [self validationErrorWithDescription:@"Supplied schema is not valid according to the root level schema specification" forURL:nil detailedError:detailedError];
            }
            return NO; //error: invalid schema
        }
        if (![self _validateJSON:json withSchemaDict:schema error:&detailedError]) {
            if (error) {
                *error = [self validationErrorWithDescription:@"Supplied json is not valid according to the supplied schema specification" forURL:nil detailedError:detailedError];
            }
            return NO;
        }

        [self removeResolution];
        return YES;
    }
}

-(BOOL)_validateJSON:(id)json withSchemaDict:(NSDictionary *)schema error:(NSError **)error
{
    NSParameterAssert(schema != nil);
    //check stack for JSON and schema
    //push to stack the json and the schema.
    if (![self pushToStackJSON:json forSchema:schema]) {
        if (error) {
            *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"Could not push json object to stack: %@", json] forURL:nil detailedError:nil];
        }
        return NO;
    }
    BOOL newResolution = NO;
    NSString *resolutionValue = schema[@"id"];
    if (resolutionValue) {
        newResolution = [self setResolutionString:resolutionValue forSchema:schema];
    }
    BOOL result = [self __validateJSON:json withSchemaDict:schema error:error];
    //pop from the stacks
    if (newResolution) {
        [self removeResolution];
    }
    [self popStack];
    return result;
}

-(BOOL)__validateJSON:(id)json withSchemaDict:(NSDictionary *)schema error:(NSError **)error
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

    if (schema[@"$ref"]) {
        if (![schema[@"$ref"] isKindOfClass:[NSString class]]) {
            if (error) {
                *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"$ref entry is not a valid string: %@", schema[@"$ref"]] forURL:nil detailedError:nil];
            }
            return NO;
        }
        return [self validateJSON:json withSchemaAtReference:schema[@"$ref"] error:error];
    }

    NSString *type = nil;
    SEL typeValidator = nil;
    if ([json isKindOfClass:[NSArray class]]) {
        type = @"array";
        typeValidator = @selector(_validateJSONArray:withSchemaDict:error:);
    } else if ([json isKindOfClass:[NSNumber class]]) {
        NSParameterAssert(strcmp( [@YES objCType], @encode(char) ) == 0);
        if (strcmp( [json objCType], @encode(char) ) == 0) {
            type = @"boolean";
        } else {
            typeValidator = @selector(_validateJSONNumeric:withSchemaDict:error:);
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
        typeValidator = @selector(_validateJSONObject:withSchemaDict:error:);
        
    } else if ([json isKindOfClass:[NSString class]]) {
        type = @"string";
        typeValidator = @selector(_validateJSONString:withSchemaDict:error:);
    } else {
        if (error) {
            *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"JSON object is not one of the valid types according to the JSON schema spec: %@: %@", NSStringFromClass(json), json] forURL:nil detailedError:nil];
        }
        return NO; // the schema is not one of the valid types.
    }    
    
    //TODO: extract the types first before the check (if there is no type specified, we'll never hit the checking code
    for (NSString * keyword in anyInstanceKeywords) {
        id schemaItem = schema[keyword];
        if (schemaItem != nil) {

            if ([keyword isEqualToString:@"enum"]) {
                //An instance validates successfully against this keyword if its value is equal to one of the elements in this keyword's array value.
                if (![schemaItem containsObject:json]) {
                    if (error) {
                        *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"JSON object is not valid according to the allowed items for this enumeration (json, schemaItem): (%@, %@)", json, schemaItem] forURL:nil detailedError:nil];
                    }
                    return NO; 
                }
            } else if ([keyword isEqualToString:@"type"]) {
                if ([schemaItem isKindOfClass:[NSString class]]) {
                    if ([type isEqualToString:@"integer"] && [schemaItem isEqualToString:@"number"]) {
                        continue; 
                    }
                    if (![schemaItem isEqualToString:type]) {
                        if (error) {
                            *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"JSON object type is not valid according to the specified type by the schema (type, schemaItem): (%@, %@)", type, schemaItem] forURL:nil detailedError:nil];
                        }
                        return NO;
                    }
                } else { //array
                    if (![schemaItem containsObject:type]) {
                        if (error) {
                            *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"JSON object type for array is not valid according to the specified type by the schema (type, schemaItem): (%@, %@)", type, schemaItem] forURL:nil detailedError:nil];
                        }
                        return NO; 
                    }
                }
            } else if ([keyword isEqualToString:@"allOf"]) {
                for (NSDictionary * subSchema in schemaItem) {
                    if (![self _validateJSON:json withSchemaDict:subSchema error:error]) {
                        if (error) {
                            *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"JSON object was not valid to allOf the specified schemas (json, schemaItem): (%@,%@)", json, schemaItem] forURL:nil detailedError:nil];
                        }
                        return NO;
                    }
                }
            } else if ([keyword isEqualToString:@"anyOf"]) {
                BOOL anySuccess = NO;
                for (NSDictionary * subSchema in schemaItem) {
                    if ([self _validateJSON:json withSchemaDict:subSchema error:error]) {
                        anySuccess = YES;
                        break;
                    }
                }
                if (!anySuccess) {
                    if (error) {
                        *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"JSON object was not valid to anyOf the specified schemas (json, schemaItem): (%@, %@)", json, schemaItem] forURL:nil detailedError:nil];
                    }
                    return NO;
                }
            } else if ([keyword isEqualToString:@"oneOf"]) {
                int passes = 0;
                for (NSDictionary * subSchema in schemaItem) {
                    if ([self _validateJSON:json withSchemaDict:subSchema error:error]) { passes++; }
                    if (passes > 1) {
                        if (error) {
                            *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"JSON object was valid to more than exactly oneOf the specified schemas (json, schemaItem): (%@, %@)", json, schemaItem] forURL:nil detailedError:nil];
                        }
                        return NO;
                    }
                }
                if (passes != 1) {
                    if (error) {
                        *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"JSON object was valid to less than exactly oneOf the specified schemas (json, schemaItem): (%@, %@)", json, schemaItem] forURL:nil detailedError:nil];
                    }
                    return NO;
                }
            } else if ([keyword isEqualToString:@"not"]) {
                if ([self _validateJSON:json withSchemaDict:schemaItem error:error]) {
                    if (error) {
                        *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"JSON object was valid to the specified schema while it should not be as specified by 'not' (json, schemaItem): (%@, %@)", json, schemaItem] forURL:nil detailedError:nil];
                    }
                    return NO;
                }
            } else if ([keyword isEqualToString:@"definitions"]) {
                
            }
        }
    }
    
    if (typeValidator != nil) {
        IMP imp = [self methodForSelector:typeValidator];
        NSError *detailedError = nil;
        BOOL (*func)(id, SEL, id, id, id*) = (BOOL(*)(id, SEL, id, id, id*))imp;
        if (!func(self, typeValidator, json, schema, &detailedError)) {
            if (error) {
                *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"JSON object was not valid according to the type specification (json, schema): (%@, %@)", json, schema] forURL:nil detailedError:detailedError];
            }
            return NO;
        }
    }
    
    return YES;
}

//for number and integer
-(BOOL)_validateJSONNumeric:(NSNumber*)jsonNumber withSchemaDict:(NSDictionary*)schema error:(NSError **)error
{
    static NSArray * numericKeywords;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        numericKeywords = @[@"multipleOf", @"maximum",/* @"exclusiveMaximum",*/ @"minimum",/* @"exclusiveMinimum"*/];
    });
    
    if (!schema || ![schema isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [self validationErrorWithDescription:@"Specified schema was not a valid dictionary" forURL:nil detailedError:nil];
        }
        return NO;
    }
    
    for (NSString * keyword in numericKeywords) {
        id schemaItem = schema[keyword];
        if (schemaItem != nil) {

            if ([keyword isEqualToString:@"multipleOf"]) {
                //A numeric instance is valid against "multipleOf" if the result of the division of the instance by this keyword's value is an integer.
                double divResult = [jsonNumber doubleValue] / [schemaItem doubleValue];
                if ((divResult - floor(divResult)) != 0.0) {
                    if (error) {
                        *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"Number '%@' is not a multiple of '%@'", jsonNumber, schemaItem] forURL:nil detailedError:nil];
                    }
                    return NO;
                }
            } else if ([keyword isEqualToString:@"maximum"]) {
                if ([schema[@"exclusiveMaximum"] isKindOfClass:[NSNumber class]] && [schema[@"exclusiveMaximum"] boolValue] == YES) {
                    if (!([jsonNumber doubleValue] < [schemaItem doubleValue])) {
                        //if "exclusiveMaximum" has boolean value true, the instance is valid if it is strictly lower than the value of "maximum".
                        if (error) {
                            *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"Number '%@' is not < '%@'", jsonNumber, schemaItem] forURL:nil detailedError:nil];
                        }
                        return NO;
                    }
                } else {
                    if (!([jsonNumber doubleValue] <= [schemaItem doubleValue])) {
                        //if "exclusiveMaximum" is not present, or has boolean value false, then the instance is valid if it is lower than, or equal to, the value of "maximum"
                        if (error) {
                            *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"Number '%@' is not <= '%@'", jsonNumber, schemaItem] forURL:nil detailedError:nil];
                        }
                        return NO;
                    }
                }
            } else if ([keyword isEqualToString:@"minimum"]) {
                if ([schema[@"exclusiveMinimum"] isKindOfClass:[NSNumber class]] && [schema[@"exclusiveMinimum"] boolValue] == YES) {
                    if (!([jsonNumber doubleValue] > [schemaItem doubleValue])) {
                        //if "exclusiveMinimum" is present and has boolean value true, the instance is valid if it is strictly greater than the value of "minimum".
                        if (error) {
                            *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"Number '%@' is not > '%@'", jsonNumber, schemaItem] forURL:nil detailedError:nil];
                        }
                        return NO;
                    }
                } else {
                    if (!([jsonNumber doubleValue] >= [schemaItem doubleValue])) {
                        //if "exclusiveMinimum" is not present, or has boolean value false, then the instance is valid if it is greater than, or equal to, the value of "minimum"
                        if (error) {
                            *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"Number '%@' is not >= '%@'", jsonNumber, schemaItem] forURL:nil detailedError:nil];
                        }
                        return NO;
                    }
                }
            }
        }
    }
    return YES;
}

-(BOOL)_validateJSONString:(NSString*)jsonString withSchemaDict:(NSDictionary*)schema error:(NSError **)error
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
                    if (error) {
                        *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"Length of string '%@' is not <= '%@'", jsonString, schemaItem] forURL:nil detailedError:nil];
                    }
                    return NO;
                }
            } else if ([keyword isEqualToString:@"minLength"]) {
                //A string instance is valid against this keyword if its length is greater than, or equal to, the value of this keyword.
                
                NSInteger realLength = [jsonString lengthOfBytesUsingEncoding:NSUTF32StringEncoding] / 4;
                if (!(realLength >= [schemaItem intValue])) {
                    if (error) {
                        *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"Length of string '%@' is not >= '%@'", jsonString, schemaItem] forURL:nil detailedError:nil];
                    }
                    return NO;
                }
            } else if ([keyword isEqualToString:@"pattern"]) {
                //A string instance is considered valid if the regular expression matches the instance successfully. Recall: regular expressions are not implicitly anchored.
                //This string SHOULD be a valid regular expression, according to the ECMA 262 regular expression dialect.
                //NOTE: this regex uses ICU which has some differences to ECMA-262 (such as look-behind)
                NSError * regexError = nil;
                NSRegularExpression * regex = [NSRegularExpression regularExpressionWithPattern:schemaItem options:0 error:&regexError];
                if (regex == nil) {
                    continue;
                }
                if (NSEqualRanges([regex rangeOfFirstMatchInString:jsonString options:0 range:NSMakeRange(0, jsonString.length)], NSMakeRange(NSNotFound, 0))) {
                    //A string instance is considered valid if the regular expression matches the instance successfully. Recall: regular expressions are not implicitly anchored.
                    if (error) {
                        *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"Pattern '%@' does not match string '%@'", schemaItem, jsonString] forURL:nil detailedError:nil];
                    }
                    return NO;
                }
            }
        }
    }
    return YES;
}

-(BOOL)_validateJSONObject:(NSDictionary*)jsonDict withSchemaDict:(NSDictionary*)schema error:(NSError **)error
{
    static NSArray * objectKeywords;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        objectKeywords = @[@"maxProperties", @"minProperties", @"required", @"properties", @"patternProperties", @"additionalProperties", @"dependencies"];
    });
    BOOL doneProperties = NO;
    NSError *detailedError = nil;
    for (NSString * keyword in objectKeywords) {
        id schemaItem = schema[keyword];
        if (schemaItem != nil) {

            if ([keyword isEqualToString:@"maxProperties"]) {
                //An object instance is valid against "maxProperties" if its number of properties is less than, or equal to, the value of this keyword.
                if ((NSInteger)[jsonDict count] > [schemaItem integerValue]) {
                    if (error) {
                        *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"Item count in json dict '%@' exceeds schema limit: %@", jsonDict, schemaItem] forURL:nil detailedError:nil];
                    }
                    return NO; /*invalid JSON dict*/
                }
            } else if ([keyword isEqualToString:@"minProperties"]) {
                //An object instance is valid against "minProperties" if its number of properties is greater than, or equal to, the value of this keyword.
                if ((NSInteger)[jsonDict count] < [schemaItem integerValue]) {
                    if (error) {
                        *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"Property count in json dict '%@' is less than min schema limit: %@", jsonDict, schemaItem] forURL:nil detailedError:nil];
                    }
                    return NO; /*invalid JSON dict*/
                }
            } else if ([keyword isEqualToString:@"required"]) {
                NSArray * requiredArray = schemaItem;
                for (NSObject * requiredProp in requiredArray) {
                    NSString * requiredPropStr = (NSString*)requiredProp;
                    if (![jsonDict valueForKey:requiredPropStr]) {
                        if (error) {
                            *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"Json dict '%@' does not contain required property: %@", jsonDict, requiredPropStr] forURL:nil detailedError:nil];
                        }
                        return NO; //required not present. invalid JSON dict.
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
                    NSError * regexError;
                    NSRegularExpression * regex = [NSRegularExpression regularExpressionWithPattern:regexString options:0 error:&regexError];
                    if (regex == nil) {
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
                        if (error) {
                            *error = [self validationErrorWithDescription:@"There are invalid properties left" forURL:nil detailedError:nil];
                        }
                        return NO;
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
                        if (![self _validateJSON:jsonDict[property] withSchemaDict:subschema error:&detailedError]) {
                            if (error) {
                                *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"Property '%@' is not valid according to schema: %@", property, subschema] forURL:nil detailedError:detailedError];
                            }
                            return NO;
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
                        if (![self _validateJSON:jsonDict withSchemaDict:schemaDependency error:&detailedError]) {
                            if (error) {
                                *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"JSON dict '%@' is not valid according to schema dependency: %@", jsonDict, schemaDependency] forURL:nil detailedError:detailedError];
                            }
                            return NO;
                        }
                    } else if ([dependency isKindOfClass:[NSArray class]]) {
                        NSArray * propertyDependency = dependency;
                        //For each (name, propertyset) pair of property dependencies, if the instance has a property by this name, then it must also have properties with the same names as propertyset.
                        NSSet * propertySet = [NSSet setWithArray:propertyDependency];
                        if (![propertySet isSubsetOfSet:properties]) {
                            if (error) {
                                *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"Property set %@ is not a subset of set: %@", propertySet, properties] forURL:nil detailedError:detailedError];
                            }
                            return NO;
                        }
                    }
                }
            }
        }
    }
    return YES;
}

-(BOOL)_validateJSONArray:(NSArray*)jsonArray withSchemaDict:(NSDictionary*)schema error:(NSError **)error
{
    static NSArray * arrayKeywords;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        arrayKeywords = @[@"additionalItems", @"items", @"maxItems", @"minItems", @"uniqueItems"];
    });
    
    BOOL doneItems = NO;
    NSError *detailedError = nil;
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
                        if (![self _validateJSON:jsonArray[index] withSchemaDict:items error:&detailedError]) {
                            if (error) {
                                *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"Item '%@' is not valid according to schema dict: %@", jsonArray[index], items] forURL:nil detailedError:detailedError];
                            }
                            return NO;
                        }
                    } else if ([items isKindOfClass:[NSArray class]]) {
                        if (index < [(NSArray *)items count]) {
                            if (![self _validateJSON:child withSchemaDict:items[index] error:&detailedError]) {
                                if (error) {
                                    *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"Item '%@' is not valid according to schema dict: %@", child, items[index]] forURL:nil detailedError:detailedError];
                                }
                                return NO;
                            }
                        } else {
                            if ([additionalItems isKindOfClass:[NSNumber class]] && [additionalItems boolValue] == NO) {
                                //if the value of "additionalItems" is boolean value false and the value of "items" is an array, the instance is valid if its size is less than, or equal to, the size of "items".
                                if (error) {
                                    *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"additionalItems is not in a valid format: %@", additionalItems] forURL:nil detailedError:detailedError];
                                }
                                return NO;
                            } else {
                                if (![self _validateJSON:child withSchemaDict:additionalItems error:&detailedError]) {
                                    if (error) {
                                        *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"Item '%@' is not valid according to additional items: %@", child, additionalItems] forURL:nil detailedError:detailedError];
                                    }
                                    return NO;
                                }
                            }
                        }
                    }
                }
            } else if ([keyword isEqualToString:@"maxItems"]) {
                //An array instance is valid against "maxItems" if its size is less than, or equal to, the value of this keyword.
                if ((NSInteger)[jsonArray count] > [schemaItem integerValue]) {
                    if (error) {
                        *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"Max item count of '%@' is exceeded by items: %@", schemaItem, jsonArray] forURL:nil detailedError:detailedError];
                    }
                    return NO;
                }
                //An array instance is valid against "minItems" if its size is greater than, or equal to, the value of this keyword.
            } else if ([keyword isEqualToString:@"minItems"]) {
                if ((NSInteger)[jsonArray count] < [schemaItem integerValue]) {
                    if (error) {
                        *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"Min item count of '%@' is not met by items: %@", schemaItem, jsonArray] forURL:nil detailedError:detailedError];
                    }
                    return NO;
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
                        if (error) {
                            *error = [self validationErrorWithDescription:[NSString stringWithFormat:@"Not all items are unique as required by schema for items: %@", jsonArray] forURL:nil detailedError:detailedError];
                        }
                        return NO;
                    }
                }
            }
        }
    }
    return YES;
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

- (NSError *)validationErrorWithDescription:(NSString *)description forURL:(nullable NSURL *)url detailedError:(nullable NSError *)detailedError {
    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    
    userInfo[NSLocalizedDescriptionKey] = description;
    
    if (url != nil) {
        userInfo[NSURLErrorKey] = url;
    }
    
    if (detailedError != nil) {
        userInfo[NSUnderlyingErrorKey] = detailedError;
    }
    
    return [NSError errorWithDomain:@"KiteJSONValidator" code:1 userInfo:userInfo];
}

@end
