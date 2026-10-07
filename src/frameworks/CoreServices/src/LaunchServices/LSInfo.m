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
#include <CarbonCore/MacErrors.h>
#include <stdio.h>
#include <sqlite3.h>
#import <Foundation/NSString.h>
#import <fmdb/FMDatabaseQueue.h>

__attribute__((visibility("hidden")))
FMDatabaseQueue* getDatabaseQueue(void)
{
	static dispatch_once_t pred;
	static FMDatabaseQueue* db;
	dispatch_once(&pred, ^{
		db = [[FMDatabaseQueue databaseQueueWithPath: @"/private/var/db/launchservices.db" flags:SQLITE_OPEN_READONLY] retain];
	});
	return db;
}

__attribute__((visibility("hidden")))
NSString* escape(NSString* str)
{
	return [str stringByReplacingOccurrencesOfString:@"'"
		withString:@"''"];
}

// An SQL-safe fourcc string
static NSString* fourcc(UInt32 code)
{
	CFStringRef str = UTCreateStringForOSType(code);
	NSString* rv = escape((NSString*) str);
	CFRelease(str);

	return rv;
}

OSStatus
LSFindApplicationForInfo(
  OSType inCreator,
  CFStringRef inBundleID,
  CFStringRef inName,
  FSRef * outAppRef,
  CFURLRef * outAppURL)
{
	if (outAppURL)
		*outAppURL = NULL;

	if (inCreator == kLSUnknownCreator && !inBundleID && !inName)
		return paramErr;

	__block OSStatus retval;
	FMDatabaseQueue* dq = getDatabaseQueue();

	if (dq == nil)
		return fnfErr;

	[dq inDatabase:^(FMDatabase* db) {
		NSString* query = @"select path from bundle where package_type='APPL'";

		if (inCreator != kLSUnknownCreator)
			query = [query stringByAppendingFormat:@" and creator = '%@'", fourcc(inCreator)];
		if (inBundleID != NULL)
			query = [query stringByAppendingFormat:@" and bundle_id = '%@'", escape((NSString*) inBundleID)];
		if (inName != NULL)
			query = [query stringByAppendingFormat:@" and path like '%%%@'", escape((NSString*) inName)];
		
		FMResultSet* rs = [db executeQuery:query];
		if ([rs next])
		{
			NSString* path = [rs stringForColumn:@"path"];
			if (outAppURL)
				*outAppURL = (CFURLRef) [[NSURL alloc] initFileURLWithPath:path isDirectory:YES];
			if (outAppRef)
				FSPathMakeRef((const UInt8*) [path fileSystemRepresentation], outAppRef, NULL);

			retval = noErr;
		}
		else
			retval = kLSApplicationNotFoundErr;
		[rs close];
	}];

	return retval;
}

CFArrayRef LSCopyApplicationURLsForBundleIdentifier(CFStringRef inBundleIdentifier, CFErrorRef  _Nullable *outError)
{
	if (!inBundleIdentifier)
	{
		if (outError)
			*outError = CFErrorCreate(NULL, kCFErrorDomainOSStatus, paramErr, NULL);
		return NULL;
	}

	__block CFArrayRef retval;
	FMDatabaseQueue* dq = getDatabaseQueue();

	if (dq == nil)
	{
		if (outError)
			*outError = CFErrorCreate(NULL, kCFErrorDomainOSStatus, fnfErr, NULL);
		return NULL;
	}

	[dq inDatabase:^(FMDatabase* db) {
		FMResultSet* rs = [db executeQuery:@"select path from bundle where package_type='APPL' and bundle_id = ?", inBundleIdentifier];

		if ([rs next])
		{
			NSMutableArray* mut = [[NSMutableArray alloc] init];
			do
			{
				[mut addObject: [NSURL fileURLWithPath: [rs stringForColumn:@"path"] isDirectory: YES]];
			}
			while ([rs next]);

			retval = (CFArrayRef) [[NSArray alloc] initWithArray: mut];
			[mut release];
		}
		else
		{
			if (outError)
				*outError = CFErrorCreate(NULL, kCFErrorDomainOSStatus, kLSApplicationNotFoundErr, NULL);
			retval = NULL;
		}
		[rs close];
	}];

	return retval;
}

