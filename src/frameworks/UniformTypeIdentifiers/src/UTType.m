/*
 This file is part of Darling.

 Copyright (C) 2023 Darling Team

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

#import <UniformTypeIdentifiers/UTType.h>
#import <CoreServices/CoreServices.h>

// CoreServices exports this, but (like on macOS) no header declares it
extern CFArrayRef UTTypeCopyParentIdentifiers(CFStringRef inUTI);

@implementation UTType

- (instancetype)initWithIdentifier: (NSString *)identifier
{
	self = [super init];
	if (self != nil)
	{
		_identifier = [identifier copy];
	}
	return self;
}

- (void)dealloc
{
	[_identifier release];
	[super dealloc];
}

- (NSString *)identifier
{
	return _identifier;
}

- (NSString *)preferredFilenameExtension
{
	CFStringRef tag = UTTypeCopyPreferredTagWithClass((CFStringRef) _identifier, kUTTagClassFilenameExtension);
	return [(NSString *) tag autorelease];
}

- (NSString *)preferredMIMEType
{
	CFStringRef tag = UTTypeCopyPreferredTagWithClass((CFStringRef) _identifier, kUTTagClassMIMEType);
	return [(NSString *) tag autorelease];
}

- (NSString *)localizedDescription
{
	CFStringRef description = UTTypeCopyDescription((CFStringRef) _identifier);
	return [(NSString *) description autorelease];
}

- (NSNumber *)version
{
	return nil;
}

- (NSURL *)referenceURL
{
	return nil;
}

- (BOOL)isDynamic
{
	return UTTypeIsDynamic((CFStringRef) _identifier) ? YES : NO;
}

- (BOOL)isDeclared
{
	return UTTypeIsDeclared((CFStringRef) _identifier) ? YES : NO;
}

- (BOOL)isPublicType
{
	return _identifier != nil && [_identifier rangeOfString: @"public." options: NSCaseInsensitiveSearch].location == 0;
}

- (NSDictionary<NSString *, NSArray<NSString *> *> *)tags
{
	NSMutableDictionary* result = [NSMutableDictionary dictionary];
	CFDictionaryRef declaration = UTTypeCopyDeclaration((CFStringRef) _identifier);

	if (declaration != nil)
	{
		NSDictionary* specification = [(NSDictionary *) declaration objectForKey: (NSString *) kUTTypeTagSpecificationKey];

		for (NSString* tagClass in specification)
		{
			id value = [specification objectForKey: tagClass];

			if ([value isKindOfClass: [NSArray class]])
				[result setObject: value forKey: tagClass];
			else if (value != nil)
				[result setObject: [NSArray arrayWithObject: value] forKey: tagClass];
		}

		CFRelease(declaration);
	}

	// dynamic types (and declared types with no declaration) still report the tags encoded in
	// their identifier / available for the standard classes
	{
		NSArray* classes = [NSArray arrayWithObjects: UTTagClassFilenameExtension, UTTagClassMIMEType, nil];

		for (NSString* tagClass in classes)
		{
			if ([result objectForKey: tagClass] != nil)
				continue;

			CFArrayRef values = UTTypeCopyAllTagsWithClass((CFStringRef) _identifier, (CFStringRef) tagClass);
			if (values != nil)
			{
				if (CFArrayGetCount(values) > 0)
					[result setObject: [(NSArray *) values autorelease] forKey: tagClass];
				else
					CFRelease(values);
			}
		}
	}

	return result;
}

- (NSSet<UTType *> *)supertypes
{
	NSMutableSet* result = [NSMutableSet set];
	NSMutableArray* queue = [NSMutableArray array];
	NSMutableSet* seen = [NSMutableSet set];

	if (_identifier != nil)
	{
		[queue addObject: _identifier];
		[seen addObject: [_identifier lowercaseString]];
	}

	while ([queue count] > 0)
	{
		NSString* identifier = [[queue objectAtIndex: 0] retain];
		CFArrayRef parents;
		CFIndex i;

		[queue removeObjectAtIndex: 0];

		parents = UTTypeCopyParentIdentifiers((CFStringRef) identifier);
		[identifier release];

		if (parents == nil)
			continue;

		for (i = 0; i < CFArrayGetCount(parents); i++)
		{
			NSString* parent = (NSString *) CFArrayGetValueAtIndex(parents, i);
			NSString* key = [parent lowercaseString];

			if ([seen containsObject: key])
				continue;

			[seen addObject: key];
			[result addObject: [[[UTType alloc] initWithIdentifier: parent] autorelease]];
			[queue addObject: parent];
		}

		CFRelease(parents);
	}

	return result;
}

- (BOOL)conformsToType: (UTType *)type
{
	if (type == nil)
		return NO;

	return UTTypeConformsTo((CFStringRef) _identifier, (CFStringRef) type.identifier) ? YES : NO;
}

- (BOOL)isSupertypeOfType: (UTType *)type
{
	if (type == nil || [self isEqual: type])
		return NO;

	return UTTypeConformsTo((CFStringRef) type.identifier, (CFStringRef) _identifier) ? YES : NO;
}

- (BOOL)isSubtypeOfType: (UTType *)type
{
	if (type == nil || [self isEqual: type])
		return NO;

	return UTTypeConformsTo((CFStringRef) _identifier, (CFStringRef) type.identifier) ? YES : NO;
}

- (BOOL)isEqual: (id)object
{
	if (object == self)
		return YES;
	if (![object isKindOfClass: [UTType class]])
		return NO;

	return [self.identifier caseInsensitiveCompare: ((UTType *) object).identifier] == NSOrderedSame;
}

- (NSUInteger)hash
{
	return [[_identifier lowercaseString] hash];
}

- (id)copyWithZone: (NSZone *)zone
{
	return [self retain];
}

+ (BOOL)supportsSecureCoding
{
	return YES;
}

- (void)encodeWithCoder: (NSCoder *)coder
{
	[coder encodeObject: _identifier forKey: @"NSIdentifier"];
}

- (instancetype)initWithCoder: (NSCoder *)coder
{
	NSString* identifier = [coder decodeObjectOfClass: [NSString class] forKey: @"NSIdentifier"];

	if (identifier == nil)
	{
		[self release];
		return nil;
	}

	return [self initWithIdentifier: identifier];
}

+ (nullable instancetype)typeFromCreatedIdentifier: (CFStringRef)identifier
{
	UTType* result;

	if (identifier == NULL)
		return nil;

	result = [[[self alloc] initWithIdentifier: (NSString *) identifier] autorelease];
	CFRelease(identifier);

	return result;
}

+ (nullable instancetype)typeWithIdentifier: (NSString *)identifier
{
	if (identifier == nil)
		return nil;

	if (UTTypeIsDynamic((CFStringRef) identifier) || UTTypeIsDeclared((CFStringRef) identifier))
		return [[[self alloc] initWithIdentifier: identifier] autorelease];

	return nil;
}

+ (nullable instancetype)typeWithFilenameExtension: (NSString *)filenameExtension
{
	return [self typeFromCreatedIdentifier: UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (CFStringRef) filenameExtension, NULL)];
}

+ (nullable instancetype)typeWithFilenameExtension: (NSString *)filenameExtension conformingToType: (UTType *)supertype
{
	return [self typeFromCreatedIdentifier: UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (CFStringRef) filenameExtension, supertype != nil ? (CFStringRef) supertype.identifier : NULL)];
}

+ (nullable instancetype)typeWithMIMEType: (NSString *)mimeType
{
	return [self typeFromCreatedIdentifier: UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, (CFStringRef) mimeType, NULL)];
}

+ (nullable instancetype)typeWithMIMEType: (NSString *)mimeType conformingToType: (UTType *)supertype
{
	return [self typeFromCreatedIdentifier: UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, (CFStringRef) mimeType, supertype != nil ? (CFStringRef) supertype.identifier : NULL)];
}

+ (nullable instancetype)typeWithTag: (NSString *)tag tagClass: (NSString *)tagClass conformingToType: (UTType *)supertype
{
	if (tag == nil || tagClass == nil)
		return nil;

	return [self typeFromCreatedIdentifier: UTTypeCreatePreferredIdentifierForTag((CFStringRef) tagClass, (CFStringRef) tag, supertype != nil ? (CFStringRef) supertype.identifier : NULL)];
}

+ (NSArray<UTType *> *)typesWithTag: (NSString *)tag tagClass: (NSString *)tagClass conformingToType: (UTType *)supertype
{
	NSMutableArray* result = [NSMutableArray array];
	CFArrayRef identifiers;

	if (tag == nil || tagClass == nil)
		return result;

	identifiers = UTTypeCreateAllIdentifiersForTag((CFStringRef) tagClass, (CFStringRef) tag, supertype != nil ? (CFStringRef) supertype.identifier : NULL);

	if (identifiers != nil)
	{
		CFIndex i;

		for (i = 0; i < CFArrayGetCount(identifiers); i++)
		{
			NSString* identifier = (NSString *) CFArrayGetValueAtIndex(identifiers, i);
			[result addObject: [[[UTType alloc] initWithIdentifier: identifier] autorelease]];
		}

		CFRelease(identifiers);
	}

	return result;
}

+ (nullable instancetype)exportedTypeWithIdentifier: (NSString *)identifier
{
	if (identifier == nil)
		return nil;

	if (UTTypeIsDeclared((CFStringRef) identifier))
		return [self typeWithIdentifier: identifier];

	return [[[self alloc] initWithIdentifier: identifier] autorelease];
}

+ (nullable instancetype)exportedTypeWithIdentifier: (NSString *)identifier conformingToType: (UTType *)supertype
{
	(void) supertype;
	return [self exportedTypeWithIdentifier: identifier];
}

+ (nullable instancetype)importedTypeWithIdentifier: (NSString *)identifier
{
	if (identifier == nil)
		return nil;

	if (UTTypeIsDeclared((CFStringRef) identifier))
		return [self typeWithIdentifier: identifier];

	return [[[self alloc] initWithIdentifier: identifier] autorelease];
}

+ (nullable instancetype)importedTypeWithIdentifier: (NSString *)identifier conformingToType: (UTType *)supertype
{
	(void) supertype;
	return [self importedTypeWithIdentifier: identifier];
}

@end

// used by the UTType* constant initializer (see UniformTypeIdentifiers.m)
UTType *UTTypeCreateInternal(NSString *identifier)
{
	return [[UTType alloc] initWithIdentifier: identifier];
}