//
//  Tests.m
//  Tests
//
//  Created by Sam Duke on 19/01/2014.
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

- (void)testExample
{
//    XCTFail(@"No implementation for \"%s\"", __PRETTY_FUNCTION__);
}

- (void)testTestSuite
{
    NSArray * paths = [[NSBundle bundleForClass:[self class]] pathsForResourcesOfType:@"json" inDirectory:@"JSON-Schema-Test-Suite/tests/draft4"];
    for (NSString * path in paths) {
        NSData *testData = [NSData dataWithContentsOfFile:path];
        NSError *error = nil;
        NSDictionary * tests = [NSJSONSerialization JSONObjectWithData:testData
                                                                    options:kNilOptions
                                                                      error:&error];
        if (error != nil) {
            XCTFail(@"Failed to load test file: %@", path);
            continue;
        }
        
        for (NSDictionary * test in tests) {
            for (NSDictionary * json in test[@"tests"]) {
                KiteJSONValidator * validator = [KiteJSONValidator new];
                BOOL result = [validator validateJSON:json[@"data"] withSchemaDict:test[@"schema"]];
                if (result != (BOOL)json[@"valid"]) {
                    XCTFail(@"Category: %@ Test: %@ Expected result: %i", test[@"description"], json[@"description"], !result);
                }
            }
        }
    }
}

@end
