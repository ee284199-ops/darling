// UTITypes: checks Uniform Type Identifiers against the LaunchServices database (built by
// launchservicesd from the UTI declarations bundles ship): the CoreServices C API (UTType*)
// and the UniformTypeIdentifiers framework (UTType class, UTType* constants).
// Prints PASS/FAIL lines and exits non-zero on failure. Needs no window.

#import <CoreServices/CoreServices.h>
#import <Foundation/Foundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <stdio.h>

static int failures = 0;

static void expect(BOOL condition, NSString* what)
{
	printf("%s: %s\n", condition ? "PASS" : "FAIL", [what UTF8String]);
	if (!condition)
		++failures;
}

static void expectString(NSString* actual, NSString* expected, NSString* what)
{
	BOOL same = actual != nil && [actual caseInsensitiveCompare: expected] == NSOrderedSame;
	expect(same, [NSString stringWithFormat: @"%@ is %@ (got %@)", what, expected, actual]);
}

static void testCoreServices(void)
{
	// tags to identifiers and back
	NSString* png = [(NSString*) UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, CFSTR("png"), NULL) autorelease];
	expectString(png, @"public.png", @"UTI for the png extension");

	NSString* jpeg = [(NSString*) UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, CFSTR("image/jpeg"), NULL) autorelease];
	expectString(jpeg, @"public.jpeg", @"UTI for image/jpeg");

	NSString* mime = [(NSString*) UTTypeCopyPreferredTagWithClass(CFSTR("public.png"), kUTTagClassMIMEType) autorelease];
	expectString(mime, @"image/png", @"MIME type of public.png");

	NSString* txt = [(NSString*) UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, CFSTR("txt"), kUTTypeText) autorelease];
	expectString(txt, @"public.plain-text", @"UTI for txt conforming to public.text");

	// conformance is reflexive and transitive
	expect(UTTypeConformsTo(CFSTR("public.png"), CFSTR("public.png")), @"public.png conforms to itself");
	expect(UTTypeConformsTo(CFSTR("public.png"), CFSTR("public.image")), @"public.png conforms to public.image");
	expect(UTTypeConformsTo(CFSTR("public.png"), CFSTR("public.data")), @"public.png conforms to public.data (through public.image)");
	expect(UTTypeConformsTo(CFSTR("public.png"), CFSTR("public.item")), @"public.png conforms to public.item");
	expect(!UTTypeConformsTo(CFSTR("public.png"), CFSTR("public.text")), @"public.png doesn't conform to public.text");
	expect(UTTypeConformsTo(CFSTR("PUBLIC.PNG"), CFSTR("public.image")), @"UTIs compare without case");

	// unknown tags get dynamic identifiers that lead back to the tag
	NSString* dynamic = [(NSString*) UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, CFSTR("darlingtest"), NULL) autorelease];
	expect([dynamic hasPrefix: @"dyn."], [NSString stringWithFormat: @"an unknown extension gets a dynamic UTI (got %@)", dynamic]);
	if (dynamic != nil) {
		expect(UTTypeIsDynamic((CFStringRef) dynamic), @"UTTypeIsDynamic says so");
		NSString* back = [(NSString*) UTTypeCopyPreferredTagWithClass((CFStringRef) dynamic, kUTTagClassFilenameExtension) autorelease];
		expectString(back, @"darlingtest", @"the dynamic UTI's extension");
	}
	expect(!UTTypeIsDynamic(CFSTR("public.png")), @"public.png isn't dynamic");

	// declarations
	expect(UTTypeIsDeclared(CFSTR("public.jpeg")), @"public.jpeg is declared");
	NSString* description = [(NSString*) UTTypeCopyDescription(CFSTR("public.jpeg")) autorelease];
	expect([description length] > 0, [NSString stringWithFormat: @"public.jpeg has a description (%@)", description]);

	// OSTypes
	NSString* text = [(NSString*) UTCreateStringForOSType('TEXT') autorelease];
	expectString(text, @"TEXT", @"UTCreateStringForOSType('TEXT')");
	expect(UTGetOSTypeFromString(CFSTR("TEXT")) == 'TEXT', @"UTGetOSTypeFromString(TEXT) is 'TEXT'");
}

