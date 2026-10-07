// Checks the text paths of apps that pass NSFonts to CoreText and draw glyphs themselves, the way
// Hex Fiend's hex view does: glyphs from CTFontGetGlyphsForCharacters, widths from NSFont, then
// CGContextShowGlyphsWithAdvances after -[NSFont set], or CTFontDrawGlyphs.

#import <AppKit/AppKit.h>
#import <CoreText/CoreText.h>

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures = 0;

static void expect(int condition, const char* what) {
	printf("%s: %s\n", condition ? "PASS" : "FAIL", what);
	if (!condition)
		failures++;
}

enum { kWidth = 200, kHeight = 40 };

static const UniChar hexChars[] = { '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
	'A', 'B', 'C', 'D', 'E', 'F', ' ' };
enum { kHexCount = sizeof(hexChars) / sizeof(hexChars[0]) };

static NSBitmapImageRep* makeBitmap(void) {
	return [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL
	                                                pixelsWide: kWidth
	                                                pixelsHigh: kHeight
	                                             bitsPerSample: 8
	                                           samplesPerPixel: 4
	                                                  hasAlpha: YES
	                                                  isPlanar: NO
	                                            colorSpaceName: NSDeviceRGBColorSpace
	                                               bytesPerRow: kWidth * 4
	                                              bitsPerPixel: 32] autorelease];
}

// pixels clearly darker than the white background (thin fonts antialias to gray)
static int countInk(NSBitmapImageRep* rep) {
	const unsigned char* data = [rep bitmapData];
	int count = 0;

	for (int i = 0; i < kWidth * kHeight; i++) {
		if (data[i * 4] < 200)
			count++;
	}
	return count;
}

// Runs the drawing block with a white bitmap as the current context and returns the inked pixels.
static int drawAndCount(void (^draw)(CGContextRef context)) {
	NSBitmapImageRep* rep = makeBitmap();
	NSGraphicsContext* context = [NSGraphicsContext graphicsContextWithBitmapImageRep: rep];

	[NSGraphicsContext saveGraphicsState];
	[NSGraphicsContext setCurrentContext: context];
	CGContextRef cg = [context graphicsPort];
	CGContextSetRGBFillColor(cg, 1, 1, 1, 1);
	CGContextFillRect(cg, CGRectMake(0, 0, kWidth, kHeight));
	CGContextSetRGBFillColor(cg, 0, 0, 0, 1);
	draw(cg);
	[context flushGraphics];
	// APPKIT_TEXT_DUMP=<directory> saves every drawing as a PPM image
	const char* dumpDirectory = getenv("APPKIT_TEXT_DUMP");
	if (dumpDirectory != NULL) {
		static int dumpCount = 0;
		char path[1024];
		snprintf(path, sizeof(path), "%s/appkit-text-%02d.ppm", dumpDirectory, dumpCount++);
		FILE* file = fopen(path, "wb");
		if (file != NULL) {
			const unsigned char* data = [rep bitmapData];
			fprintf(file, "P6\n%d %d\n255\n", kWidth, kHeight);
			for (int i = 0; i < kWidth * kHeight; i++)
				fwrite(data + i * 4, 1, 3, file);
			fclose(file);
		}
	}
	[NSGraphicsContext restoreGraphicsState];
	return countInk(rep);
}

