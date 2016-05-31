//
//  QMUserInfoViewController.m
//  Q-municate
//
//  Created by Vitaliy Gorbachov on 3/23/16.
//  Copyright © 2016 Quickblox. All rights reserved.
//

#import "QMUserInfoViewController.h"
#import "QMCore.h"
#import "UINavigationController+QMNotification.h"
#import "QMPlaceholder.h"
#import "QMChatVC.h"
#import <QMDateUtils.h>
#import <QMImageView.h>
#import "QBChatDialog+OpponentID.h"
#import <SVProgressHUD.h>

static const CGFloat kQMStatusCellMinHeight = 65.0f;

typedef NS_ENUM(NSUInteger, QMUserInfoSection) {
    
    QMUserInfoSectionStatus,
    QMUserInfoSectionInfo,
    QMUserInfoSectionContactInteractions,
    QMUserInfoSectionAddAction
};

@interface QMUserInfoViewController ()

<
QMContactListServiceDelegate
>

@property (weak, nonatomic) BFTask *task;

@property (weak, nonatomic) IBOutlet QMImageView *avatarImageView;

@property (weak, nonatomic) IBOutlet UILabel *fullNameLabel;
@property (weak, nonatomic) IBOutlet UILabel *lastSeenLabel;
@property (weak, nonatomic) IBOutlet UILabel *statusLabel;
@property (weak, nonatomic) IBOutlet UILabel *phoneLabel;
@property (weak, nonatomic) IBOutlet UILabel *emailLabel;

@property (strong, nonatomic) NSMutableIndexSet *hiddenSections;

@end

@implementation QMUserInfoViewController

+ (instancetype)userInfoViewControllerWithUser:(QBUUser *)user {
    
    QMUserInfoViewController *userInfoViewController = [[UIStoryboard storyboardWithName:kQMChatStoryboard bundle:nil] instantiateViewControllerWithIdentifier:NSStringFromClass([self class])];
    userInfoViewController.user = user;
    
    return userInfoViewController;
}

- (void)dealloc {
    
    ILog(@"%@ - %@",  NSStringFromSelector(_cmd), self);
}

