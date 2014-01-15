//
//  Tests.m
//  Tests
//
//  Created by Sam Duke on 06/01/2014.
//
//

#import <XCTest/XCTest.h>
#import "KiteJSONValidator.h"

@interface Tests : XCTestCase

@end

@implementation Tests

- (void)setUp
{
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testFstab
{
    NSString *schemaPath = [[NSBundle bundleForClass:[self class]] pathForResource:@"fstab.schema"
                                                                            ofType:@"json"];
    NSData *schemaData = [NSData dataWithContentsOfFile:schemaPath];
    NSError *error = nil;
    id schemaJSON = [NSJSONSerialization JSONObjectWithData:schemaData
                                              options:kNilOptions
                                                error:&error];
    NSLog(@"Schema JSON: %@", schemaJSON);
    
    NSString *samplePath = [[NSBundle bundleForClass:[self class]] pathForResource:@"fstab-sample"
                                                                            ofType:@"json"];
    NSData *sampleData = [NSData dataWithContentsOfFile:samplePath];
    error = nil;
    id sampleJSON = [NSJSONSerialization JSONObjectWithData:sampleData
                                              options:kNilOptions
                                                error:&error];
    NSLog(@"Sample JSON: %@", sampleJSON);
    
    XCTAssertTrue([[KiteJSONValidator new] validateJSONDict:sampleJSON withSchemaDict:schemaJSON], @"fstab schema test failed");
}

//- (void)testExample
//{
//    XCTFail(@"No implementation for \"%s\"", __PRETTY_FUNCTION__);
//}

@end