static void checkFont(NSFont* font, const char* label) {
	char what[256];
	CGGlyph glyphStorage[kHexCount];
	CGSize advanceStorage[kHexCount];
	CGPoint positionStorage[kHexCount];
	// blocks can't capture arrays
	CGGlyph* glyphs = glyphStorage;
	CGSize* advances = advanceStorage;
	CGPoint* positions = positionStorage;

	snprintf(what, sizeof(what), "%s exists", label);
	expect(font != nil, what);
	if (font == nil)
		return;
	NSString* family = [(NSString*) CTFontCopyFamilyName((CTFontRef) font) autorelease];
	printf("  %s -> %s (%s) %.1fpt, fixed pitch %d, CoreText traits 0x%x\n", label, [[font fontName] UTF8String],
		[family UTF8String], [font pointSize], [font isFixedPitch], (unsigned) CTFontGetSymbolicTraits((CTFontRef) font));

	memset(glyphStorage, 0, sizeof(glyphStorage));
	bool found = CTFontGetGlyphsForCharacters((CTFontRef) font, hexChars, glyphs, kHexCount);
	snprintf(what, sizeof(what), "%s: CTFontGetGlyphsForCharacters finds the hex digits", label);
	expect(found && glyphs[0] != 0 && glyphs[15] != 0, what);

	CGFloat nsAdvance = [font advancementForGlyph: glyphs[0]].width;
	double total = CTFontGetAdvancesForGlyphs((CTFontRef) font, kCTFontOrientationHorizontal, glyphs, advances, kHexCount);
	printf("  advancementForGlyph: %.2f, CTFontGetAdvancesForGlyphs: %.2f (total %.2f)\n", nsAdvance, advances[0].width, total);
	snprintf(what, sizeof(what), "%s: glyph advances are positive", label);
	expect(nsAdvance > 0 && advances[0].width > 0 && total > 0, what);

	for (int i = 0; i < kHexCount; i++) {
		advances[i] = CGSizeMake(nsAdvance > 0 ? nsAdvance : 6, 0);
		positions[i] = CGPointMake(4 + i * (nsAdvance > 0 ? nsAdvance : 6), 12);
	}

	int ink = drawAndCount(^(CGContextRef cg) {
		[font set];
		CGContextSetTextDrawingMode(cg, kCGTextFill);
		CGContextSetTextPosition(cg, 4, 12);
		CGContextShowGlyphsWithAdvances(cg, glyphs, advances, kHexCount);
	});
	printf("  CGContextShowGlyphsWithAdvances inked %d pixels\n", ink);
	snprintf(what, sizeof(what), "%s: -[NSFont set] + CGContextShowGlyphsWithAdvances draws", label);
	expect(ink > 50, what);

	ink = drawAndCount(^(CGContextRef cg) {
		[font set];
		CGContextSetTextPosition(cg, 0, 0);
		CGContextShowGlyphsAtPositions(cg, glyphs, positions, kHexCount);
	});
	printf("  CGContextShowGlyphsAtPositions inked %d pixels\n", ink);
	snprintf(what, sizeof(what), "%s: CGContextShowGlyphsAtPositions draws", label);
	expect(ink > 50, what);

	ink = drawAndCount(^(CGContextRef cg) {
		CGContextSetTextMatrix(cg, CGAffineTransformIdentity);
		CTFontDrawGlyphs((CTFontRef) font, glyphs, positions, kHexCount, cg);
	});
	printf("  CTFontDrawGlyphs inked %d pixels\n", ink);
	snprintf(what, sizeof(what), "%s: CTFontDrawGlyphs with an NSFont draws", label);
	expect(ink > 50, what);

	ink = drawAndCount(^(CGContextRef cg) {
		NSDictionary* attributes = @{ NSFontAttributeName: font, NSForegroundColorAttributeName: [NSColor blackColor] };
		[@"0123456789ABCDEF" drawAtPoint: NSMakePoint(4, 8) withAttributes: attributes];
	});
	printf("  -[NSString drawAtPoint:withAttributes:] inked %d pixels\n", ink);
	snprintf(what, sizeof(what), "%s: NSString drawing draws", label);
	expect(ink > 50, what);
}

