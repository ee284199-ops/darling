// CoreTextFonts: exercises CoreText's font layer (descriptors, collections, font manager,
// metrics, glyphs, paths, tables and drawing) against the fonts fontconfig knows about.
// Prints PASS/FAIL lines and exits non-zero on failure.  Needs no window.

#import <CoreText/CoreText.h>
#import <CoreGraphics/CGBitmapContext.h>
#import <CoreGraphics/CGColorSpace.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#include <math.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>

static int failures = 0;

static void expect(int condition, const char* what) {
    if (condition) {
        printf("PASS: %s\n", what);
    } else {
        printf("FAIL: %s\n", what);
        ++failures;
    }
}

static void printString(CFStringRef string) {
    char buffer[512];
    if (string != NULL && CFStringGetCString(string, buffer, sizeof(buffer), kCFStringEncodingUTF8))
        printf("      %s\n", buffer);
}

static CFDictionaryRef makeFamilyAttributes(CFStringRef family) {
    const void* keys[] = { kCTFontFamilyNameAttribute };
    const void* values[] = { family };
    return CFDictionaryCreate(NULL, keys, values, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
}

static void printDescriptor(CFStringRef label, CTFontDescriptorRef descriptor) {
    CFStringRef family = (CFStringRef) CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute);
    CFStringRef style = (CFStringRef) CTFontDescriptorCopyAttribute(descriptor, kCTFontStyleNameAttribute);
    CFURLRef url = (CFURLRef) CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute);

    printf("      %s:\n", label);
    if (family != NULL) {
        printf("        family: ");
        printString(family);
    }
    if (style != NULL) {
        printf("        style:  ");
        printString(style);
    }
    if (url != NULL) {
        CFStringRef urlString = CFURLGetString(url);
        printf("        url:    ");
        printString(urlString);
    }

    if (family != NULL) CFRelease(family);
    if (style != NULL) CFRelease(style);
    if (url != NULL) CFRelease(url);
}

// CoreText's table list holds the tags themselves (Skia reads them that way), not CFNumbers.
static int listsHeadTable(CTFontRef font) {
    CFArrayRef tables = CTFontCopyAvailableTables(font, kCTFontTableOptionNoOptions);
    CFIndex i;
    int found = 0;

    for (i = 0; tables != NULL && i < CFArrayGetCount(tables); i++) {
        if ((uintptr_t) CFArrayGetValueAtIndex(tables, i) == kCTFontTableHead)
            found = 1;
    }
    printf("      %ld tables\n", tables != NULL ? (long) CFArrayGetCount(tables) : -1L);
    if (tables != NULL)
        CFRelease(tables);
    return found;
}

// Counts pixels with any color in an RGBA/ARGB buffer: the glyphs are drawn white on opaque black,
// so the alpha channel alone says nothing.
static size_t countLitPixels(const uint8_t* pixels, size_t width, size_t height, size_t bytesPerRow, int alphaFirst) {
    size_t x, y, lit = 0;
    for (y = 0; y < height; y++) {
        for (x = 0; x < width; x++) {
            const uint8_t* p = pixels + y * bytesPerRow + x * 4;
            const uint8_t* rgb = alphaFirst ? p + 1 : p;
            if (rgb[0] > 32 || rgb[1] > 32 || rgb[2] > 32)
                lit++;
        }
    }
    return lit;
}

static int checkDrawing(CTFontRef font) {
    size_t width = 64;
    size_t height = 32;
    size_t bytesPerRow = width * 4;
    uint8_t pixels[64 * 32 * 4];
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGContextRef context;
    CGGlyph glyphs[2];
    CGPoint positions[2];
    UniChar characters[2] = { 'H', 'i' };
    size_t lit;

    memset(pixels, 0, sizeof(pixels));

    context = CGBitmapContextCreate(pixels, width, height, 8, bytesPerRow, rgb, kCGImageAlphaPremultipliedLast);
    if (context == NULL) {
        CFRelease(rgb);
        return 0;
    }

    CGContextSetRGBFillColor(context, 0, 0, 0, 1);
    CGContextFillRect(context, CGRectMake(0, 0, width, height));

    if (!CTFontGetGlyphsForCharacters(font, characters, glyphs, 2)) {
        CGContextRelease(context);
        CFRelease(rgb);
        return 0;
    }

    positions[0] = CGPointMake(2, 8);
    positions[1] = CGPointMake(18, 8);

    CGContextSetRGBFillColor(context, 1, 1, 1, 1);
    CTFontDrawGlyphs(font, glyphs, positions, 2, context);

    lit = countLitPixels(pixels, width, height, bytesPerRow, 0);
    printf("      %zu lit pixels\n", lit);

    CGContextRelease(context);
    CFRelease(rgb);
    return lit > 10;
}

