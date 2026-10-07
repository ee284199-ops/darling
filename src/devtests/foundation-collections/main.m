// Checks Foundation collection and string behavior that apps lean on: NSIndexSet with many
// ranges (built index by index and walked with indexGreaterThanIndex: / getIndexes:), and
// one-byte strings in the common 8-bit encodings.

#import <Foundation/Foundation.h>

#include <dlfcn.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static int failures = 0;

static void expect(int condition, const char* what) {
	printf("%s: %s\n", condition ? "PASS" : "FAIL", what);
	if (!condition)
		failures++;
}

// the byte values Hex Fiend puts in one set (printable ASCII) and the other (the rest)
static BOOL isPrintable(NSUInteger value) {
	return value >= 0x20 && value < 0x7F;
}

static void checkIndexSets(void) {
	NSMutableIndexSet* printable = [NSMutableIndexSet indexSet];
	NSMutableIndexSet* others = [NSMutableIndexSet indexSet];
	NSUInteger value;

	for (value = 0; value < 256; value++)
		[isPrintable(value) ? printable : others addIndex: value];

	expect([printable count] == 95 && [others count] == 161, "counts of sets built index by index");
	expect([others rangeCount] == 2 && [printable rangeCount] == 1, "adjacent indexes merge into ranges");

	// walk both sets the way Hex Fiend pairs glyphs with characters
	BOOL inOrder = YES;
	NSUInteger seen = 0;
	for (value = [others firstIndex]; value != NSNotFound; value = [others indexGreaterThanIndex: value]) {
		if (isPrintable(value))
			inOrder = NO;
		seen++;
	}
	expect(inOrder && seen == 161, "indexGreaterThanIndex: walks a two-range set in order");

	NSUInteger buffer[300];
	NSUInteger got = [others getIndexes: buffer maxCount: 300 inIndexRange: NULL];
	BOOL same = got == 161;
	NSUInteger expected = 0, i;
	for (i = 0; same && i < got; i++) {
		while (isPrintable(expected))
			expected++;
		if (buffer[i] != expected)
			same = NO;
		expected++;
	}
	expect(same, "getIndexes:maxCount:inIndexRange: returns every index in order");

	// many ranges: every third index
	NSMutableIndexSet* sparse = [NSMutableIndexSet indexSet];
	for (value = 0; value < 3000; value += 3)
		[sparse addIndex: value];
	expect([sparse count] == 1000 && [sparse rangeCount] == 1000, "a set of 1000 single-index ranges");

	seen = 0;
	inOrder = YES;
	NSUInteger previous = 0;
	for (value = [sparse firstIndex]; value != NSNotFound; value = [sparse indexGreaterThanIndex: value]) {
		if (value % 3 != 0 || (seen > 0 && value != previous + 3))
			inOrder = NO;
		previous = value;
		seen++;
	}
	expect(inOrder && seen == 1000, "indexGreaterThanIndex: walks 1000 ranges");

	NSUInteger* all = malloc(sizeof(NSUInteger) * 1100);
	got = [sparse getIndexes: all maxCount: 1100 inIndexRange: NULL];
	same = got == 1000;
	for (i = 0; same && i < got; i++)
		if (all[i] != i * 3)
			same = NO;
	expect(same, "getIndexes:maxCount:inIndexRange: returns 1000 ranges' indexes");

	// a range limit and a short buffer
	NSRange range = NSMakeRange(10, 20);
	got = [sparse getIndexes: all maxCount: 3 inIndexRange: &range];
	printf("  limited: %lu indexes %lu %lu %lu, range left %lu+%lu\n", (unsigned long) got,
		(unsigned long) all[0], (unsigned long) all[1], (unsigned long) all[2],
		(unsigned long) range.location, (unsigned long) range.length);
	expect(got == 3 && all[0] == 12 && all[1] == 15 && all[2] == 18 && range.location == 19 && range.length == 11,
		"getIndexes:maxCount:inIndexRange: stops at maxCount and moves the range on");
	free(all);

	expect([sparse containsIndex: 2997] && ![sparse containsIndex: 2998], "containsIndex: in a many-range set");
	expect([sparse indexLessThanIndex: 100] == 99 && [sparse lastIndex] == 2997, "indexLessThanIndex: and lastIndex");

	// removing and shifting keep the ranges right
	NSMutableIndexSet* shifted = [[sparse mutableCopy] autorelease];
	[shifted removeIndexesInRange: NSMakeRange(0, 1500)];
	expect([shifted count] == 500 && [shifted firstIndex] == 1500, "removeIndexesInRange: on many ranges");
	[shifted shiftIndexesStartingAtIndex: 1500 by: -1500];
	expect([shifted firstIndex] == 0 && [shifted lastIndex] == 1497 && [shifted count] == 500,
		"shiftIndexesStartingAtIndex:by:");

	__block NSUInteger enumerated = 0;
	__block BOOL enumeratedInOrder = YES;
	__block NSUInteger last = 0;
	[sparse enumerateIndexesUsingBlock: ^(NSUInteger index, BOOL* stop) {
		if (enumerated > 0 && index != last + 3)
			enumeratedInOrder = NO;
		last = index;
		enumerated++;
	}];
	expect(enumerated == 1000 && enumeratedInOrder, "enumerateIndexesUsingBlock: over 1000 ranges");

	// keyed archives (a multi-range set goes into NSRangeData)
	NSData* archive = [NSKeyedArchiver archivedDataWithRootObject: others];
	NSIndexSet* decoded = [NSKeyedUnarchiver unarchiveObjectWithData: archive];
	expect([decoded isKindOfClass: [NSIndexSet class]] && [decoded isEqualToIndexSet: others],
		"a two-range NSIndexSet survives keyed archiving");
	decoded = [NSKeyedUnarchiver unarchiveObjectWithData: [NSKeyedArchiver archivedDataWithRootObject: sparse]];
	expect([decoded isEqualToIndexSet: sparse], "a 1000-range NSIndexSet survives keyed archiving");
	decoded = [NSKeyedUnarchiver unarchiveObjectWithData:
		[NSKeyedArchiver archivedDataWithRootObject: [NSIndexSet indexSetWithIndexesInRange: NSMakeRange(5, 10)]]];
	expect([decoded count] == 10 && [decoded firstIndex] == 5, "a one-range NSIndexSet survives keyed archiving");
}