// What Hex Fiend's text column does for characters its font lacks: ask CoreText for a font that
// has them and treat that font as an NSFont (on macOS a CTFont is one).
static void checkSubstitution(NSFont* font) {
	UniChar zero = '0';
	CGGlyph zeroGlyph = 0;
	CTFontGetGlyphsForCharacters((CTFontRef) font, &zero, &zeroGlyph, 1);
	CGFloat zeroWidth = [font advancementForGlyph: zeroGlyph].width;
	NSSize maximum = [font maximumAdvancement];
	NSRect box = [font boundingRectForFont];

	printf("  %s: advance of 0 %.2f, maximumAdvancement %.2f, boundingRectForFont %.1f x %.1f\n",
		[[font fontName] UTF8String], zeroWidth, maximum.width, box.size.width, box.size.height);
	expect(maximum.width >= zeroWidth && maximum.width < 4 * zeroWidth,
		"maximumAdvancement is about a character's width");

	// a character the font may lack, and one every font has
	NSString* strings[] = { @"Ï", @"一", @"A" };
	for (int i = 0; i < 3; i++) {
		CTFontRef substitute = CTFontCreateForString((CTFontRef) font, (CFStringRef) strings[i], CFRangeMake(0, 1));
		char what[256];
		UniChar character = [strings[i] characterAtIndex: 0];
		CGGlyph glyph = 0;

		snprintf(what, sizeof(what), "CTFontCreateForString finds a font for U+%04X", character);
		expect(substitute != NULL, what);
		if (substitute == NULL)
			continue;

		NSString* name = [(NSString*) CTFontCopyPostScriptName(substitute) autorelease];
		CTFontGetGlyphsForCharacters(substitute, &character, &glyph, 1);
		CGSize advance = CGSizeZero;
		CTFontGetAdvancesForGlyphs(substitute, kCTFontOrientationHorizontal, &glyph, &advance, 1);

		// the NSFont side of the same font, as apps use it
		NSFont* asNSFont = [(id) substitute screenFont];
		NSSize nsAdvance = NSZeroSize;
		NSGlyph nsGlyph = glyph;
		[asNSFont getAdvancements: &nsAdvance forGlyphs: &nsGlyph count: 1];
		printf("  U+%04X -> %s %.1fpt glyph %u advance %.2f; as NSFont %s %.1fpt advance %.2f\n", character,
			[name UTF8String], CTFontGetSize(substitute), glyph, advance.width,
			[[asNSFont fontName] UTF8String], [asNSFont pointSize], nsAdvance.width);

		snprintf(what, sizeof(what), "U+%04X: the substitute font has the glyph at the same size", character);
		expect(glyph != 0 && fabs(CTFontGetSize(substitute) - [font pointSize]) < 0.01, what);
		snprintf(what, sizeof(what), "U+%04X: as an NSFont it measures the glyph the same", character);
		expect(asNSFont != nil && fabs(nsAdvance.width - advance.width) < 0.01, what);

		NSString* family = [(NSString*) CTFontCopyFamilyName(substitute) autorelease];
		NSString* nsFamily = [(NSString*) CTFontCopyFamilyName((CTFontRef) asNSFont) autorelease];
		printf("    families: %s / %s\n", [family UTF8String], [nsFamily UTF8String]);
		snprintf(what, sizeof(what), "U+%04X: as an NSFont it is the same face", character);
		expect(family != nil && [family isEqualToString: nsFamily], what);
		CFRelease(substitute);
	}
}

int main(int argc, char** argv) {
	@autoreleasepool {
		[NSApplication sharedApplication];

		checkFont([NSFont fontWithName: @"Monaco" size: 10], "Monaco 10");
		checkFont([NSFont userFixedPitchFontOfSize: 0], "userFixedPitchFont");
		checkFont([NSFont monospacedDigitSystemFontOfSize: 12 weight: NSFontWeightRegular], "monospacedDigitSystemFont");
		checkFont([NSFont systemFontOfSize: 12], "systemFont");

		// macOS's monospaced fonts stand in for the system's monospaced font
		expect([[NSFont fontWithName: @"Monaco" size: 10] isFixedPitch], "Monaco is fixed pitch");
		expect([[NSFont fontWithName: @"Menlo-Regular" size: 12] isFixedPitch], "Menlo-Regular is fixed pitch");
		expect([[NSFont userFixedPitchFontOfSize: 0] isFixedPitch], "the user's fixed pitch font is fixed pitch");
		expect([[NSFont monospacedSystemFontOfSize: 12 weight: NSFontWeightRegular] isFixedPitch],
			"the monospaced system font is fixed pitch");

		checkSubstitution([NSFont fontWithName: @"Monaco" size: 10]);

		printf("%s (%d failures)\n", failures ? "FAILED" : "ALL PASSED", failures);
	}
	return failures ? 1 : 0;
}
