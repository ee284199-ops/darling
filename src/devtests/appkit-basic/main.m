// AppKitBasic: a small AppKit smoke test for Darling.
//
// Opens one window with a custom-drawn view (solid fills, a stroked oval and a
// line of text) above a few standard controls. Each milestone is logged to
// stderr, and the app quits by itself after DEVTEST_AUTOQUIT seconds when that
// environment variable is set.

#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

static void milestone(const char* what)
{
	fprintf(stderr, "[AppKitBasic] %s\n", what);
}

@interface PaintView : NSView
@end

@implementation PaintView

- (void)drawRect: (NSRect)dirtyRect
{
	milestone("drawRect");

	[[NSColor whiteColor] set];
	NSRectFill([self bounds]);

	[[NSColor redColor] set];
	NSRectFill(NSMakeRect(20, 20, 100, 100));
	[[NSColor greenColor] set];
	NSRectFill(NSMakeRect(140, 20, 100, 100));
	[[NSColor blueColor] set];
	NSRectFill(NSMakeRect(260, 20, 100, 100));

	NSBezierPath* oval = [NSBezierPath bezierPathWithOvalInRect: NSMakeRect(380, 20, 150, 100)];
	[oval setLineWidth: 6];
	[[NSColor orangeColor] set];
	[oval stroke];

	NSDictionary* attributes = @{
		NSFontAttributeName: [NSFont systemFontOfSize: 28],
		NSForegroundColorAttributeName: [NSColor blackColor],
	};
	[@"Hello from Darling" drawAtPoint: NSMakePoint(20, 150) withAttributes: attributes];
}

@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching: (NSNotification*)notification
{
	milestone("applicationDidFinishLaunching");

	const char* autoquit = getenv("DEVTEST_AUTOQUIT");
	if (autoquit != NULL && atof(autoquit) > 0) {
		[NSTimer scheduledTimerWithTimeInterval: atof(autoquit)
		                                 target: NSApp
		                               selector: @selector(terminate:)
		                               userInfo: nil
		                                repeats: NO];
	}
}

- (void)buttonClicked: (id)sender
{
	milestone("button clicked");
}

@end

int main(int argc, char** argv)
{
	@autoreleasepool {
		[NSApplication sharedApplication];
		[NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];

		AppDelegate* delegate = [AppDelegate new];
		[NSApp setDelegate: delegate];

		NSWindow* window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 560, 320)
		                                                styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
		                                                  backing: NSBackingStoreBuffered
		                                                    defer: NO];
		[window setTitle: @"AppKitBasic"];

		PaintView* paint = [[PaintView alloc] initWithFrame: NSMakeRect(0, 80, 560, 240)];
		[paint setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
		[[window contentView] addSubview: paint];

		NSButton* button = [[NSButton alloc] initWithFrame: NSMakeRect(20, 20, 140, 32)];
		[button setTitle: @"Click me"];
		[button setBezelStyle: NSRoundedBezelStyle];
		[button setTarget: delegate];
		[button setAction: @selector(buttonClicked:)];
		[[window contentView] addSubview: button];

		NSTextField* field = [[NSTextField alloc] initWithFrame: NSMakeRect(180, 24, 200, 24)];
		[field setStringValue: @"Editable text field"];
		[[window contentView] addSubview: field];

		NSSlider* slider = [[NSSlider alloc] initWithFrame: NSMakeRect(400, 24, 140, 24)];
		[slider setDoubleValue: 0.5];
		[[window contentView] addSubview: slider];

		[window center];
		[window makeKeyAndOrderFront: nil];
		milestone("window ordered front");

		[NSApp run];
	}
	return 0;
}