static void testUniformTypeIdentifiers(void)
{
	UTType* png = [UTType typeWithFilenameExtension: @"png"];
	expectString(png.identifier, @"public.png", @"[UTType typeWithFilenameExtension: png]");
	expectString(png.preferredMIMEType, @"image/png", @"its preferredMIMEType");
	expectString(png.preferredFilenameExtension, @"png", @"its preferredFilenameExtension");
	expect([png conformsToType: UTTypeImage], @"it conforms to UTTypeImage");
	expect([png conformsToType: UTTypeData], @"it conforms to UTTypeData");
	expect(![png conformsToType: UTTypeText], @"it doesn't conform to UTTypeText");
	expect([png isSubtypeOfType: UTTypeImage] && ![png isSubtypeOfType: UTTypePNG], @"isSubtypeOfType: excludes the type itself");
	expect([png isEqual: UTTypePNG], @"it equals UTTypePNG");
	expect(png.declared && !png.dynamic, @"it is declared and not dynamic");
	expect(png.publicType, @"it is a public type");
	expect([png.supertypes containsObject: UTTypeImage], @"its supertypes include UTTypeImage");

	expect(UTTypePlainText != nil, @"UTTypePlainText isn't nil");
	expectString(UTTypePlainText.identifier, @"public.plain-text", @"UTTypePlainText's identifier");
	expectString(UTTypePlainText.preferredMIMEType, @"text/plain", @"UTTypePlainText's MIME type");
	expectString(UTTypeFolder.identifier, @"public.folder", @"UTTypeFolder's identifier");
	expectString(UTTypeApplicationBundle.identifier, @"com.apple.application-bundle", @"UTTypeApplicationBundle's identifier");
	expectString(UTTypeJSON.identifier, @"public.json", @"UTTypeJSON's identifier");
	expectString(UTTagClassFilenameExtension, @"public.filename-extension", @"UTTagClassFilenameExtension");
	expectString(UTTagClassMIMEType, @"public.mime-type", @"UTTagClassMIMEType");

	UTType* jpeg = [UTType typeWithMIMEType: @"image/jpeg"];
	expectString(jpeg.identifier, @"public.jpeg", @"[UTType typeWithMIMEType: image/jpeg]");

	UTType* text = [UTType typeWithIdentifier: @"public.plain-text"];
	expect(text != nil && [text conformsToType: UTTypeText], @"typeWithIdentifier: public.plain-text conforms to UTTypeText");
	expect([UTType typeWithIdentifier: @"com.example.not-declared"] == nil || ![UTType typeWithIdentifier: @"com.example.not-declared"].declared,
		@"an undeclared identifier isn't declared");

	UTType* dynamic = [UTType typeWithFilenameExtension: @"darlingtest"];
	expect(dynamic != nil && dynamic.dynamic, @"an unknown extension gives a dynamic type");
	expectString(dynamic.preferredFilenameExtension, @"darlingtest", @"its preferredFilenameExtension");

	UTType* textFile = [UTType typeWithFilenameExtension: @"txt" conformingToType: UTTypeText];
	expectString(textFile.identifier, @"public.plain-text", @"typeWithFilenameExtension: txt conformingToType: UTTypeText");

	expect([[UTType typesWithTag: @"jpg" tagClass: UTTagClassFilenameExtension conformingToType: nil] containsObject: UTTypeJPEG],
		@"typesWithTag: jpg includes UTTypeJPEG");

	expectString([@"photo" stringByAppendingPathExtensionForType: UTTypePNG], @"photo.png",
		@"stringByAppendingPathExtensionForType:");
	expectString([[NSURL fileURLWithPath: @"/tmp/photo"] URLByAppendingPathExtensionForType: UTTypeJPEG].lastPathComponent,
		@"photo.jpeg", @"URLByAppendingPathExtensionForType:");

	// archiving keeps the identifier
	NSData* data = [NSKeyedArchiver archivedDataWithRootObject: png requiringSecureCoding: YES error: NULL];
	UTType* unarchived = data != nil ? [NSKeyedUnarchiver unarchivedObjectOfClass: [UTType class] fromData: data error: NULL] : nil;
	expect([unarchived isEqual: png], @"a UTType survives keyed archiving");
}

int main(int argc, const char** argv)
{
	@autoreleasepool {
		testCoreServices();
		testUniformTypeIdentifiers();

		if (failures > 0) {
			printf("%d check(s) failed\n", failures);
			return 1;
		}
		printf("PASS: all UTI checks succeeded\n");
	}
	return 0;
}
