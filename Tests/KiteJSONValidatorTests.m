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

- (void)testDraft4Suite
{
    NSBundle * mainBundle = [NSBundle bundleForClass:[self class]];
    NSArray * paths = [mainBundle pathsForResourcesOfType:@"json" inDirectory:@"JSON-Schema-Test-Suite/tests/draft4"];
    NSString * directory = [[mainBundle resourcePath] stringByAppendingPathComponent:@"JSON-Schema-Test-Suite/remotes"];
    NSArray * refPaths = [self recursivePathsForResourcesOfType:@"json" inDirectory:directory];

    unsigned int successes = 0;

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
                for (NSString * refPath in refPaths)
                {
                    NSString * fullpath  = [directory stringByAppendingPathComponent:refPath];
                    NSData * data = [NSData dataWithContentsOfFile:fullpath];
                    NSURL * url = [NSURL URLWithString:@"http://localhost:1234/"];
                    url = [NSURL URLWithString:refPath relativeToURL:url];
                    NSError* addRefError = [validator addRefSchemaData:data atURL:url];
                    XCTAssertNil(addRefError, @"Unable to add the reference schema at '%@': %@", url, addRefError.localizedDescription);
                }
                
                error = [validator validateJSONInstance:json[@"data"] withSchema:test[@"schema"]];
                BOOL desired = [json[@"valid"] boolValue];
                
                if (error)
                {
                    NSLog(@"error: %@", error.localizedDescription);
                }
                
                if ((error?YES:NO) == desired) {
                    XCTFail(@"Category: %@ Test: %@ Expected result: %i", test[@"description"], json[@"description"], desired);
                }
                else
                {
                    successes++;
                }
            }
        }
    }

    XCTAssertTrue(successes >= 251, @"Expected at least 251 test successes (as of draft v4), but found %ud", successes);
}

- (NSArray *)recursivePathsForResourcesOfType:(NSString *)type inDirectory:(NSString *)directoryPath {
    NSMutableArray *filePaths = [[NSMutableArray alloc] init];
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:directoryPath];
    NSString *filePath = nil;
    
    while ((filePath = [enumerator nextObject]) != nil) {
        if (!type || [[filePath pathExtension] isEqualToString:type]){
            [filePaths addObject:filePath];
        }
    }
    
    return filePaths;
}

@end
