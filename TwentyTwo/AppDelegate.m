//
//  AppDelegate.m
//  TwentyTwo
//
//  Created by Márton Salomváry on 2012/12/11.
//  Copyright (c) 2012 Márton Salomváry. All rights reserved.
//  Copyright (c) 2013 Marc Weistroff. All rights reserved.
//

#import "AppConstants.h"
#import "AppDelegate.h"

NSString *const TTNavigate = @"documentation.location = '%@'";
NSString *const TTPlayPause = @"angular.element($('[ng-controller=PlayerCtrl]')).scope().Audio.playpause();";
NSString *const TTNext = @"angular.element($('[ng-controller=PlayerCtrl]')).scope().Audio.next();";
NSString *const TTPrev = @"angular.element($('[ng-controller=PlayerCtrl]')).scope().Audio.previous();";
NSString *const TTIsPlaying = @"$('.playpause.play')";

NSURL *baseUrl = nil;


@interface WebPreferences (WebPreferencesPrivate)
- (void)_setLocalStorageDatabasePath:(NSString *)path;
- (void) setLocalStorageEnabled: (BOOL) localStorageEnabled;
@end

@implementation AppDelegate

@synthesize webView;
@synthesize popupController;
@synthesize window;
@synthesize urlPromptController;

id contentView;
id tmpHostWindow;

+ (void)initialize;
{
	if([self class] != [AppDelegate class]) return;
    
	// Register defaults for the whitelist of apps that want to use media keys
	[[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
                                                             [SPMediaKeyTap defaultMediaKeyUserBundleIdentifiers], kMediaKeyUsingBundleIdentifiersDefaultsKey,
                                                             nil]];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    [window setFrameAutosaveName:@"TwentyTwo"];
    
    keyTap = [[SPMediaKeyTap alloc] initWithDelegate:self];
	if([SPMediaKeyTap usesGlobalMediaKeyTap])
		[keyTap startWatchingMediaKeys];
	else
		NSLog(@"Media key monitoring disabled");
    
    baseUrl = [NSURL URLWithString:[[NSUserDefaults standardUserDefaults] stringForKey:@"BaseUrl"]];
    if (baseUrl == nil) {
        baseUrl = [NSURL URLWithString: [@"http://" stringByAppendingString:TTHost]];
    }

    [[webView mainFrame] loadRequest: [NSURLRequest requestWithURL:baseUrl]];
    
    WebPreferences* prefs = [WebPreferences standardPreferences];
    
    [prefs setCacheModel:WebCacheModelPrimaryWebBrowser];
    [prefs setPlugInsEnabled:TRUE]; // Flash is required for playing sounds in certain cases
    
    [prefs _setLocalStorageDatabasePath:@"~/Library/Application Support/TwentyTwo"];
    [prefs setLocalStorageEnabled:YES];
    
    [webView setPreferences:prefs];
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                           selector: @selector(receiveSleepNotification:)
                                                               name: NSWorkspaceWillSleepNotification object: NULL];

    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                           selector: @selector(didPressSpaceBarKey:)
                                                               name: TTApplicationDidPressSpaceBarKey object: NULL];

    [window setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];
}


- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)flag
{
    if (flag == NO)
    {
        [window makeKeyAndOrderFront:self];
    }

    return YES;
}


- (void)awakeFromNib
{
    [window setDelegate:self];
    [webView setUIDelegate:self];
    [webView setFrameLoadDelegate:self];
    [webView setPolicyDelegate:self];

    [urlPromptController setNavigateDelegate:self];
    
    // stored for adding back later, see windowWillClose
    contentView = [window contentView];
}

- (void)windowDidBecomeKey:(NSNotification *)notification
{
    // restore "hidden" webview, see windowShouldClose
    // (would be better to do it in applicationShouldHandleReopen
    // but that seems to be too early (has no effect)
    if ([window contentView] != contentView) {
        [window setContentView:contentView];
        [webView setHostWindow:nil];
        tmpHostWindow = nil;
    }
}

- (BOOL)windowShouldClose:(NSNotification *)notification
{
    // set temporary hostWindow on WebView and remove it from
    // the closed window to prevent stopping flash plugin
    // (windowWillClose would be better but that doesn't always work)
    // http://stackoverflow.com/questions/5307423/plugin-objects-in-webview-getting-destroyed
    // https://developer.apple.com/library/mac/documentation/Cocoa/Reference/WebKit/Classes/WebView_Class/Reference/Reference.html#//apple_ref/occ/instm/WebView/setHostWindow%3a
    tmpHostWindow = [[NSWindow alloc] init];
    [webView setHostWindow:tmpHostWindow];
    [window setContentView:nil];
    [contentView removeFromSuperview];
    
    return TRUE;
}

- (WebView *)webView:(WebView *)sender createWebViewWithRequest:(NSURLRequest *)request
{
    // request will always be null (probably a bug)
    return [popupController show];
}