static NSString* appendRole(NSString* str, NSString* role)
{
	if (str == nil)
		return [NSString stringWithFormat:@"'%@'", role];
	else
		return [str stringByAppendingFormat:@",'%@'", role];
}

static NSString* roleSQLArray(LSRolesMask inRoleMask)
{
	NSString* str = nil;
	if (inRoleMask & kLSRolesNone)
		str = appendRole(str, @"None");
	if (inRoleMask & kLSRolesViewer)
		str = appendRole(str, @"Viewer");
	if (inRoleMask & kLSRolesEditor)
		str = appendRole(str, @"Editor");
	if (inRoleMask & kLSRolesShell)
		str = appendRole(str, @"Shell");
	return str;
}

OSStatus
LSGetApplicationForInfo(
  OSType inType,
  OSType inCreator,
  CFStringRef inExtension,
  LSRolesMask inRoleMask,
  FSRef * outAppRef,
  CFURLRef * outAppURL)
{
	__block OSStatus retval;

	if (outAppURL)
		*outAppURL = NULL;

	if (inType == kLSUnknownType && inCreator == kLSUnknownCreator && inExtension == NULL)
	{
		return paramErr;
	}

	FMDatabaseQueue* dq = getDatabaseQueue();
	if (dq == nil)
		return fnfErr;

	[dq inDatabase:^(FMDatabase* db) {
		NSString* query = @"select path, AD.rank from bundle INNER JOIN app_doc AD on AD.bundle=bundle.id where bundle.package_type='APPL'";

		if (inExtension != NULL)
		{
			NSString* escaped = escape((NSString*) inExtension);
			query = [query stringByAppendingFormat:@" and (EXISTS (SELECT * FROM app_doc_extension AE WHERE AE.doc=AD.class AND AE.extension = '%@')"
							@" OR "
					@"EXISTS (SELECT * FROM app_doc_uti AU JOIN uti ON uti.type_identifier = AU.uti JOIN uti_tag UT ON UT.uti=uti.id WHERE AU.doc=AD.id AND UT.tag = 'public.filename-extension' AND UT.value='%@'))",
					escaped, escaped];
		}
		
		if (inType != kLSUnknownType)
			query = [query stringByAppendingFormat:@" and signature='%@'", fourcc(inType)];
		if (inCreator != kLSUnknownCreator)
			query = [query stringByAppendingFormat:@" and creator='%@'", fourcc(inCreator)];
		if (inRoleMask != kLSRolesAll)
		{
			query = [query stringByAppendingFormat:@" and id IN (SELECT A.bundle FROM app_doc WHERE role IN (%@))", roleSQLArray(inRoleMask)];
		}

		query = [query stringByAppendingString:@" order by case "
			@"when AD.rank='Owner' then 1 "
			@"when AD.rank='Default' then 2 "
			@"when AD.rank='Alternate' then 3 "
			@"else 5 "
			@"end asc"];

		FMResultSet* rs = [db executeQuery:query];
		if ([rs next])
		{
			NSString* path = [rs stringForColumn:@"path"];
			if (outAppURL)
				*outAppURL = (CFURLRef) [[NSURL alloc] initFileURLWithPath:path isDirectory:YES];
			if (outAppRef)
				FSPathMakeRef((const UInt8*) [path fileSystemRepresentation], outAppRef, NULL);

			retval = noErr;
		}
		else
			retval = kLSApplicationNotFoundErr;
		[rs close];
	}];

	return retval;
}