// Skia (Neovide) draws glyphs into RGB contexts without alpha: NoneSkipFirst, host byte order.
static int checkSkipFirstDrawing(CTFontRef font) {
    const size_t size = 32;
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, size, size, 8, size * 4, rgb,
        kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Host);
    UniChar character = 'H';
    CGGlyph glyph;
    CGPoint origin = CGPointMake(8, 8);
    size_t lit = 0;

    CFRelease(rgb);
    if (context == NULL || !CTFontGetGlyphsForCharacters(font, &character, &glyph, 1)) {
        if (context != NULL)
            CGContextRelease(context);
        return 0;
    }

    CGContextSetRGBFillColor(context, 0, 0, 0, 1);
    CGContextFillRect(context, CGRectMake(0, 0, size, size));
    CGContextSetRGBFillColor(context, 1, 1, 1, 1);
    CTFontDrawGlyphs(font, &glyph, &origin, 1, context);

    // host byte order on x86: B, G, R, unused
    lit = countLitPixels((const uint8_t*) CGBitmapContextGetData(context), size, size, size * 4, 0);
    printf("      %zu lit pixels\n", lit);
    CGContextRelease(context);
    return lit > 10;
}

// The way Alacritty's font rasterizer (crossfont) draws a glyph: a bitmap context sized to the
// glyph's bounding rect with its own backing store, ARGB in host byte order, opaque black, the
// glyph drawn in white with its origin moved so the whole bounding rect is inside.
static int checkGlyphRasterization(CTFontRef font, UniChar character) {
    CGGlyph glyph;
    CGRect bounds;
    int left, descent, ascent;
    size_t width, height, lit;
    CGColorSpaceRef rgb;
    CGContextRef context;
    const uint8_t* pixels;
    CGPoint origin;

    if (!CTFontGetGlyphsForCharacters(font, &character, &glyph, 1))
        return 0;

    bounds = CTFontGetBoundingRectsForGlyphs(font, kCTFontOrientationDefault, &glyph, NULL, 1);
    left = (int) floor(bounds.origin.x);
    width = (size_t) ceil(bounds.origin.x - left + bounds.size.width);
    descent = (int) ceil(-bounds.origin.y);
    ascent = (int) ceil(bounds.size.height + bounds.origin.y);
    height = (size_t) (descent + ascent);

    printf("      '%c': bounds {%.2f, %.2f, %.2f, %.2f}, bitmap %zux%zu\n", (char) character,
        bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height, width, height);
    if (width == 0 || height == 0)
        return 0;

    rgb = CGColorSpaceCreateDeviceRGB();
    context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, rgb,
        kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
    CFRelease(rgb);
    if (context == NULL)
        return 0;

    CGContextSetRGBFillColor(context, 0, 0, 0, 1);
    CGContextFillRect(context, CGRectMake(0, 0, width, height));
    CGContextSetAllowsFontSmoothing(context, true);
    CGContextSetShouldSmoothFonts(context, false);
    CGContextSetAllowsFontSubpixelQuantization(context, true);
    CGContextSetShouldSubpixelQuantizeFonts(context, true);
    CGContextSetAllowsFontSubpixelPositioning(context, true);
    CGContextSetShouldSubpixelPositionFonts(context, true);
    CGContextSetAllowsAntialiasing(context, true);
    CGContextSetShouldAntialias(context, true);

    CGContextSetRGBFillColor(context, 1, 1, 1, 1);
    origin = CGPointMake(-left, descent);
    CTFontDrawGlyphs(font, &glyph, &origin, 1, context);

    pixels = (const uint8_t*) CGBitmapContextGetData(context);
    // host byte order on x86 means the bytes are BGRA: color first
    lit = pixels != NULL ? countLitPixels(pixels, width, height, width * 4, 0) : 0;
    printf("      %zu of %zu pixels lit\n", lit, width * height);
    for (size_t y = 0; pixels != NULL && y < height; y++) {
        printf("      ");
        for (size_t x = 0; x < width; x++) {
            const uint8_t* p = pixels + y * width * 4 + x * 4;
            int value = p[0] > p[1] ? (p[0] > p[2] ? p[0] : p[2]) : (p[1] > p[2] ? p[1] : p[2]);
            putchar(value > 192 ? '#' : value > 64 ? '+' : value > 16 ? '.' : ' ');
        }
        printf("|\n");
    }

    CGContextRelease(context);
    return lit > 0;
}