- (void)webView:(WebView *)sender didReceiveTitle:(NSString *)title forFrame:(WebFrame *)frame
{
    if (frame == [webView mainFrame]) {
        [window setTitle:title];
        if ([self isPlaying]) {
            title = [title stringByReplacingOccurrencesOfString:@"▶ " withString:@""];
            NSArray *info = [title componentsSeparatedByString:@" by "];
            if (info.count == 1) {
                // current track is part of a set
                info = [title componentsSeparatedByString:@" in "];
            }
            NSUserNotification *notification = [[NSUserNotification alloc] init];
            notification.title = info[0]; // track
            notification.informativeText = info[1]; // artist
            [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
        }
    }
}

- (void)webView:(WebView *)sender decidePolicyForNavigationAction:(NSDictionary *)actionInformation
        request:(NSURLRequest *)request frame:(WebFrame *)frame decisionListener:(id)listener
{
    // normal in-frame navigation
    if(frame != [webView mainFrame] || [AppDelegate isTTURL:[request URL]]) {
        // allow loading urls in sub-frames OR when they are sc urls
        [listener use];
    } else {
        [listener ignore];
        // open external links in external browser
        [[NSWorkspace sharedWorkspace] openURL:[actionInformation objectForKey:WebActionOriginalURLKey]];
    }
}

- (void)webView:(WebView *)sender decidePolicyForNewWindowAction:(NSDictionary *)actionInformation request:(NSURLRequest *)request newFrameName:(NSString *)frameName decisionListener:(id < WebPolicyDecisionListener >)listener
{
    // target=_blank or anything scenario
    [listener ignore];
    if([AppDelegate isTTURL:[request URL]]) {
        // open local links in the main frame
        // TODO: maybe maintain a frame stack instead?
        [[webView mainFrame] loadRequest: [NSURLRequest requestWithURL:
                                           [actionInformation objectForKey:WebActionOriginalURLKey]]];
    } else {
        // open external links in external browser
        [[NSWorkspace sharedWorkspace] openURL:[actionInformation objectForKey:WebActionOriginalURLKey]];
    }

}

// based on http://stackoverflow.com/questions/5177640
- (void)webView:(WebView *)sender runOpenPanelForFileButtonWithResultListener:(id < WebOpenPanelResultListener >)resultListener allowMultipleFiles:(BOOL)allowMultipleFiles
{
    // Create the File Open Dialog class.
    NSOpenPanel* openDlg = [NSOpenPanel openPanel];

    // Enable the selection of files in the dialog.
    [openDlg setCanChooseFiles:YES];

    // Enable the selection of directories in the dialog.
    [openDlg setCanChooseDirectories:NO];

    // Allow multiple files
    [openDlg setAllowsMultipleSelection:allowMultipleFiles];

    // Display the dialog.  If the OK button was pressed,
    // process the files.
    if ( [openDlg runModal] == NSOKButton )
    {
		NSArray *urls = [openDlg URLs];
		NSArray *filenames = [urls valueForKey:@"path"];
        // Do something with the filenames.
        [resultListener chooseFilenames:filenames];
    }
}

// stolen from MacGap
- (BOOL)webView:(WebView *)sender runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WebFrame *)frame
{
    NSAlert *alert = [[NSAlert alloc] init];
    [alert addButtonWithTitle:@"Yes"];
    [alert addButtonWithTitle:@"No"];
    [alert setMessageText:message];
    [alert setAlertStyle:NSWarningAlertStyle];
    
    if ([alert runModal] == NSAlertFirstButtonReturn)
        return YES;
    else
        return NO;
}

- (void)receiveSleepNotification:(NSNotification*)note
{
    if([self isPlaying]) {
        [self playPause];
    }
}

- (void)mediaKeyTap:(SPMediaKeyTap*)keyTap receivedMediaKeyEvent:(NSEvent*)event;
{
	NSAssert([event type] == NSSystemDefined && [event subtype] == SPSystemDefinedEventMediaKeys, @"Unexpected NSEvent in mediaKeyTap:receivedMediaKeyEvent:");
	// here be dragons...
	int keyCode = (([event data1] & 0xFFFF0000) >> 16);
	int keyFlags = ([event data1] & 0x0000FFFF);
	BOOL keyIsPressed = (((keyFlags & 0xFF00) >> 8)) == 0xA;
	//int keyRepeat = (keyFlags & 0x1);
    
	if (keyIsPressed) {
		switch (keyCode) {
			case NX_KEYTYPE_PLAY:
                [self playPause];
				break;
                
			case NX_KEYTYPE_FAST:
				[self next];
                break;
                
			case NX_KEYTYPE_REWIND:
                [self prev];
				break;
			default:
				NSLog(@"Key %d pressed", keyCode);
				break;
		}
	}
}


- (IBAction)showHelp:(id)sender
{
}

- (IBAction)restoreWindow:(id)sender
{
    [window makeKeyAndOrderFront:self];
}

- (IBAction)reload:(id)sender
{
    [webView reload:self];
}

- (void)next
{
    [webView stringByEvaluatingJavaScriptFromString:TTNext];
}

- (void)prev
{
    [webView stringByEvaluatingJavaScriptFromString:TTPrev];
}

- (void)playPause
{
    [webView stringByEvaluatingJavaScriptFromString:TTPlayPause];
}

- (BOOL)isPlaying
{
    return [[webView stringByEvaluatingJavaScriptFromString:TTIsPlaying]  isEqual: @""];
}

- (void)navigate:(NSString*)permalink
{
    NSString *js = [NSString stringWithFormat:TTNavigate, permalink];
    [webView stringByEvaluatingJavaScriptFromString:js];
}

+ (BOOL)isTTURL:(NSURL *)url
{
    if(url != nil) {
        if([url host] != nil) {
            if([[url host] isEqualToString:TTHost] || [[url host] isEqualToString:[baseUrl host]]) {
                return TRUE;
            }
        }
    }
    return FALSE;
}


#pragma mark - Notifications
- (void)didPressSpaceBarKey:(NSNotification *)notification
{
    NSEvent *event = (NSEvent *)notification.object;
    [self.window sendEvent:event];
}


@end
