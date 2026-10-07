// Checks CoreGraphics drawing that apps rely on: the memory layout of bitmap contexts for each
// byte order (Quartz stores integer pixels big-endian by default), images moving between
// layouts, linear and radial gradients, tiled images and glyphs drawn at positions.

#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>

#include <math.h>
#include <stdio.h>
#include <string.h>

static int failures = 0;

static void expect(int condition, const char* what) {
	printf("%s: %s\n", condition ? "PASS" : "FAIL", what);
	if (!condition)
		failures++;
}

static int near(int value, int expected) {
	return abs(value - expected) <= 8;
}

enum { kSize = 64 };

static CGContextRef makeContext(uint8_t* pixels, CGBitmapInfo info) {
	CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
	CGContextRef context = CGBitmapContextCreate(pixels, kSize, kSize, 8, kSize * 4, rgb, info);

	CGColorSpaceRelease(rgb);
	return context;
}

static const uint8_t* pixelAt(const uint8_t* pixels, int x, int y) {
	// row 0 is the top of the bitmap
	return pixels + (kSize - 1 - y) * kSize * 4 + x * 4;
}

// Fills a context with opaque pure red and checks where the bytes land.
static void checkLayout(CGBitmapInfo info, const char* name, int r, int g, int b, int a) {
	uint8_t pixels[kSize * kSize * 4];
	char what[256];

	memset(pixels, 0x55, sizeof(pixels));
	CGContextRef context = makeContext(pixels, info);
	snprintf(what, sizeof(what), "%s: context created", name);
	expect(context != NULL, what);
	if (context == NULL)
		return;

	CGContextSetRGBFillColor(context, 1, 0, 0, 1);
	CGContextFillRect(context, CGRectMake(0, 0, kSize, kSize));
	const uint8_t* p = pixelAt(pixels, 10, 10);
	printf("  bytes: %d %d %d %d\n", p[0], p[1], p[2], p[3]);

	snprintf(what, sizeof(what), "%s: red is stored at byte %d", name, r);
	expect(p[r] == 255 && (g < 0 || p[g] == 0) && p[b] == 0 && (a < 0 || p[a] == 255), what);
	CGContextRelease(context);
}