static void checkEncodings(void) {
	struct {
		NSStringEncoding encoding;
		const char* name;
		uint8_t byte;
		unichar expected;
	} cases[] = {
		{ NSASCIIStringEncoding, "ASCII 't'", 't', 't' },
		{ NSASCIIStringEncoding, "ASCII '_'", '_', '_' },
		{ NSMacOSRomanStringEncoding, "Mac Roman 't'", 't', 't' },
		{ NSMacOSRomanStringEncoding, "Mac Roman 0xCF", 0xCF, 0x0153 },
		{ NSISOLatin1StringEncoding, "Latin 1 0xCF", 0xCF, 0x00CF },
		{ NSWindowsCP1252StringEncoding, "Windows 1252 0x80", 0x80, 0x20AC },
	};

	for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
		NSString* string = [[[NSString alloc] initWithBytes: &cases[i].byte length: 1
		                                            encoding: cases[i].encoding] autorelease];
		char what[128];
		unichar got = [string length] == 1 ? [string characterAtIndex: 0] : 0;

		printf("  %s -> U+%04X\n", cases[i].name, got);
		snprintf(what, sizeof(what), "%s decodes", cases[i].name);
		expect(got == cases[i].expected, what);
	}
}

// What @available compiles to (compiler-rt's __isPlatformVersionAtLeast, linked into apps)
// looks up and calls; Darling says it is macOS 11.7.4.
typedef struct {
	uint32_t platform;
	uint32_t version;
} BuildVersion;