CFURLRef LSCopyDefaultApplicationURLForContentType(CFStringRef inContentType, LSRolesMask inRoleMask, CFErrorRef  _Nullable *outError)
{
	__block CFURLRef retval;
	FMDatabaseQueue* dq = getDatabaseQueue();

	if (dq == nil)
	{
		if (outError)
			*outError = CFErrorCreate(NULL, kCFErrorDomainOSStatus, fnfErr, NULL);
		return NULL;
	}

	[dq inDatabase:^(FMDatabase* db) {
		NSString* query = @"select path, AD.rank from bundle INNER JOIN app_doc AD on AD.bundle=bundle.id LEFT JOIN app_doc_uti AU on AU.doc=AD.id WHERE bundle.package_type='APPL' AND uti=?";

		if (inRoleMask != kLSRolesAll)
		{
			query = [query stringByAppendingFormat:@" and AD.role in (%@)", roleSQLArray(inRoleMask)];
		}

		query = [query stringByAppendingString:@" order by case "
			@"when AD.rank='Owner' then 1 "
			@"when AD.rank='Default' then 2 "
			@"when AD.rank='Alternate' then 3 "
			@"else 5 "
			@"end asc"];

		FMResultSet* rs = [db executeQuery:query, inContentType];

		if ([rs next])
		{
			retval = (CFURLRef) [[NSURL alloc] initFileURLWithPath: [rs stringForColumn:@"path"] isDirectory: YES];
		}
		else
		{
			if (outError)
				*outError = CFErrorCreate(NULL, kCFErrorDomainOSStatus, kLSApplicationNotFoundErr, NULL);
			retval = NULL;
		}
		[rs close];
	}];

	return retval;
}

CFURLRef LSCopyDefaultApplicationURLForURL(CFURLRef inURL, LSRolesMask inRoleMask, CFErrorRef  _Nullable *outError)
{
	CFURLRef retval;
	OSStatus status = LSGetApplicationForURL(inURL, inRoleMask, NULL, &retval);

	if (status != noErr)
	{
		if (outError)
			*outError = CFErrorCreate(NULL, kCFErrorDomainOSStatus, status, NULL);
		return NULL;
	}
	else
	{
		if (outError)
			*outError = NULL;
		return retval;
	}
}

OSStatus LSGetApplicationForURL(CFURLRef inURL, LSRolesMask inRoleMask, FSRef *outAppRef, CFURLRef *outAppURL)
{
	NSString* extension = [(NSURL*) inURL pathExtension];
	return LSGetApplicationForInfo(kLSUnknownType, kLSUnknownCreator, (CFStringRef) extension, inRoleMask, outAppRef, outAppURL);
}

// The user's choices of handlers, like macOS keeps them: an LSHandlers array of
// { LSHandlerURLScheme or LSHandlerContentType, LSHandlerRole..., LSHandlerPreferredVersions }.
static CFStringRef const kLSHandlersDomain = CFSTR("com.apple.LaunchServices/com.apple.launchservices.secure");

static NSString* preferredHandler(NSString* key, NSString* value, NSString* roleKey)
{
	NSArray* handlers = [(NSArray*) CFPreferencesCopyAppValue(CFSTR("LSHandlers"), kLSHandlersDomain) autorelease];

	if (![handlers isKindOfClass: [NSArray class]])
		return nil;

	for (NSDictionary* handler in handlers)
	{
		if (![handler isKindOfClass: [NSDictionary class]])
			continue;
		if ([[handler objectForKey: key] caseInsensitiveCompare: value] != NSOrderedSame)
			continue;

		NSString* bundleID = [handler objectForKey: roleKey];
		if (bundleID == nil)
			bundleID = [handler objectForKey: @"LSHandlerRoleAll"];
		if ([bundleID isKindOfClass: [NSString class]] && ![bundleID isEqualToString: @"-"])
			return bundleID;
	}
	return nil;
}

