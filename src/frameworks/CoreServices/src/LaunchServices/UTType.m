/*
This file is part of Darling.

Copyright (C) 2020 Lubos Dolezel

Darling is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Darling is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/


#include <LaunchServices/LaunchServices.h>
#import <Foundation/Foundation.h>
#import <fmdb/FMDatabaseQueue.h>

#include <stdint.h>

extern FMDatabaseQueue* getDatabaseQueue(void);

//
// dynamic type identifiers
//
// A dynamic identifier is "dyn." followed by the lowercase, unpadded RFC 4648 base32
// encoding of the UTF-8 payload "ct:<tag class>\ntg:<tag>\ncf:<conforming type>".
// This is reversible using only characters that are valid in a UTI.
//

static const char kUTBase32Alphabet[] = "abcdefghijklmnopqrstuvwxyz234567";

static NSString* UTBase32Encode(NSData* data)
{
	const uint8_t* bytes = [data bytes];
	NSUInteger length = [data length];
	NSMutableString* result = [NSMutableString stringWithCapacity: (length * 8 + 4) / 5];
	unsigned long long buffer = 0;
	int bits = 0;
	NSUInteger i;

	for (i = 0; i < length; i++)
	{
		buffer = (buffer << 8) | bytes[i];
		bits += 8;

		while (bits >= 5)
		{
			bits -= 5;
			[result appendFormat: @"%c", kUTBase32Alphabet[(buffer >> bits) & 0x1f]];
		}

		buffer &= (bits > 0) ? ((1ull << bits) - 1) : 0;
	}

	if (bits > 0)
		[result appendFormat: @"%c", kUTBase32Alphabet[(buffer << (5 - bits)) & 0x1f]];

	return result;
}

static NSData* UTBase32Decode(NSString* string)
{
	NSMutableData* result = [NSMutableData data];
	unsigned long long buffer = 0;
	int bits = 0;
	NSUInteger length = [string length];
	NSUInteger i;

	for (i = 0; i < length; i++)
	{
		unichar ch = [string characterAtIndex: i];
		int value;

		if (ch >= 'a' && ch <= 'z')
			value = ch - 'a';
		else if (ch >= 'A' && ch <= 'Z')
			value = ch - 'A';
		else if (ch >= '2' && ch <= '7')
			value = 26 + (ch - '2');
		else
			return nil;

		buffer = (buffer << 5) | (unsigned)value;
		bits += 5;

		if (bits >= 8)
		{
			uint8_t byte;

			bits -= 8;
			byte = (buffer >> bits) & 0xff;
			[result appendBytes: &byte length: 1];
		}

		buffer &= (bits > 0) ? ((1ull << bits) - 1) : 0;
	}

	return result;
}

static BOOL UTStringIsDynamic(CFStringRef identifier)
{
	UniChar prefix[4];

	if (identifier == NULL || CFStringGetLength(identifier) < 4)
		return NO;

	CFStringGetCharacters(identifier, CFRangeMake(0, 4), prefix);

	return (prefix[0] == 'd' || prefix[0] == 'D')
		&& (prefix[1] == 'y' || prefix[1] == 'Y')
		&& (prefix[2] == 'n' || prefix[2] == 'N')
		&& prefix[3] == '.';
}

// returns a dictionary with keys ct/tg/cf, or nil if `identifier` is not a valid dynamic UTI
static NSDictionary* UTDecodeDynamicIdentifier(CFStringRef identifier)
{
	NSString* ident;
	NSString* prefix;
	NSString* encoded;
	NSData* data;
	NSString* payload;
	NSMutableDictionary* result;

	if (!UTStringIsDynamic(identifier))
		return nil;

	ident = (NSString*) identifier;
	prefix = [ident substringToIndex: 4];

	if ([prefix caseInsensitiveCompare: @"dyn."] != NSOrderedSame)
		return nil;

	encoded = [ident substringFromIndex: 4];
	data = UTBase32Decode(encoded);
	if (data == nil)
		return nil;

	payload = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];
	if (payload == nil)
		return nil;

	result = [NSMutableDictionary dictionary];

	for (NSString* line in [payload componentsSeparatedByString: @"\n"])
	{
		if ([line hasPrefix: @"ct:"])
			[result setObject: [line substringFromIndex: 3] forKey: @"ct"];
		else if ([line hasPrefix: @"tg:"])
			[result setObject: [line substringFromIndex: 3] forKey: @"tg"];
		else if ([line hasPrefix: @"cf:"])
			[result setObject: [line substringFromIndex: 3] forKey: @"cf"];
	}

	if ([result objectForKey: @"ct"] == nil || [result objectForKey: @"tg"] == nil)
		return nil;

	return result;
}

static CFStringRef UTDecodeDynamicIdentifierTag(CFStringRef identifier, CFStringRef tagClass)
{
	NSDictionary* payload = UTDecodeDynamicIdentifier(identifier);
	NSString* encodedClass;
	NSString* encodedTag;

	if (payload == nil)
		return NULL;

	encodedClass = [payload objectForKey: @"ct"];
	encodedTag = [payload objectForKey: @"tg"];

	if (tagClass == NULL || [encodedClass caseInsensitiveCompare: (NSString*) tagClass] != NSOrderedSame)
		return NULL;

	return (CFStringRef) [[encodedTag copy] autorelease];
}

static CFStringRef UTCreateDynamicIdentifier(CFStringRef tagClass, CFStringRef tag, CFStringRef conforming)
{
	NSMutableString* payload = [NSMutableString string];

	[payload appendFormat: @"ct:%@\n", (NSString*) tagClass];
	[payload appendFormat: @"tg:%@\n", (NSString*) tag];
	[payload appendFormat: @"cf:%@", conforming != NULL ? (NSString*) conforming : @""];

	return (CFStringRef) [[@"dyn." stringByAppendingString: UTBase32Encode([payload dataUsingEncoding: NSUTF8StringEncoding])] copy];
}

//
// database helpers
//

static CFArrayRef arrayForStringColumn0(FMResultSet* rs)
{
	if (rs != nil && [rs next])
	{
		NSMutableArray* array = [[NSMutableArray alloc] initWithCapacity: 0];
		do
		{
			NSString* value = [rs stringForColumnIndex: 0];
			if (value != nil)
				[array addObject: value];
		}
		while ([rs next]);

		CFArrayRef retval = (CFArrayRef) [[NSArray alloc] initWithArray: array];
		[array release];

		return retval;
	}
	else
	{
		return NULL;
	}
}

_Nullable CFStringRef
UTTypeCreatePreferredIdentifierForTag(
  CFStringRef inTagClass,
  CFStringRef inTag,
  _Nullable CFStringRef inConformingToUTI)
{
	CFArrayRef array = UTTypeCreateAllIdentifiersForTag(inTagClass, inTag, inConformingToUTI);
	CFStringRef str;

	if (array == NULL || CFArrayGetCount(array) == 0)
	{
		if (array != NULL)
			CFRelease(array);
		return NULL;
	}

	str = (CFStringRef) CFRetain(CFArrayGetValueAtIndex(array, 0));
	CFRelease(array);

	return str;
}

_Nullable CFArrayRef
UTTypeCreateAllIdentifiersForTag(
  CFStringRef inTagClass,
  CFStringRef inTag,
  _Nullable CFStringRef inConformingToUTI)
{
	FMDatabaseQueue* dq;
	NSMutableArray* result;

	if (inTagClass == NULL || inTag == NULL)
		return NULL;

	result = [NSMutableArray array];
	dq = getDatabaseQueue();

	if (dq != nil)
	{
		[dq inDatabase:^(FMDatabase* db) {
			FMResultSet* rs;

			if (inConformingToUTI != NULL)
			{
				// the recursive CTE collects the requested type and all of its subtypes, so that
				// only declared types that (transitively) conform to it are returned
				rs = [db executeQuery:
					@"WITH RECURSIVE conformers(ident) AS ("
					@" SELECT ? COLLATE NOCASE"
					@" UNION"
					@" SELECT u2.type_identifier FROM uti u2"
					@" JOIN uti_conforms c ON c.uti=u2.id"
					@" JOIN conformers r ON c.conforms_to = r.ident COLLATE NOCASE"
					@") SELECT u.type_identifier FROM uti u JOIN uti_tag t ON t.uti=u.id"
					@" WHERE t.tag = ? AND t.value = ?"
					@" AND u.type_identifier IN (SELECT ident FROM conformers)"
					@" ORDER BY u.id",
					inConformingToUTI, inTagClass, inTag];
			}
			else
			{
				rs = [db executeQuery:
					@"SELECT u.type_identifier FROM uti u JOIN uti_tag t ON t.uti=u.id"
					@" WHERE t.tag = ? AND t.value = ? ORDER BY u.id",
					inTagClass, inTag];
			}

			while ([rs next])
			{
				NSString* identifier = [rs stringForColumnIndex: 0];

				if (identifier == nil)
					continue;

				// dedupe without case
				BOOL seen = NO;
				for (NSString* existing in result)
				{
					if ([existing caseInsensitiveCompare: identifier] == NSOrderedSame)
					{
						seen = YES;
						break;
					}
				}

				if (!seen)
					[result addObject: identifier];
			}

			[rs close];
		}];
	}

	if ([result count] == 0)
	{
		CFStringRef dynamic = UTCreateDynamicIdentifier(inTagClass, inTag, inConformingToUTI);

		if (dynamic == NULL)
			return NULL;

		[result addObject: (NSString*) dynamic];
		CFRelease(dynamic);
	}

	return (CFArrayRef) [[NSArray alloc] initWithArray: result];
}

_Nullable CFStringRef
UTTypeCopyPreferredTagWithClass(
  CFStringRef inUTI,
  CFStringRef inTagClass)
{
	CFArrayRef array = UTTypeCopyAllTagsWithClass(inUTI, inTagClass);
	CFStringRef str;

	if (array == NULL || CFArrayGetCount(array) == 0)
	{
		if (array != NULL)
			CFRelease(array);
		return NULL;
	}

	str = (CFStringRef) CFRetain(CFArrayGetValueAtIndex(array, 0));
	CFRelease(array);

	return str;
}

_Nullable CFArrayRef
UTTypeCopyAllTagsWithClass(
  CFStringRef inUTI,
  CFStringRef inTagClass)
{
	FMDatabaseQueue* dq;
	CFArrayRef retval;

	if (inUTI == NULL || inTagClass == NULL)
		return NULL;

	if (UTStringIsDynamic(inUTI))
	{
		CFStringRef tag = UTDecodeDynamicIdentifierTag(inUTI, inTagClass);
		NSArray* array;

		if (tag == NULL)
			return NULL;

		array = [NSArray arrayWithObject: (NSString*) tag];
		return (CFArrayRef) [array copy];
	}

	dq = getDatabaseQueue();
	if (dq == nil)
		return NULL;

	__block CFArrayRef result = NULL;
	[dq inDatabase:^(FMDatabase* db) {
		FMResultSet* rs = [db executeQuery:
			@"select UT.value from uti inner join uti_tag UT on UT.uti=uti.id"
			@" where UT.tag = ? and type_identifier = ?",
			inTagClass, inUTI];

		result = arrayForStringColumn0(rs);
		[rs close];
	}];

	retval = result;
	return retval;
}

Boolean
UTTypeEqual(
  CFStringRef inUTI1,
  CFStringRef inUTI2)
{
	if (inUTI1 == NULL || inUTI2 == NULL)
		return inUTI1 == inUTI2;

	return CFStringCompare(inUTI1, inUTI2, kCFCompareCaseInsensitive) == kCFCompareEqualTo;
}

Boolean
UTTypeConformsTo(
  CFStringRef inUTI,
  CFStringRef inConformsToUTI)
{
	FMDatabaseQueue* dq;
	__block Boolean result = FALSE;

	if (inUTI == NULL || inConformsToUTI == NULL)
		return FALSE;

	if (UTTypeEqual(inUTI, inConformsToUTI))
		return TRUE;

	if (UTStringIsDynamic(inUTI))
	{
		NSDictionary* payload = UTDecodeDynamicIdentifier(inUTI);
		NSString* conforming;

		if (payload == nil)
			return FALSE;

		conforming = [payload objectForKey: @"cf"];
		if ([conforming length] > 0 && UTTypeEqual((CFStringRef) conforming, inConformsToUTI))
			return TRUE;

		{
			NSString* tagClass = [payload objectForKey: @"ct"];

			if ([tagClass caseInsensitiveCompare: (NSString*) kUTTagClassFilenameExtension] == NSOrderedSame
			 || [tagClass caseInsensitiveCompare: (NSString*) kUTTagClassMIMEType] == NSOrderedSame)
			{
				if (UTTypeEqual(CFSTR("public.data"), inConformsToUTI)
				 || UTTypeEqual(CFSTR("public.item"), inConformsToUTI))
					return TRUE;
			}
		}

		return FALSE;
	}

	dq = getDatabaseQueue();
	if (dq == nil)
		return FALSE;

	[dq inDatabase:^(FMDatabase* db) {
		FMResultSet* rs = [db executeQuery:
			@"WITH RECURSIVE reach(ident) AS ("
			@" SELECT c.conforms_to FROM uti u JOIN uti_conforms c ON c.uti=u.id WHERE u.type_identifier = ? COLLATE NOCASE"
			@" UNION"
			@" SELECT c.conforms_to FROM uti u JOIN uti_conforms c ON c.uti=u.id"
			@" JOIN reach r ON u.type_identifier = r.ident COLLATE NOCASE"
			@") SELECT ident FROM reach WHERE ident = ? COLLATE NOCASE LIMIT 1",
			inUTI, inConformsToUTI];

		result = [rs next];
		[rs close];
	}];

	return result;
}

_Nullable CFStringRef
UTTypeCopyDescription(CFStringRef inUTI)
{
	FMDatabaseQueue* dq;
	__block CFStringRef retval = NULL;

	if (inUTI == NULL || UTStringIsDynamic(inUTI))
		return NULL;

	dq = getDatabaseQueue();
	if (dq == nil)
		return NULL;

	[dq inDatabase:^(FMDatabase* db) {
		FMResultSet* rs = [db executeQuery:@"select description from uti where type_identifier = ?", inUTI];
		if ([rs next])
			retval = (CFStringRef) [[rs stringForColumnIndex:0] retain];
		else
			retval = NULL;
		[rs close];
	}];

	return retval;
}

Boolean
UTTypeIsDeclared(CFStringRef inUTI)
{
	CFStringRef str;

	if (inUTI == NULL || UTStringIsDynamic(inUTI))
		return FALSE;

	str = UTTypeCopyDescription(inUTI);
	if (str != NULL)
	{
		CFRelease(str);
		return TRUE;
	}
	else
		return FALSE;
}

Boolean
UTTypeIsDynamic(CFStringRef inUTI)
{
	return UTStringIsDynamic(inUTI);
}

_Nullable CFDictionaryRef
UTTypeCopyDeclaration(CFStringRef inUTI)
{
	FMDatabaseQueue* dq;
	__block CFDictionaryRef retval = NULL;

	if (inUTI == NULL || UTStringIsDynamic(inUTI))
		return NULL;

	dq = getDatabaseQueue();
	if (dq == nil)
		return NULL;

	[dq inDatabase:^(FMDatabase* db) {
		FMResultSet* rs = [db executeQuery:@"select id, description from uti where type_identifier = ?", inUTI];
		if ([rs next])
		{
			NSMutableDictionary* dict = [[NSMutableDictionary alloc] initWithCapacity: 5];
			NSNumber* utiId = [NSNumber numberWithInt: [rs intForColumn:@"id"]];

			[dict setObject: (NSString*) inUTI forKey: (NSString*) kUTTypeIdentifierKey];
			if ([rs stringForColumn:@"description"] != nil)
				[dict setObject: [rs stringForColumn:@"description"] forKey: (NSString*) kUTTypeDescriptionKey];
			[rs close];

			{
				NSMutableArray* conformsTo = [[NSMutableArray alloc] initWithCapacity:0];
				rs = [db executeQuery:@"select conforms_to from uti_conforms where uti = ?", utiId];

				while ([rs next])
				{
					NSString* value = [rs stringForColumnIndex:0];
					if (value != nil)
						[conformsTo addObject: value];
				}

				[rs close];
				[dict setObject: conformsTo forKey: (NSString*) kUTTypeConformsToKey];
				[conformsTo release];
			}

			{
				NSMutableDictionary* tags = [[NSMutableDictionary alloc] initWithCapacity:0];
				rs = [db executeQuery:@"select tag, value from uti_tag where uti = ?", utiId];

				while ([rs next])
				{
					NSString* tag = [rs stringForColumn:@"tag"];
					NSString* value = [rs stringForColumn:@"value"];

					if (tag == nil || value == nil)
						continue;

					NSMutableArray* values = [tags objectForKey: tag];
					if (values == nil)
					{
						values = [NSMutableArray array];
						[tags setObject: values forKey: tag];
					}
					[values addObject: value];
				}

				[rs close];
				[dict setObject: tags forKey: (NSString*) kUTTypeTagSpecificationKey];
				[tags release];
			}

			{
				NSMutableArray* icons = [[NSMutableArray alloc] initWithCapacity:0];
				rs = [db executeQuery:@"select file from uti_icon where uti = ?", utiId];

				while ([rs next])
				{
					NSString* value = [rs stringForColumnIndex:0];
					if (value != nil)
						[icons addObject: value];
				}

				[rs close];
				[dict setObject: icons forKey: @"UTTypeIconFiles"];
				[icons release];
			}

			retval = (CFDictionaryRef) [[NSDictionary alloc] initWithDictionary:dict copyItems:YES];
			[dict release];
		}
		else
		{
			[rs close];
			retval = NULL;
		}
	}];

	return retval;
}

_Nullable CFURLRef
UTTypeCopyDeclaringBundleURL(CFStringRef inUTI)
{
	FMDatabaseQueue* dq;
	__block CFURLRef retval = NULL;

	if (inUTI == NULL || UTStringIsDynamic(inUTI))
		return NULL;

	dq = getDatabaseQueue();
	if (dq == nil)
		return NULL;

	[dq inDatabase:^(FMDatabase* db) {
		FMResultSet* rs = [db executeQuery:@"select B.path from uti inner join bundle B on B.id=uti.bundle where type_identifier = ?", inUTI];
		if ([rs next])
		{
			NSString* path = [rs stringForColumnIndex:0];
			retval = path != nil ? CFURLCreateWithFileSystemPath(NULL, (CFStringRef) path, kCFURLPOSIXPathStyle, TRUE) : NULL;
		}
		else
			retval = NULL;
		[rs close];
	}];

	return retval;
}

CFArrayRef
UTTypeCopyParentIdentifiers(CFStringRef inUTI)
{
	FMDatabaseQueue* dq;
	__block CFArrayRef retval = NULL;

	if (inUTI == NULL)
		return NULL;

	if (UTStringIsDynamic(inUTI))
	{
		NSDictionary* payload = UTDecodeDynamicIdentifier(inUTI);
		NSMutableArray* parents;

		if (payload == nil)
			return NULL;

		parents = [NSMutableArray array];

		{
			NSString* conforming = [payload objectForKey: @"cf"];
			if ([conforming length] > 0)
				[parents addObject: conforming];
		}

		[parents addObject: @"public.data"];
		[parents addObject: @"public.item"];

		return (CFArrayRef) [parents copy];
	}

	dq = getDatabaseQueue();
	if (dq == nil)
		return NULL;

	[dq inDatabase:^(FMDatabase* db) {
		FMResultSet* rs = [db executeQuery:@"select id from uti where type_identifier = ?", inUTI];
		if ([rs next])
		{
			NSNumber* utiId = [NSNumber numberWithInt: [rs intForColumn:@"id"]];
			[rs close];

			{
				NSMutableArray* conformsTo = [[NSMutableArray alloc] init];
				rs = [db executeQuery:@"select conforms_to from uti_conforms where uti = ?", utiId];

				while ([rs next])
				{
					NSString* value = [rs stringForColumnIndex:0];
					if (value != nil)
						[conformsTo addObject: value];
				}

				[rs close];

				retval = (CFArrayRef) [[NSArray alloc] initWithArray: conformsTo copyItems: YES];
				[conformsTo release];
			}
		}
		else
		{
			[rs close];
		}
	}];

	return retval;
}

CFStringRef
UTCreateStringForOSType(OSType inOSType)
{
	char buf[5];
	int i;

	for (i = 0; i < 4; i++)
		buf[i] = (char) ((inOSType >> (24 - i * 8)) & 0xff);
	buf[4] = '\0';

	// trim trailing spaces/nulls, like the system implementation
	for (i = 3; i >= 0 && (buf[i] == ' ' || buf[i] == '\0'); i--)
		buf[i] = '\0';

	return CFStringCreateWithCString(NULL, buf, kCFStringEncodingASCII);
}

OSType
UTGetOSTypeFromString(CFStringRef inString)
{
	CFIndex length;
	char buf[5];
	OSType retval = 0;
	int i;

	if (!inString)
		return 0;
	if (CFStringGetLength(inString) > 4)
		return 0;

	length = CFStringGetLength(inString);
	if (!CFStringGetCString(inString, buf, sizeof(buf), kCFStringEncodingASCII))
		return 0;

	for (i = 0; i < 4; i++)
	{
		retval <<= 8;
		retval |= (i < length) ? (((UInt32) buf[i]) & 0xff) : ' ';
	}

	return retval;
}