static BOOL availableOnMac(uint32_t major, uint32_t minor) {
	static bool (*versionCheck)(uint32_t, BuildVersion*) = NULL;
	BuildVersion versions[2] = {
		{ 6, (major + 3) << 16 }, // a zippered library's Mac Catalyst entry, which doesn't apply
		{ 1, (major << 16) | (minor << 8) },
	};

	if (versionCheck == NULL)
		versionCheck = (bool (*)(uint32_t, BuildVersion*)) dlsym(RTLD_DEFAULT, "_availability_version_check");
	return versionCheck != NULL && versionCheck(2, versions);
}

static void checkAvailability(void) {
	BOOL atLeast11_5 = availableOnMac(11, 5);
	BOOL atLeast11_7 = availableOnMac(11, 7);
	BOOL atLeast11_8 = availableOnMac(11, 8);
	BOOL atLeast12 = availableOnMac(12, 0);

	NSOperatingSystemVersion version = [[NSProcessInfo processInfo] operatingSystemVersion];
	printf("  system %ld.%ld.%ld: 11.5 %d, 11.7 %d, 11.8 %d, 12.0 %d\n", (long) version.majorVersion,
		(long) version.minorVersion, (long) version.patchVersion, atLeast11_5, atLeast11_7, atLeast11_8, atLeast12);
	expect(atLeast11_5 && atLeast11_7, "@available is true for versions up to the system's");
	expect(!atLeast11_8 && !atLeast12, "@available is false for later versions");
}

static void checkDuration(NSDateComponentsFormatterUnitsStyle style, NSCalendarUnit units, NSTimeInterval interval,
	void (^configure)(NSDateComponentsFormatter* formatter), NSString* expected) {
	NSDateComponentsFormatter* formatter = [[[NSDateComponentsFormatter alloc] init] autorelease];
	char what[256];

	[formatter setUnitsStyle: style];
	[formatter setAllowedUnits: units];
	if (configure != nil)
		configure(formatter);
	NSString* got = [formatter stringFromTimeInterval: interval];
	snprintf(what, sizeof(what), "duration %.0f s -> \"%s\" (got \"%s\")", interval, [expected UTF8String],
		got != nil ? [got UTF8String] : "(nil)");
	expect([got isEqualToString: expected], what);
}

static void checkDateComponentsFormatter(void) {
	NSCalendarUnit hm = NSCalendarUnitHour | NSCalendarUnitMinute;
	NSCalendarUnit hms = hm | NSCalendarUnitSecond;

	checkDuration(NSDateComponentsFormatterUnitsStyleFull, hm, 3900, nil, @"1 hour, 5 minutes");
	checkDuration(NSDateComponentsFormatterUnitsStyleAbbreviated, hm, 3900, nil, @"1h 5m");
	checkDuration(NSDateComponentsFormatterUnitsStyleShort, hm, 3900, nil, @"1 hr, 5 min");
	checkDuration(NSDateComponentsFormatterUnitsStylePositional, hms, 3725, nil, @"1:02:05");
	checkDuration(NSDateComponentsFormatterUnitsStylePositional, NSCalendarUnitMinute | NSCalendarUnitSecond, 65, nil, @"1:05");
	checkDuration(NSDateComponentsFormatterUnitsStyleFull, hm, 7300, ^(NSDateComponentsFormatter* f) {
		[f setMaximumUnitCount: 1];
		[f setIncludesTimeRemainingPhrase: YES];
	}, @"2 hours remaining");
	checkDuration(NSDateComponentsFormatterUnitsStyleFull, NSCalendarUnitMinute | NSCalendarUnitSecond, 75,
		^(NSDateComponentsFormatter* f) { [f setCollapsesLargestUnit: YES]; }, @"75 seconds");
	checkDuration(NSDateComponentsFormatterUnitsStyleFull, NSCalendarUnitDay | hm, 90061, nil, @"1 day, 1 hour, 1 minute");
	checkDuration(NSDateComponentsFormatterUnitsStyleFull, hms, 0, nil, @"0 seconds");
}

int main(int argc, char** argv) {
	@autoreleasepool {
		checkIndexSets();
		checkEncodings();
		checkAvailability();
		checkDateComponentsFormatter();
		printf("%s (%d failures)\n", failures ? "FAILED" : "ALL PASSED", failures);
	}
	return failures ? 1 : 0;
}