- (void)viewDidLoad {
    
    NSAssert(self.user.ID > 0, @"Must be a valid user ID!");
    
    [super viewDidLoad];
    
    self.hiddenSections = [NSMutableIndexSet indexSet];
    self.avatarImageView.imageViewType = QMImageViewTypeCircle;
    
    // Hide empty separators
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    
    // automatic self-sizing cells (used for status cell, due to status label could be multiline)
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = kQMStatusCellMinHeight;
    
    // subscribing to delegates
    [[QMCore instance].contactListService addDelegate:self];
    
    // update info table
    [self performUpdate];
    
    if (self.user.lastRequestAt == nil) {
        
        [self.navigationController showNotificationWithType:QMNotificationPanelTypeLoading message:NSLocalizedString(@"QM_STR_LOADING", nil) duration:0];
        
        [self loadUser];
    }
    
    // adding refresh control task
    if (self.refreshControl) {
        
        self.refreshControl.backgroundColor = [UIColor whiteColor];
        [self.refreshControl addTarget:self
                                action:@selector(loadUser)
                      forControlEvents:UIControlEventValueChanged];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // smooth rows deselection
    [self qm_smoothlyDeselectRowsForTableView:self.tableView];
}

#pragma mark - Methods

- (void)loadUser {
    
    __weak UINavigationController *navigationController = self.navigationController;
    
    // get user from server
    @weakify(self);
    [[[QMCore instance].usersService getUserWithID:self.user.ID forceLoad:YES] continueWithBlock:^id _Nullable(BFTask<QBUUser *> * _Nonnull task) {
        
        @strongify(self);
        [navigationController dismissNotificationPanel];
        [self.refreshControl endRefreshing];
        
        if (!task.isFaulted) {
            
            self.user = task.result;
            [self performUpdate];
            [self.tableView reloadData];
        }
        
        return nil;
    }];
}

- (void)performUpdate {
    
    [self.hiddenSections removeAllIndexes];
    
    [self updateFullName];
    [self updateAvatarImage];
    [self updateUserIteractions];
    [self updateLastSeen];
    [self updateStatus];
    [self updateInfo];
}

- (void)updateFullName {
    
    // Full name
    self.fullNameLabel.text = self.user.fullName;
}

- (void)updateAvatarImage {
    
    // Avatar
    UIImage *placeholder = [QMPlaceholder placeholderWithFrame:self.avatarImageView.bounds title:self.user.fullName ID:self.user.ID];
    [self.avatarImageView setImageWithURL:[NSURL URLWithString:self.user.avatarUrl]
                              placeholder:placeholder
                                  options:SDWebImageHighPriority
                                 progress:nil
                           completedBlock:nil];
}

- (void)updateUserIteractions {
    
    BOOL isFriend = [[QMCore instance].contactManager isFriendWithUserID:self.user.ID];
    if (isFriend) {
        
        [self.hiddenSections addIndex:QMUserInfoSectionAddAction];
    }
    else {
        
        [self.hiddenSections addIndex:QMUserInfoSectionContactInteractions];
        
        BOOL isAwaitingForApproval = [[QMCore instance].contactManager isContactListItemExistentForUserWithID:self.user.ID];
        if (isAwaitingForApproval) {
            
            [self.hiddenSections addIndex:QMUserInfoSectionAddAction];
        }
    }
}

- (void)updateLastSeen {
    
    // Last seen
    BOOL isOnline = [[QMCore instance].contactManager isUserOnlineWithID:self.user.ID];
    if (isOnline) {
        
        self.lastSeenLabel.text = NSLocalizedString(@"QM_STR_ONLINE", nil);
    }
    else if (self.user.lastRequestAt) {
        
        self.lastSeenLabel.text = [NSString stringWithFormat:@"%@ %@", NSLocalizedString(@"QM_STR_LAST_SEEN", nil), [QMDateUtils formattedLastSeenString:self.user.lastRequestAt withTimePrefix:NSLocalizedString(@"QM_STR_TIME_PREFIX", nil)]];
    }
    else {
        
        self.lastSeenLabel.text = NSLocalizedString(@"QM_STR_OFFLINE", nil);
    }
}

- (void)updateStatus {
    
    // Status
    NSCharacterSet *whiteSpaceSet = [NSCharacterSet whitespaceCharacterSet];
    if ([[self.user.status stringByTrimmingCharactersInSet:whiteSpaceSet] length] > 0) {
        
        self.statusLabel.text = self.user.status;
    }
    else {
        
        [self.hiddenSections addIndex:QMUserInfoSectionStatus];
    }
}

- (void)updateInfo {
    
    if (self.user.email.length > 0 || self.user.phone.length > 0) {
        
        // Phone
        self.phoneLabel.text = self.user.phone.length > 0 ? self.user.phone : NSLocalizedString(@"QM_STR_NONE", nil);
        // Email
        self.emailLabel.text = self.user.email.length > 0 ? self.user.email : NSLocalizedString(@"QM_STR_NONE", nil);
    }
    else {
        
        // hide section
        [self.hiddenSections addIndex:QMUserInfoSectionInfo];
    }
}

#pragma mark - Actions

- (IBAction)sendMessageButtonPressed {
    
    __block BOOL chatDialogFound = NO;
    
    @weakify(self);
    [self.navigationController.viewControllers enumerateObjectsUsingBlock:^(__kindof UIViewController * _Nonnull obj, NSUInteger __unused idx, BOOL * _Nonnull stop) {
        // enumerating through all view controllers due to
        // navigation stack could have more than one chat view controller
        @strongify(self);
        if ([obj isKindOfClass:[QMChatVC class]]) {
            
            QBChatDialog *chatDialog = [(QMChatVC *)obj chatDialog];
            if (chatDialog.opponentID == self.user.ID) {
                
                [self.navigationController popToViewController:obj animated:YES];
                *stop = YES;
                chatDialogFound = YES;
            }
        }
    }];
    
    if (chatDialogFound) {
        // chat dialog was found in navigation stack
        return;
    }
    
    QBChatDialog *privateChatDialog = [[QMCore instance].chatService.dialogsMemoryStorage privateChatDialogWithOpponentID:self.user.ID];
    
    if (privateChatDialog) {
        
        [self performSegueWithIdentifier:kQMSceneSegueChat sender:privateChatDialog];
    }
    else {
        
        if (self.task) {
            // task in progress
            return;
        }
        
        [self.navigationController showNotificationWithType:QMNotificationPanelTypeLoading message:NSLocalizedString(@"QM_STR_LOADING", nil) duration:0];
        
        __weak UINavigationController *navigationController = self.navigationController;
        
        self.task = [[[QMCore instance].chatService createPrivateChatDialogWithOpponentID:self.user.ID] continueWithBlock:^id _Nullable(BFTask<QBChatDialog *> * _Nonnull task) {
            
            @strongify(self);
            [navigationController dismissNotificationPanel];
            
            if (!task.isFaulted) {
                
                [self performSegueWithIdentifier:kQMSceneSegueChat sender:task.result];
            }
            
            return nil;
        }];
    }
}

- (BOOL)callAllowed {
    
    if (![QMCore instance].isInternetConnected) {
        
        [self.navigationController showNotificationWithType:QMNotificationPanelTypeWarning message:NSLocalizedString(@"QM_STR_CHECK_INTERNET_CONNECTION", nil) duration:kQMDefaultNotificationDismissTime];
        return NO;
    }
    
    if (![QBChat instance].isConnected) {
        
        [self.navigationController showNotificationWithType:QMNotificationPanelTypeFailed message:NSLocalizedString(@"QM_STR_CHAT_SERVER_UNAVAILABLE", nil) duration:kQMDefaultNotificationDismissTime];
        return NO;
    }
    
    return YES;
}

- (IBAction)audioCallButtonPressed {
    
    if (![self callAllowed]) {
        
        return;
    }
    
    [[QMCore instance].callManager callToUserWithID:self.user.ID conferenceType:QBRTCConferenceTypeAudio];
}

- (IBAction)videoCallButtonPressed {
    
    if (![self callAllowed]) {
        
        return;
    }
    
    [[QMCore instance].callManager callToUserWithID:self.user.ID conferenceType:QBRTCConferenceTypeVideo];
}

- (IBAction)removeContactButtonPressed {
    
    if (self.task) {
        // task in progress
        return;
    }
    
    UIAlertController *alertController = [UIAlertController
                                          alertControllerWithTitle:nil
                                          message:[NSString stringWithFormat:NSLocalizedString(@"QM_STR_CONFIRM_DELETE_CONTACT", nil), self.user.fullName]
                                          preferredStyle:UIAlertControllerStyleAlert];
    
    [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"QM_STR_CANCEL", nil)
                                                        style:UIAlertActionStyleCancel
                                                      handler:^(UIAlertAction * _Nonnull __unused action) {
                                                          
                                                      }]];
    
    [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"QM_STR_DELETE", nil)
                                                        style:UIAlertActionStyleDestructive
                                                      handler:^(UIAlertAction * _Nonnull __unused action) {
                                                          
                                                          [SVProgressHUD showWithMaskType:SVProgressHUDMaskTypeClear];
                                                          
                                                          self.task = [[[QMCore instance].contactManager removeUserFromContactList:self.user] continueWithBlock:^id _Nullable(BFTask * _Nonnull __unused task) {
                                                              
                                                              [SVProgressHUD dismiss];
                                                              
                                                              return nil;
                                                          }];
                                                      }]];
    
    [self presentViewController:alertController animated:YES completion:nil];
}

