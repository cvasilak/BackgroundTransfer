/*
 * JBoss, Home of Professional Open Source.
 * Copyright Red Hat, Inc., and individual contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "AGAppDelegate.h"
#import "AGBackgroundTransferViewController.h"

#import "AeroGearPush.h"

typedef void (^CompletionHandler)();

@implementation AGAppDelegate {
    NSMutableDictionary *_completionHandlerDictionary;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    _completionHandlerDictionary = [NSMutableDictionary dictionary];
    
     // register with Apple Push Notification Service (APNS)
    // to retrieve the device token.
    [[UIApplication sharedApplication] registerForRemoteNotificationTypes:
     (UIRemoteNotificationTypeBadge | UIRemoteNotificationTypeSound | UIRemoteNotificationTypeAlert)];
    
    [self.window makeKeyAndVisible];
    return YES;
}

#pragma mark - Push Notification handling

// Upon successfully registration with APNS, we register the device to 'AeroGear Push Server'
- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
    
    // initialize "Registration helper" object using the
    // base URL where the "AeroGear Unified Push Server" is running.
    AGDeviceRegistration *registration =
    
    [[AGDeviceRegistration alloc] initWithServerURL:[NSURL URLWithString:@"http://192.168.1.10:8080/ag-push"]];
    
    // perform registration of this device
    [registration registerWithClientInfo:^(id<AGClientDeviceInformation> clientInfo) {
        // set up configuration parameters
        
        // apply the deviceToken as received by Apple's Push Notification service
        [clientInfo setDeviceToken:deviceToken];
        
        // You need to fill the 'Variant Id' together with the 'Variant Secret'
        // both received when performing the variant registration with the server.
        // See section "Register an iOS Variant" in the guide:
        // http://aerogear.org/docs/guides/aerogear-push-ios/unified-push-server/
        [clientInfo setVariantID:@"6d69d137-77b8-4818-889d-583bb48657db"];
        [clientInfo setVariantSecret:@"0151f65f-8ee4-4cdd-8229-b1cd8ae244a7"];
        
        // --optional config--
        // set some 'useful' hardware information params
        UIDevice *currentDevice = [UIDevice currentDevice];
        
        [clientInfo setOperatingSystem:[currentDevice systemName]];
        [clientInfo setOsVersion:[currentDevice systemVersion]];
        [clientInfo setDeviceType: [currentDevice model]];
        
    } success:^() {
        // successfully registered!
        NSLog(@"Successfully registered on UPS server!");
        
    } failure:^(NSError *error) {
        // An error occurred during registration.
        // Let's log it for now
        NSLog(@"Failed to register on UPS server! %@", error);
    }];
}

// Callback called after failing to register with APNS
- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
    // Log the error for now
    NSLog(@"APNs Error: %@", error);
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    
    NSLog(@"Received remote notification with userInfo %@", userInfo);
    
    // extract the URL from the notification
    NSURL *downloadURL = [NSURL URLWithString:userInfo[@"url"]];
    
    // setup request
    NSURLRequest *request = [NSURLRequest requestWithURL:downloadURL];
    
    // create download task
    NSURLSessionDownloadTask *task = [[self backgroundURLSession] downloadTaskWithRequest:request];
    
    // start downloading
    [task resume];

    // notify any interested listeners for the new download (e.g. to update UI)
    [[NSNotificationCenter defaultCenter] postNotificationName:@"AGNewDownloadNotification" object:nil
                                                      userInfo:@{@"filename": downloadURL.lastPathComponent,
                                                                 @"identifier" : [NSNumber numberWithInt:task.taskIdentifier]}];
    // let the system know we started transfer
    completionHandler(UIBackgroundFetchResultNewData);
}

- (void)application:(UIApplication *)application handleEventsForBackgroundURLSession:(NSString *)identifier
  completionHandler:(void (^)())completionHandler {
    NSURLSession *backgroundSession = [self backgroundURLSession];
    NSLog(@"Rejoining session with identifier %@ %@", identifier, backgroundSession);
    
    // store the completion handler
    _completionHandlerDictionary[identifier] = completionHandler;
}

#pragma mark - NSURLSessionDelegate methods

- (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session {
    NSLog(@"Background URL session %@ finished events.\n", session);
    
    NSString *identifier = session.configuration.identifier;
    if (identifier) {
        [self presentCompletedLocalNotification];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:@"AGAllDownloadsCompletedNotification" object:nil userInfo:nil];
        
        CompletionHandler handler = _completionHandlerDictionary[identifier];
        if (handler)
            handler();
    }
}

#pragma mark - NSURLSessionDownloadDelegate methods

- (void) URLSession:(NSURLSession *)session
       downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location {
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"AGDownloadCompletedNotification" object:nil
                                                      userInfo:@{@"identifier" : [NSNumber numberWithInt:downloadTask.taskIdentifier]}];
}

- (void) URLSession:(NSURLSession *)session
       downloadTask:(NSURLSessionDownloadTask *)downloadTask
       didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    
    NSUInteger progress = (totalBytesWritten / (float)totalBytesExpectedToWrite) * 100;
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"AGUpdateDownloadProgressNotification" object:nil
                                                      userInfo:@{@"identifier" : [NSNumber numberWithInt:downloadTask.taskIdentifier],
                                                                 @"progress": [NSNumber numberWithInt:progress]}];
}

- (void)  URLSession:(NSURLSession *)session
        downloadTask:(NSURLSessionDownloadTask *)downloadTask
   didResumeAtOffset:(int64_t)fileOffset
  expectedTotalBytes:(int64_t)expectedTotalBytes {
    
    // unused currently
}

# pragma mark - Utility methods

-(void)presentCompletedLocalNotification {
    UILocalNotification* localNotification = [[UILocalNotification alloc] init];
    localNotification.alertBody = @"All Downloads completed!";
    localNotification.soundName = UILocalNotificationDefaultSoundName;
    
    [[UIApplication sharedApplication] presentLocalNotificationNow:localNotification];
}

- (NSURLSession *)backgroundURLSession {
    static NSURLSession *session = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        NSString *identifier = @"org.aerogear.BackgroundTransferSession";
        NSURLSessionConfiguration* sessionConfig = [NSURLSessionConfiguration backgroundSessionConfiguration:identifier];
        session = [NSURLSession sessionWithConfiguration:sessionConfig
                                                delegate:self
                                           delegateQueue:[NSOperationQueue mainQueue]];
    });
    
    return session;
}

@end
