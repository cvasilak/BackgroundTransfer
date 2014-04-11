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

#import "AGBackgroundTransferViewController.h"
#import "AGAppDelegate.h"

@interface AGFile : NSObject

@property (nonatomic, copy) NSString *filename;
@property (nonatomic, strong) NSNumber *progress;
@property (nonatomic, assign) BOOL completed;

@end

@implementation AGFile

@end

@implementation AGBackgroundTransferViewController {
    NSMutableDictionary *_downloadTasks;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _downloadTasks = [NSMutableDictionary dictionary];
    
    AGAppDelegate *delegate = (AGAppDelegate *)[[UIApplication sharedApplication] delegate];
    
    // initialize with pending downloads as retrieved by the background session
    [[delegate backgroundURLSession] getTasksWithCompletionHandler:^(NSArray *dataTasks, NSArray *uploadTasks, NSArray *downloadTasks) {
        [downloadTasks enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            
            NSURLSessionDownloadTask *task = (NSURLSessionDownloadTask *)obj;
            
            AGFile *file = [[AGFile alloc] init];
            file.filename = [task.currentRequest.URL lastPathComponent];

            [_downloadTasks setObject:file forKey:[NSNumber numberWithInt:task.taskIdentifier]];
        }];
        
        // reload table
        [self.tableView reloadData];
    }];
    
    // register to receive notification during transfers
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNewDownloadNotification:)
                                                 name:@"AGNewDownloadNotification" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleUpdateProgressNotification:)
                                                 name:@"AGUpdateDownloadProgressNotification" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleDownloadCompletedNotification:)
                                                 name:@"AGDownloadCompletedNotification" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleAllDownloadsCompletedNotification:)
                                                 name:@"AGAllDownloadsCompletedNotification" object:nil];
    
}

#pragma mark - UITableViewDataSource delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _downloadTasks.allValues.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"Cell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
    }
    
    // TODO can be better
    NSArray *sorted = [_downloadTasks.allKeys sortedArrayUsingSelector:@selector(compare:)];
    
    AGFile *file = _downloadTasks[sorted[indexPath.row]];
    cell.textLabel.text = file.filename;
    
    if (!file.completed)
        cell.detailTextLabel.text = [NSString stringWithFormat:@"Downloading (%@%%)", file.progress ? file.progress.stringValue : @"calculating"];
    else
        cell.detailTextLabel.text = @"Downloaded";
    
    return cell;
}

#pragma mark notification handling

- (void)handleNewDownloadNotification:(NSNotification *)notification {
    NSDictionary *info = [notification userInfo];
    
    AGFile *file = [[AGFile alloc] init];
    file.filename = info[@"filename"];
    file.progress = [NSNumber numberWithInt:0];
    
    _downloadTasks[info[@"identifier"]] = file;
    
    [self.tableView reloadData];
}

- (void)handleUpdateProgressNotification:(NSNotification *)notification {
    NSDictionary *info = [notification userInfo];
    
    AGFile *file = _downloadTasks[info[@"identifier"]];
    file.progress = info[@"progress"];
    
    [self.tableView reloadData];
}

- (void)handleDownloadCompletedNotification:(NSNotification *)notification {
    NSDictionary *info = [notification userInfo];
    
    AGFile *file = _downloadTasks[info[@"identifier"]];
    file.completed = YES;
    
    [self.tableView reloadData];
}

- (void)handleAllDownloadsCompletedNotification:(NSNotification *)notification {
    
    [_downloadTasks enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        AGFile *file = (AGFile *)obj;
        file.completed = YES;
    }];
    
    [self.tableView reloadData];
}

@end