// Draws a red-left/blue-right image made in one layout into a context with another layout.
static void checkImageConversion(CGBitmapInfo fromInfo, CGBitmapInfo toInfo, const char* name) {
	uint8_t source[kSize * kSize * 4];
	uint8_t target[kSize * kSize * 4];
	char what[256];

	CGContextRef context = makeContext(source, fromInfo);
	CGContextSetRGBFillColor(context, 1, 0, 0, 1);
	CGContextFillRect(context, CGRectMake(0, 0, kSize / 2, kSize));
	CGContextSetRGBFillColor(context, 0, 0, 1, 1);
	CGContextFillRect(context, CGRectMake(kSize / 2, 0, kSize / 2, kSize));
	CGImageRef image = CGBitmapContextCreateImage(context);
	CGContextRelease(context);

	memset(target, 0, sizeof(target));
	context = makeContext(target, toInfo);
	CGContextDrawImage(context, CGRectMake(0, 0, kSize, kSize), image);
	CGContextRelease(context);
	CGImageRelease(image);

	// read the target back through a context of the same layout that knows where red is
	CGContextRef check = makeContext(target, toInfo);
	CGImageRef copy = CGBitmapContextCreateImage(check);
	CGContextRelease(check);

	uint8_t rgba[kSize * kSize * 4];
	context = makeContext(rgba, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	CGContextDrawImage(context, CGRectMake(0, 0, kSize, kSize), copy);
	CGContextRelease(context);
	CGImageRelease(copy);

	const uint8_t* left = pixelAt(rgba, 5, 30);
	const uint8_t* right = pixelAt(rgba, kSize - 5, 30);
	printf("  left %d %d %d %d, right %d %d %d %d\n", left[0], left[1], left[2], left[3],
		right[0], right[1], right[2], right[3]);
	snprintf(what, sizeof(what), "%s: colors survive", name);
	expect(left[0] > 240 && left[2] < 15 && right[0] < 15 && right[2] > 240, what);
}

static void checkLinearGradient(void) {
	uint8_t pixels[kSize * kSize * 4];
	CGFloat components[] = { 1, 0, 0, 1, 0, 0, 1, 1 };
	CGFloat locations[] = { 0, 1 };
	CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
	CGGradientRef gradient = CGGradientCreateWithColorComponents(rgb, components, locations, 2);

	expect(gradient != NULL, "CGGradientCreateWithColorComponents makes a gradient");
	memset(pixels, 0, sizeof(pixels));
	CGContextRef context = makeContext(pixels, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	CGContextDrawLinearGradient(context, gradient, CGPointMake(8, 0), CGPointMake(kSize - 8, 0),
		kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
	CGContextRelease(context);

	const uint8_t* start = pixelAt(pixels, 2, 20);
	const uint8_t* middle = pixelAt(pixels, kSize / 2, 20);
	const uint8_t* end = pixelAt(pixels, kSize - 2, 20);
	printf("  start %d %d %d %d, middle %d %d %d %d, end %d %d %d %d\n", start[0], start[1], start[2], start[3],
		middle[0], middle[1], middle[2], middle[3], end[0], end[1], end[2], end[3]);
	expect(start[0] > 240 && start[2] < 15 && start[3] == 255, "linear gradient: red before the start");
	expect(end[2] > 240 && end[0] < 15 && end[3] == 255, "linear gradient: blue after the end");
	expect(near(middle[0], 128) && near(middle[2], 128), "linear gradient: half way in the middle");

	// without the extend options nothing is drawn outside the axis
	memset(pixels, 0, sizeof(pixels));
	context = makeContext(pixels, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	CGContextDrawLinearGradient(context, gradient, CGPointMake(8, 0), CGPointMake(kSize - 8, 0), 0);
	CGContextRelease(context);
	expect(pixelAt(pixels, 2, 20)[3] == 0 && pixelAt(pixels, kSize / 2, 20)[3] == 255,
		"linear gradient: nothing outside the axis without the extend options");

	// colors made from gray CGColors
	CGColorRef black = CGColorCreateGenericGray(0, 1);
	CGColorRef white = CGColorCreateGenericGray(1, 1);
	CFTypeRef colorValues[] = { black, white };
	CFArrayRef colors = CFArrayCreate(NULL, colorValues, 2, &kCFTypeArrayCallBacks);
	CGGradientRef grayGradient = CGGradientCreateWithColors(rgb, colors, NULL);
	expect(grayGradient != NULL, "CGGradientCreateWithColors with gray colors makes a gradient");
	memset(pixels, 0, sizeof(pixels));
	context = makeContext(pixels, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	CGContextDrawLinearGradient(context, grayGradient, CGPointMake(0, 0), CGPointMake(0, kSize), 0);
	CGContextRelease(context);
	const uint8_t* bottom = pixelAt(pixels, 30, 1);
	const uint8_t* top = pixelAt(pixels, 30, kSize - 2);
	printf("  bottom %d %d %d, top %d %d %d\n", bottom[0], bottom[1], bottom[2], top[0], top[1], top[2]);
	expect(bottom[0] < 15 && top[0] > 240 && top[1] > 240 && top[2] > 240, "vertical gray gradient: black to white");
	CFRelease(colors);
	CGColorRelease(black);
	CGColorRelease(white);
	CGGradientRelease(grayGradient);

	CGGradientRelease(gradient);
	CGColorSpaceRelease(rgb);
}

static void checkRadialGradient(void) {
	uint8_t pixels[kSize * kSize * 4];
	CGFloat components[] = { 1, 1, 1, 1, 0, 0, 0, 1 };
	CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
	CGGradientRef gradient = CGGradientCreateWithColorComponents(rgb, components, NULL, 2);

	memset(pixels, 0, sizeof(pixels));
	CGContextRef context = makeContext(pixels, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	CGPoint center = CGPointMake(kSize / 2, kSize / 2);
	CGContextDrawRadialGradient(context, gradient, center, 0, center, kSize / 2 - 4, 0);
	CGContextRelease(context);

	const uint8_t* middle = pixelAt(pixels, kSize / 2, kSize / 2);
	const uint8_t* halfway = pixelAt(pixels, kSize / 2 + 14, kSize / 2);
	const uint8_t* corner = pixelAt(pixels, 1, 1);
	printf("  center %d, halfway %d, corner alpha %d\n", middle[0], halfway[0], corner[3]);
	expect(middle[0] > 230, "radial gradient: white in the center");
	expect(halfway[0] > 60 && halfway[0] < 200, "radial gradient: gray half way out");
	expect(corner[3] == 0, "radial gradient: nothing outside the end circle");

	CGGradientRelease(gradient);
	CGColorSpaceRelease(rgb);
}

static void checkTiledImage(void) {
	uint8_t tile[kSize * kSize * 4];
	uint8_t pixels[kSize * kSize * 4];

	// a 64x64 bitmap whose bottom-left 8x8 square is red, the rest green
	CGContextRef context = makeContext(tile, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	CGContextSetRGBFillColor(context, 0, 1, 0, 1);
	CGContextFillRect(context, CGRectMake(0, 0, kSize, kSize));
	CGContextSetRGBFillColor(context, 1, 0, 0, 1);
	CGContextFillRect(context, CGRectMake(0, 0, 8, 8));
	CGImageRef image = CGBitmapContextCreateImage(context);
	CGContextRelease(context);

	memset(pixels, 0, sizeof(pixels));
	context = makeContext(pixels, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	// tiles of 16x16, so the red corner shows up every 16 pixels at 2x2 size
	CGContextDrawTiledImage(context, CGRectMake(0, 0, 16, 16), image);
	CGContextRelease(context);
	CGImageRelease(image);

	int redTiles = 0;
	for (int y = 0; y < kSize; y += 16) {
		for (int x = 0; x < kSize; x += 16) {
			const uint8_t* p = pixelAt(pixels, x, y);
			if (p[0] > 200 && p[1] < 50)
				redTiles++;
		}
	}
	const uint8_t* between = pixelAt(pixels, 8, 8);
	printf("  red tile corners: %d, between: %d %d %d\n", redTiles, between[0], between[1], between[2]);
	expect(redTiles == 16 && between[1] > 200, "CGContextDrawTiledImage covers the context with tiles");
}

static int inkBetween(const uint8_t* pixels, int x0, int x1) {
	int ink = 0;
	for (int y = 0; y < kSize; y++)
		for (int x = x0; x < x1; x++)
			if (pixelAt(pixels, x, y)[0] > 64)
				ink++;
	return ink;
}

static void checkGlyphPositions(void) {
	uint8_t pixels[kSize * kSize * 4];
	CTFontRef font = CTFontCreateWithName(CFSTR("Helvetica"), 16, NULL);
	UniChar characters[2] = { 'H', 'H' };
	CGGlyph glyphs[2];
	CGPoint positions[2] = { { 2, 0 }, { 40, 0 } };

	CTFontGetGlyphsForCharacters(font, characters, glyphs, 2);
	CGFontRef cgFont = CTFontCopyGraphicsFont(font, NULL);

	memset(pixels, 0, sizeof(pixels));
	CGContextRef context = makeContext(pixels, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	CGContextSetRGBFillColor(context, 1, 1, 1, 1);
	CGContextSetFont(context, cgFont);
	CGContextSetFontSize(context, 16);
	CGContextSetTextMatrix(context, CGAffineTransformIdentity);
	// the text position moves every position
	CGContextSetTextPosition(context, 0, 20);
	CGContextShowGlyphsAtPositions(context, glyphs, positions, 2);
	CGContextRelease(context);

	int first = inkBetween(pixels, 0, 16);
	int gap = inkBetween(pixels, 18, 38);
	int second = inkBetween(pixels, 38, 56);
	printf("  ink: first %d, gap %d, second %d\n", first, gap, second);
	expect(first > 10 && second > 10 && gap == 0, "CGContextShowGlyphsAtPositions puts glyphs at their positions");

	// advances place the following glyphs (Hex Fiend spaces its byte columns this way)
	CGSize advances[2] = { { 38, 0 }, { 10, 0 } };
	memset(pixels, 0, sizeof(pixels));
	context = makeContext(pixels, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	CGContextSetRGBFillColor(context, 1, 1, 1, 1);
	CGContextSetFont(context, cgFont);
	CGContextSetFontSize(context, 16);
	CGContextSetTextMatrix(context, CGAffineTransformIdentity);
	CGContextSetTextPosition(context, 2, 20);
	CGContextShowGlyphsWithAdvances(context, glyphs, advances, 2);
	CGPoint after = CGContextGetTextPosition(context);
	CGContextRelease(context);

	first = inkBetween(pixels, 0, 16);
	gap = inkBetween(pixels, 18, 38);
	second = inkBetween(pixels, 38, 56);
	printf("  ink: first %d, gap %d, second %d; text position after: %.1f, %.1f\n", first, gap, second,
		after.x, after.y);
	expect(first > 10 && second > 10 && gap == 0, "CGContextShowGlyphsWithAdvances uses the advances");
	expect(fabs(after.x - 50) < 0.01 && fabs(after.y - 20) < 0.01,
		"CGContextShowGlyphsWithAdvances leaves the text position after the last advance");

	// without advances the text position moves by the glyphs' own widths
	context = makeContext(pixels, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	CGContextSetFont(context, cgFont);
	CGContextSetFontSize(context, 16);
	CGContextSetTextMatrix(context, CGAffineTransformIdentity);
	CGContextSetTextPosition(context, 0, 20);
	CGContextShowGlyphs(context, glyphs, 2);
	after = CGContextGetTextPosition(context);
	CGContextRelease(context);
	printf("  text position after two H: %.1f\n", after.x);
	expect(after.x > 10 && after.x < 40, "CGContextShowGlyphs moves the text position by the glyph widths");

	CGFontRelease(cgFont);
	CFRelease(font);
}

static void checkBitmapImageRep(void) {
	NSBitmapImageRep* rep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL
	                                                                 pixelsWide: kSize
	                                                                 pixelsHigh: kSize
	                                                              bitsPerSample: 8
	                                                            samplesPerPixel: 4
	                                                                   hasAlpha: YES
	                                                                   isPlanar: NO
	                                                             colorSpaceName: NSDeviceRGBColorSpace
	                                                                bytesPerRow: kSize * 4
	                                                               bitsPerPixel: 32] autorelease];
	NSGraphicsContext* context = [NSGraphicsContext graphicsContextWithBitmapImageRep: rep];

	[NSGraphicsContext saveGraphicsState];
	[NSGraphicsContext setCurrentContext: context];
	[[NSColor colorWithDeviceRed: 1 green: 0 blue: 0 alpha: 1] set];
	NSRectFill(NSMakeRect(0, 0, kSize, kSize));
	[context flushGraphics];
	[NSGraphicsContext restoreGraphicsState];

	const uint8_t* data = [rep bitmapData];
	printf("  first pixel bytes: %d %d %d %d\n", data[0], data[1], data[2], data[3]);
	expect(data[0] == 255 && data[1] == 0 && data[2] == 0 && data[3] == 255,
		"NSBitmapImageRep drawn red holds R,G,B,A bytes");

	NSColor* color = [rep colorAtX: 3 y: 3];
	printf("  colorAtX:y: %s\n", [[color description] UTF8String]);
	expect(color != nil && [color redComponent] > 0.95 && [color blueComponent] < 0.05,
		"NSBitmapImageRep colorAtX:y: reads red");

	NSImage* image = [[[NSImage alloc] initWithSize: NSMakeSize(kSize, kSize)] autorelease];
	[image addRepresentation: rep];
	CGImageRef cgImage = [image CGImageForProposedRect: NULL context: nil hints: nil];
	expect(cgImage != NULL && CGImageGetWidth(cgImage) == kSize, "NSImage CGImageForProposedRect: gives a CGImage");
}

int main(int argc, char** argv) {
	@autoreleasepool {
		checkLayout(kCGImageAlphaPremultipliedLast, "PremultipliedLast", 0, 1, 2, 3);
		checkLayout(kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big, "PremultipliedLast|32Big", 0, 1, 2, 3);
		checkLayout(kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Little, "PremultipliedLast|32Little", 3, 2, 1, 0);
		checkLayout(kCGImageAlphaPremultipliedFirst, "PremultipliedFirst", 1, 2, 3, 0);
		checkLayout(kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little, "PremultipliedFirst|32Little", 2, 1, 0, 3);
		checkLayout(kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little, "NoneSkipFirst|32Little", 2, 1, 0, -1);
		checkLayout(kCGImageAlphaNoneSkipLast, "NoneSkipLast", 0, 1, 2, -1);

		checkImageConversion(kCGImageAlphaPremultipliedLast, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little,
			"RGBA image into a BGRA context");
		checkImageConversion(kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little, kCGImageAlphaPremultipliedLast,
			"BGRA image into an RGBA context");
		checkImageConversion(kCGImageAlphaPremultipliedFirst, kCGImageAlphaNoneSkipLast,
			"ARGB image into an RGBX context");

		checkLinearGradient();
		checkRadialGradient();
		checkTiledImage();
		checkGlyphPositions();
		checkBitmapImageRep();

		printf("%s (%d failures)\n", failures ? "FAILED" : "ALL PASSED", failures);
	}
	return failures ? 1 : 0;
}
