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

#ifndef _UNIFORMTYPEIDENTIFIERS_H_
#define _UNIFORMTYPEIDENTIFIERS_H_

#import <Foundation/Foundation.h>

#import <UniformTypeIdentifiers/NSItemProvider+UTType.h>
#import <UniformTypeIdentifiers/NSString+UTAdditions.h>
#import <UniformTypeIdentifiers/NSURL+UTAdditions.h>
#import <UniformTypeIdentifiers/UTType.h>

// C++ typeinfo names that some binaries resolve through this framework
extern void* const _ZTSSt11logic_error;
extern void* const _ZTSSt12length_error;
extern void* const _ZTSSt19bad_optional_access;
extern void* const _ZTSSt20bad_array_new_length;
extern void* const _ZTSSt9bad_alloc;
extern void* const _ZTSSt9exception;

#endif