int main(int argc, char** argv) {
    @autoreleasepool {
        CFArrayRef families;
        CTFontCollectionRef collection;
        CFArrayRef descriptors;
        CTFontDescriptorRef monospaceDescriptor;
        CTFontDescriptorRef monospaceMatch;
        CTFontDescriptorRef firstFamilyMatch = NULL;
        CTFontDescriptorRef query;
        CTFontRef font = NULL;
        UniChar hello[5] = { 'H', 'e', 'l', 'l', 'o' };
        CGGlyph helloGlyphs[5];
        CGSize helloAdvances[5];
        CGGlyph hGlyph;
        CGRect hRect;
        CGPathRef hPath;
        CFDataRef headTable;
        CFIndex i;

        // 1. collections and available families
        families = CTFontManagerCopyAvailableFontFamilyNames();
        expect(families != NULL && CFArrayGetCount(families) > 0, "CTFontManagerCopyAvailableFontFamilyNames is non-empty");
        if (families != NULL)
            printf("      %ld families, first few:\n", (long) CFArrayGetCount(families));
        for (i = 0; families != NULL && i < 3 && i < CFArrayGetCount(families); i++) {
            printf("        ");
            printString((CFStringRef) CFArrayGetValueAtIndex(families, i));
        }

        collection = CTFontCollectionCreateFromAvailableFonts(NULL);
        descriptors = collection != NULL ? CTFontCollectionCreateMatchingFontDescriptors(collection) : NULL;
        expect(descriptors != NULL && CFArrayGetCount(descriptors) > 0, "CTFontCollectionCreateFromAvailableFonts has descriptors");
        if (descriptors != NULL) {
            printf("      %ld descriptors, first few:\n", (long) CFArrayGetCount(descriptors));
            for (i = 0; i < 3 && i < CFArrayGetCount(descriptors); i++) {
                CFStringRef family = (CFStringRef) CTFontDescriptorCopyAttribute((CTFontDescriptorRef) CFArrayGetValueAtIndex(descriptors, i), kCTFontFamilyNameAttribute);
                printf("        ");
                printString(family);
                if (family != NULL) CFRelease(family);
            }
        }

        // 2. matching "monospace" and the first family
        monospaceDescriptor = CTFontDescriptorCreateWithNameAndSize(CFSTR("monospace"), 24);
        monospaceMatch = monospaceDescriptor != NULL ? CTFontDescriptorCreateMatchingFontDescriptor(monospaceDescriptor, NULL) : NULL;
        expect(monospaceMatch != NULL, "descriptor for family monospace matches a font");
        if (monospaceMatch != NULL)
            printDescriptor("monospace", monospaceMatch);

        if (families != NULL && CFArrayGetCount(families) > 0) {
            CFDictionaryRef attributes = makeFamilyAttributes((CFStringRef) CFArrayGetValueAtIndex(families, 0));
            query = CTFontDescriptorCreateWithAttributes(attributes);
            firstFamilyMatch = CTFontDescriptorCreateMatchingFontDescriptor(query, NULL);
            CFRelease(query);
            CFRelease(attributes);
            expect(firstFamilyMatch != NULL, "descriptor for the first available family matches a font");
            if (firstFamilyMatch != NULL)
                printDescriptor("first family", firstFamilyMatch);
        }

        // 3. create a font at 24pt
        if (monospaceMatch != NULL) {
            font = CTFontCreateWithFontDescriptor(monospaceMatch, 24, NULL);
            expect(font != NULL, "CTFontCreateWithFontDescriptor returns a font");
            if (font != NULL) {
                expect(CTFontGetSize(font) == 24, "CTFontGetSize is 24");
                expect(CTFontGetAscent(font) > 0, "CTFontGetAscent > 0");
                expect(CTFontGetUnitsPerEm(font) > 0, "CTFontGetUnitsPerEm > 0");
            }
        }

        if (font != NULL) {
            // 4. glyphs and metrics
            expect(CTFontGetGlyphsForCharacters(font, hello, helloGlyphs, 5), "CTFontGetGlyphsForCharacters succeeds for Hello");
            for (i = 0; i < 5; i++)
                expect(helloGlyphs[i] != 0, "Hello glyph is non-zero");

            CTFontGetAdvancesForGlyphs(font, kCTFontOrientationDefault, helloGlyphs, helloAdvances, 5);
            for (i = 0; i < 5; i++)
                expect(helloAdvances[i].width > 0, "Hello advance > 0");

            hGlyph = helloGlyphs[0];
            CTFontGetBoundingRectsForGlyphs(font, kCTFontOrientationDefault, &hGlyph, &hRect, 1);
            expect(hRect.size.width > 0 && hRect.size.height > 0, "bounding rect of H has positive size");

            hPath = CTFontCreatePathForGlyph(font, hGlyph, NULL);
            expect(hPath != NULL && !CGPathIsEmpty(hPath), "CTFontCreatePathForGlyph(H) is non-empty");
            if (hPath != NULL)
                CGPathRelease(hPath);

            headTable = CTFontCopyTable(font, kCTFontTableHead, kCTFontTableOptionNoOptions);
            expect(headTable != NULL && CFDataGetLength(headTable) == 54, "CTFontCopyTable(head) is 54 bytes");
            if (headTable != NULL)
                CFRelease(headTable);

            expect(listsHeadTable(font), "CTFontCopyAvailableTables lists head as a raw tag");

            expect(checkDrawing(font), "CTFontDrawGlyphs draws white glyphs on black");
            expect(checkGlyphRasterization(font, 'H'), "a glyph rasterized like Alacritty does has lit pixels");
            expect(checkSkipFirstDrawing(font), "a glyph drawn into a NoneSkipFirst context like Skia does has lit pixels");
            {
                CTFontRef menlo = CTFontCreateWithName(CFSTR("Menlo"), 11.25, NULL);
                if (menlo != NULL) {
                    CFStringRef family = CTFontCopyFamilyName(menlo);
                    printf("      Menlo resolved to: ");
                    printString(family);
                    if (family != NULL) CFRelease(family);
                    expect((CTFontGetSymbolicTraits(menlo) & kCTFontTraitMonoSpace) != 0, "Menlo resolves to a monospace font");
                    // usually a face in a .ttc collection (Noto Sans Mono CJK)
                    expect(listsHeadTable(menlo), "CTFontCopyAvailableTables lists head for Menlo's font");
                    expect(checkGlyphRasterization(menlo, 'H'), "Menlo 11.25pt 'H' rasterized like Alacritty does has lit pixels");
                    CFRelease(menlo);
                }
            }

            // 5. font fallback for Hangul
            {
                UniChar hangul[1] = { 0xAC00 };
                CGGlyph hangulGlyph[1];
                CFStringRef string = CFSTR("\uAC00");
                CTFontRef fallback = CTFontCreateForString(font, string, CFRangeMake(0, CFStringGetLength(string)));

                if (fallback != NULL && CTFontGetGlyphsForCharacters(fallback, hangul, hangulGlyph, 1)) {
                    expect(1, "CTFontCreateForString found a font covering Hangul");
                } else {
                    printf("WARN: no fallback font covering Hangul was found (Noto CJK may be missing)\n");
                }
                if (fallback != NULL)
                    CFRelease(fallback);
            }
        }

        // release
        if (font != NULL) CFRelease(font);
        if (monospaceMatch != NULL) CFRelease(monospaceMatch);
        if (monospaceDescriptor != NULL) CFRelease(monospaceDescriptor);
        if (firstFamilyMatch != NULL) CFRelease(firstFamilyMatch);
        if (descriptors != NULL) CFRelease(descriptors);
        if (collection != NULL) CFRelease(collection);
        if (families != NULL) CFRelease(families);

        if (failures > 0) {
            printf("%d expect(s) failed\n", failures);
            return 1;
        }
        printf("PASS: all CoreText font checks succeeded\n");
    }
    return 0;
}