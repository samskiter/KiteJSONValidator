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
                if ([json[@"description"] isEqualToString:@"root pointer"]) {
                    
                }
                NSString * resourceRoot = [[NSBundle bundleForClass:[self class]] resourcePath];
//                NSArray * refPaths = [[NSBundle bundleForClass:[self class]] pathsForResourcesOfType:@"json" inDirectory:@"JSON-Schema-Test-Suite/remotes"];
                NSString * directory = [resourceRoot stringByAppendingPathComponent:@"JSON-Schema-Test-Suite/remotes"];
                NSArray * refPaths = [self recursivePathsForResourcesOfType:@"json" inDirectory:directory];
                for (NSString * path in refPaths)
                {
                    NSString * fullpath  = [directory stringByAppendingPathComponent:path];
                    NSData * data = [NSData dataWithContentsOfFile:fullpath];
                    NSURL * url = [NSURL URLWithString:@"http://localhost:1234/"];
                    url = [NSURL URLWithString:path relativeToURL:url];
                    [validator addRefSchemaData:data atURL:url];
                }
                BOOL result = [validator validateJSONInstance:json[@"data"] withSchema:test[@"schema"]];
                BOOL desired = [json[@"valid"] boolValue];
                if (result != desired) {
                    XCTFail(@"Category: %@ Test: %@ Expected result: %i", test[@"description"], json[@"description"], desired);
                }
            }
        }
    }
}

- (NSArray *)recursivePathsForResourcesOfType:(NSString *)type inDirectory:(NSString *)directoryPath {
    NSMutableArray *filePaths = [[NSMutableArray alloc] init];
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:directoryPath];
    
    NSString *filePath;
    
    while ((filePath = [enumerator nextObject]) != nil) {
        if (!type || [[filePath pathExtension] isEqualToString:type]){
            [filePaths addObject:filePath];
        }
    }
    
    return filePaths;
}

@end