static OSStatus setPreferredHandler(NSString* key, NSString* value, NSString* roleKey, NSString* bundleID)
{
	NSArray* handlers = [(NSArray*) CFPreferencesCopyAppValue(CFSTR("LSHandlers"), kLSHandlersDomain) autorelease];
	NSMutableArray* updated = [NSMutableArray array];

	if (value == nil || bundleID == nil)
		return paramErr;

	if ([handlers isKindOfClass: [NSArray class]])
	{
		for (NSDictionary* handler in handlers)
		{
			// replace this role's entry for the scheme or type
			if ([handler isKindOfClass: [NSDictionary class]] &&
				[[handler objectForKey: key] caseInsensitiveCompare: value] == NSOrderedSame &&
				[handler objectForKey: roleKey] != nil)
				continue;
			[updated addObject: handler];
		}
	}

	[updated addObject: @{ key: value, roleKey: bundleID, @"LSHandlerPreferredVersions": @{ roleKey: @"-" } }];
	CFPreferencesSetAppValue(CFSTR("LSHandlers"), (CFArrayRef) updated, kLSHandlersDomain);
	return CFPreferencesAppSynchronize(kLSHandlersDomain) ? noErr : kLSUnknownErr;
}

static NSString* roleKeyForMask(LSRolesMask role)
{
	if (role == kLSRolesViewer)
		return @"LSHandlerRoleViewer";
	if (role == kLSRolesEditor)
		return @"LSHandlerRoleEditor";
	if (role == kLSRolesShell)
		return @"LSHandlerRoleShell";
	return @"LSHandlerRoleAll";
}

CFArrayRef LSCopyAllHandlersForURLScheme(CFStringRef inURLScheme)
{
	__block NSMutableArray* handlers = nil;

	if (inURLScheme == NULL)
		return NULL;

	[getDatabaseQueue() inDatabase:^(FMDatabase* db) {
		FMResultSet* rs = [db executeQuery:@"select distinct B.bundle_id from bundle B "
			@"join bundle_url_type T on T.bundle = B.id "
			@"join bundle_url_type_scheme S on S.type = T.id "
			@"where B.package_type = 'APPL' and S.scheme = ? order by B.id", (NSString*) inURLScheme];

		while ([rs next])
		{
			if (handlers == nil)
				handlers = [[NSMutableArray alloc] init];
			[handlers addObject: [rs stringForColumn:@"bundle_id"]];
		}
		[rs close];
	}];

	return (CFArrayRef) handlers;
}

CFArrayRef LSCopyAllRoleHandlersForContentType(CFStringRef inContentType, LSRolesMask inRole)
{
	puts("LSCopyAllRoleHandlersForContentType STUB");
	// NULL is a safe assumption to fall back on in the stub, since it means none were found.
	return NULL;
}

CFStringRef LSCopyDefaultHandlerForURLScheme(CFStringRef inURLScheme)
{
	NSString* chosen;
	CFArrayRef all;
	CFStringRef first = NULL;

	if (inURLScheme == NULL)
		return NULL;

	chosen = preferredHandler(@"LSHandlerURLScheme", (NSString*) inURLScheme, @"LSHandlerRoleAll");
	if (chosen != nil)
		return (CFStringRef) [chosen copy];

	// otherwise the first application that says it handles the scheme
	all = LSCopyAllHandlersForURLScheme(inURLScheme);
	if (all != NULL)
	{
		if (CFArrayGetCount(all) > 0)
			first = CFStringCreateCopy(NULL, (CFStringRef) CFArrayGetValueAtIndex(all, 0));
		CFRelease(all);
	}
	return first;
}

OSStatus LSSetDefaultHandlerForURLScheme(CFStringRef inURLScheme, CFStringRef inHandlerBundleID)
{
	return setPreferredHandler(@"LSHandlerURLScheme", (NSString*) inURLScheme, @"LSHandlerRoleAll",
		(NSString*) inHandlerBundleID);
}

OSStatus LSSetDefaultRoleHandlerForContentType(CFStringRef inContentType, LSRolesMask inRole,
	CFStringRef inHandlerBundleID)
{
	return setPreferredHandler(@"LSHandlerContentType", (NSString*) inContentType, roleKeyForMask(inRole),
		(NSString*) inHandlerBundleID);
}
