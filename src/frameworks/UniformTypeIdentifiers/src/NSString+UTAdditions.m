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

#import <UniformTypeIdentifiers/NSString+UTAdditions.h>
#import <UniformTypeIdentifiers/UTType.h>

@implementation NSString (UTAdditions)

- (NSString *)stringByAppendingPathComponent: (NSString *)partialName conformingToType: (UTType *)contentType
{
	NSString* result = [self stringByAppendingPathComponent: partialName];

	if ([[result pathExtension] length] == 0)
	{
		NSString* extension = [contentType preferredFilenameExtension];

		if ([extension length] > 0)
			result = [result stringByAppendingPathExtension: extension];
	}

	return result;
}

- (NSString *)stringByAppendingPathExtensionForType: (UTType *)contentType
{
	NSString* extension = [contentType preferredFilenameExtension];

	if ([extension length] == 0)
		return self;

	return [self stringByAppendingPathExtension: extension];
}

@end