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

#import <UniformTypeIdentifiers/NSURL+UTAdditions.h>
#import <UniformTypeIdentifiers/NSString+UTAdditions.h>

@implementation NSURL (UTAdditions)

- (NSURL *)URLByAppendingPathComponent: (NSString *)partialName conformingToType: (UTType *)contentType
{
	NSString* path = [self path];

	if (path == nil)
		return self;

	return [NSURL fileURLWithPath: [path stringByAppendingPathComponent: partialName conformingToType: contentType]];
}

- (NSURL *)URLByAppendingPathExtensionForType: (UTType *)contentType
{
	NSString* path = [self path];

	if (path == nil)
		return self;

	return [NSURL fileURLWithPath: [path stringByAppendingPathExtensionForType: contentType]];
}

@end