- (IBAction)addUserButtonPressed {
    
    if (self.task) {
        // task in progress
        return;
    }
    
    [self.navigationController showNotificationWithType:QMNotificationPanelTypeLoading message:NSLocalizedString(@"QM_STR_LOADING", nil) duration:0];
    
    __weak UINavigationController *navigationController = self.navigationController;
    
    self.task = [[[QMCore instance].contactManager addUserToContactList:self.user] continueWithBlock:^id _Nullable(BFTask * _Nonnull __unused task) {
        
        [navigationController dismissNotificationPanel];
        return nil;
    }];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    
    if ([segue.identifier isEqualToString:kQMSceneSegueChat]) {
        
        QMChatVC *chatVC = segue.destinationViewController;
        chatVC.chatDialog = sender;
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    
    if ([self.hiddenSections containsIndex:section]) {
        
        return 0;
    }
    
    return [super tableView:tableView numberOfRowsInSection:section];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    if (indexPath.section == QMUserInfoSectionStatus) {
        // due to status could be multiline, need to automatically resize it
        return UITableViewAutomaticDimension;
    }
    
    return [super tableView:tableView heightForRowAtIndexPath:indexPath];
}

#pragma mark - QMContactListServiceDelegate

- (void)contactListServiceDidLoadCache {
    
    [self performUpdate];
    [self.tableView reloadData];
}

- (void)contactListService:(QMContactListService *)__unused contactListService contactListDidChange:(QBContactList *)__unused contactList {
    
    [self performUpdate];
    [self.tableView reloadData];
}

@end
