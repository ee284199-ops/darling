// Linked into every devtests app: prints an uncaught exception together with
// its call stack before the app terminates, so a crash can be located without
// a debugger.

#import <Foundation/Foundation.h>
#include <stdio.h>

static void printStack(NSArray<NSString*>* frames)
{
	for (NSString* frame in frames) {
		fprintf(stderr, "    %s\n", [frame UTF8String]);
	}
}

static void logUncaughtException(NSException* exception)
{
	fprintf(stderr, "*** uncaught %s: %s\n", [[exception name] UTF8String], [[exception reason] UTF8String]);

	NSArray<NSString*>* frames = [exception callStackSymbols];
	if ([frames count] > 0) {
		fprintf(stderr, "  thrown at:\n");
		printStack(frames);
	} else {
		fprintf(stderr, "  (exception carries no call stack; stack of the handler instead:)\n");
		printStack([NSThread callStackSymbols]);
	}
	fflush(stderr);
}

__attribute__((constructor))
static void installUncaughtExceptionLogger(void)
{
	NSSetUncaughtExceptionHandler(logUncaughtException);
}
