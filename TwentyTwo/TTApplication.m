//
//  TTApplication.m
//  TwentyTwo
//
//  Created by Rafif Yalda on 2013/06/05.
//  Copyright (c) 2013 Rafif Yalda. All rights reserved.
//  Copyright (c) 2013 Rafif Yalda. All rights reserved.
//


#import "AppConstants.h"
#import "TTApplication.h"


@implementation TTApplication


- (void)sendEvent:(NSEvent *)theEvent
{
    if (theEvent.type == NSKeyDown &&
        theEvent.keyCode == 49)
    {
        // Handle the space-bar, even if the window is closed
        [[[NSWorkspace sharedWorkspace] notificationCenter] postNotificationName:TTApplicationDidPressSpaceBarKey object:theEvent];
        return;
    }

    [super sendEvent:theEvent];
}


@end
