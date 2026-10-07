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

#ifndef UNIFORMTYPEIDENTIFIERS_UTTYPE_H
#define UNIFORMTYPEIDENTIFIERS_UTTYPE_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface UTType : NSObject <NSCopying, NSSecureCoding> {
    NSString *_identifier;
}

@property (readonly, copy) NSString *identifier;
@property (readonly, nullable, copy) NSString *preferredFilenameExtension;
@property (readonly, nullable, copy) NSString *preferredMIMEType;
@property (readonly, nullable, copy) NSString *localizedDescription;
@property (readonly, nullable, copy) NSNumber *version;
@property (readonly, nullable, strong) NSURL *referenceURL;
@property (readonly, getter=isDynamic) BOOL dynamic;
@property (readonly, getter=isDeclared) BOOL declared;
@property (readonly, getter=isPublicType) BOOL publicType;
@property (readonly, copy) NSDictionary<NSString *, NSArray<NSString *> *> *tags;
@property (readonly, copy) NSSet<UTType *> *supertypes;

- (void)encodeWithCoder: (NSCoder *)coder;
- (instancetype)initWithCoder: (NSCoder *)coder;

+ (nullable instancetype)typeWithIdentifier: (NSString *)identifier;
+ (nullable instancetype)typeWithFilenameExtension: (NSString *)filenameExtension;
+ (nullable instancetype)typeWithFilenameExtension: (NSString *)filenameExtension conformingToType: (nullable UTType *)supertype;
+ (nullable instancetype)typeWithMIMEType: (NSString *)mimeType;
+ (nullable instancetype)typeWithMIMEType: (NSString *)mimeType conformingToType: (nullable UTType *)supertype;
+ (nullable instancetype)typeWithTag: (NSString *)tag tagClass: (NSString *)tagClass conformingToType: (nullable UTType *)supertype;
+ (NSArray<UTType *> *)typesWithTag: (NSString *)tag tagClass: (NSString *)tagClass conformingToType: (nullable UTType *)supertype;

+ (nullable instancetype)exportedTypeWithIdentifier: (NSString *)identifier;
+ (nullable instancetype)exportedTypeWithIdentifier: (NSString *)identifier conformingToType: (UTType *)supertype;
+ (nullable instancetype)importedTypeWithIdentifier: (NSString *)identifier;
+ (nullable instancetype)importedTypeWithIdentifier: (NSString *)identifier conformingToType: (UTType *)supertype;

- (BOOL)conformsToType: (UTType *)type;
- (BOOL)isSupertypeOfType: (UTType *)type;
- (BOOL)isSubtypeOfType: (UTType *)type;

@end

extern NSString * const UTTagClassFilenameExtension;
extern NSString * const UTTagClassMIMEType;

extern UTType * const UTType3DContent;
extern UTType * const UTTypeAIFF;
extern UTType * const UTTypeARReferenceObject;
extern UTType * const UTTypeAVI;
extern UTType * const UTTypeAliasFile;
extern UTType * const UTTypeAppleArchive;
extern UTType * const UTTypeAppleProtectedMPEG4Audio;
extern UTType * const UTTypeAppleProtectedMPEG4Video;
extern UTType * const UTTypeAppleScript;
extern UTType * const UTTypeApplication;
extern UTType * const UTTypeApplicationBundle;
extern UTType * const UTTypeApplicationExtension;
extern UTType * const UTTypeArchive;
extern UTType * const UTTypeAssemblyLanguageSource;
extern UTType * const UTTypeAudio;
extern UTType * const UTTypeAudiovisualContent;
extern UTType * const UTTypeBMP;
extern UTType * const UTTypeBZ2;
extern UTType * const UTTypeBinaryPropertyList;
extern UTType * const UTTypeBookmark;
extern UTType * const UTTypeBundle;
extern UTType * const UTTypeCHeader;
extern UTType * const UTTypeCPlusPlusHeader;
extern UTType * const UTTypeCPlusPlusSource;
extern UTType * const UTTypeCSource;
extern UTType * const UTTypeCalendarEvent;
extern UTType * const UTTypeCommaSeparatedText;
extern UTType * const UTTypeCompositeContent;
extern UTType * const UTTypeContact;
extern UTType * const UTTypeContent;
extern UTType * const UTTypeData;
extern UTType * const UTTypeDatabase;
extern UTType * const UTTypeDelimitedText;
extern UTType * const UTTypeDirectory;
extern UTType * const UTTypeDiskImage;
extern UTType * const UTTypeEPUB;
extern UTType * const UTTypeEXE;
extern UTType * const UTTypeEmailMessage;
extern UTType * const UTTypeExecutable;
extern UTType * const UTTypeFileURL;
extern UTType * const UTTypeFlatRTFD;
extern UTType * const UTTypeFolder;
extern UTType * const UTTypeFont;
extern UTType * const UTTypeFramework;
extern UTType * const UTTypeGIF;
extern UTType * const UTTypeGZIP;
extern UTType * const UTTypeHEIC;
extern UTType * const UTTypeHEIF;
extern UTType * const UTTypeHTML;
extern UTType * const UTTypeICNS;
extern UTType * const UTTypeICO;
extern UTType * const UTTypeImage;
extern UTType * const UTTypeInternetLocation;
extern UTType * const UTTypeInternetShortcut;
extern UTType * const UTTypeItem;
extern UTType * const UTTypeJPEG;
extern UTType * const UTTypeJSON;
extern UTType * const UTTypeJavaScript;
extern UTType * const UTTypeLivePhoto;
extern UTType * const UTTypeLog;
extern UTType * const UTTypeM3UPlaylist;
extern UTType * const UTTypeMIDI;
extern UTType * const UTTypeMP3;
extern UTType * const UTTypeMPEG;
extern UTType * const UTTypeMPEG2TransportStream;
extern UTType * const UTTypeMPEG2Video;
extern UTType * const UTTypeMPEG4Audio;
extern UTType * const UTTypeMPEG4Movie;
extern UTType * const UTTypeMakefile;
extern UTType * const UTTypeMessage;
extern UTType * const UTTypeMountPoint;
extern UTType * const UTTypeMovie;
extern UTType * const UTTypeOSAScript;
extern UTType * const UTTypeOSAScriptBundle;
extern UTType * const UTTypeObjectiveCPlusPlusSource;
extern UTType * const UTTypeObjectiveCSource;
extern UTType * const UTTypePDF;
extern UTType * const UTTypePHPScript;
extern UTType * const UTTypePKCS12;
extern UTType * const UTTypePNG;
extern UTType * const UTTypePackage;
extern UTType * const UTTypePerlScript;
extern UTType * const UTTypePlainText;
extern UTType * const UTTypePlaylist;
extern UTType * const UTTypePluginBundle;
extern UTType * const UTTypePresentation;
extern UTType * const UTTypePropertyList;
extern UTType * const UTTypePythonScript;
extern UTType * const UTTypeQuickLookGenerator;
extern UTType * const UTTypeQuickTimeMovie;
extern UTType * const UTTypeRAWImage;
extern UTType * const UTTypeRTF;
extern UTType * const UTTypeRTFD;
extern UTType * const UTTypeRealityFile;
extern UTType * const UTTypeResolvable;
extern UTType * const UTTypeRubyScript;
extern UTType * const UTTypeSVG;
extern UTType * const UTTypeSceneKitScene;
extern UTType * const UTTypeScript;
extern UTType * const UTTypeShellScript;
extern UTType * const UTTypeSourceCode;
extern UTType * const UTTypeSpotlightImporter;
extern UTType * const UTTypeSpreadsheet;
extern UTType * const UTTypeSwiftSource;
extern UTType * const UTTypeSymbolicLink;
extern UTType * const UTTypeSystemPreferencesPane;
extern UTType * const UTTypeTIFF;
extern UTType * const UTTypeTabSeparatedText;
extern UTType * const UTTypeText;
extern UTType * const UTTypeToDoItem;
extern UTType * const UTTypeURL;
extern UTType * const UTTypeURLBookmarkData;
extern UTType * const UTTypeUSD;
extern UTType * const UTTypeUSDZ;
extern UTType * const UTTypeUTF16ExternalPlainText;
extern UTType * const UTTypeUTF16PlainText;
extern UTType * const UTTypeUTF8PlainText;
extern UTType * const UTTypeUTF8TabSeparatedText;
extern UTType * const UTTypeUnixExecutable;
extern UTType * const UTTypeVCard;
extern UTType * const UTTypeVideo;
extern UTType * const UTTypeVolume;
extern UTType * const UTTypeWAV;
extern UTType * const UTTypeWebArchive;
extern UTType * const UTTypeWebP;
extern UTType * const UTTypeX509Certificate;
extern UTType * const UTTypeXML;
extern UTType * const UTTypeXMLPropertyList;
extern UTType * const UTTypeXPCService;
extern UTType * const UTTypeYAML;
extern UTType * const UTTypeZIP;

extern UTType * const _UTTagClassBluetoothVendorProductID;
extern UTType * const _UTTagClassDeviceModelCode;
extern UTType * const _UTTagClassHFSTypeCode;
extern UTType * const _UTTagClassPasteboardType;
extern UTType * const _UTTypeAppCategory;
extern UTType * const _UTTypeAppCategoryActionGames;
extern UTType * const _UTTypeAppCategoryAdventureGames;
extern UTType * const _UTTypeAppCategoryArcadeGames;
extern UTType * const _UTTypeAppCategoryBoardGames;
extern UTType * const _UTTypeAppCategoryBookmarks;
extern UTType * const _UTTypeAppCategoryBooks;
extern UTType * const _UTTypeAppCategoryBusiness;
extern UTType * const _UTTypeAppCategoryCardGames;
extern UTType * const _UTTypeAppCategoryCasinoGames;
extern UTType * const _UTTypeAppCategoryDeveloperTools;
extern UTType * const _UTTypeAppCategoryDiceGames;
extern UTType * const _UTTypeAppCategoryEducation;
extern UTType * const _UTTypeAppCategoryEducationalGames;
extern UTType * const _UTTypeAppCategoryEntertainment;
extern UTType * const _UTTypeAppCategoryFamilyGames;
extern UTType * const _UTTypeAppCategoryFinance;
extern UTType * const _UTTypeAppCategoryFoodAndDrink;
extern UTType * const _UTTypeAppCategoryGames;
extern UTType * const _UTTypeAppCategoryGraphicsDesign;
extern UTType * const _UTTypeAppCategoryHealthcareFitness;
extern UTType * const _UTTypeAppCategoryKidsGames;
extern UTType * const _UTTypeAppCategoryLifestyle;
extern UTType * const _UTTypeAppCategoryMagazinesAndNewspapers;
extern UTType * const _UTTypeAppCategoryMedical;
extern UTType * const _UTTypeAppCategoryMusic;
extern UTType * const _UTTypeAppCategoryMusicGames;
extern UTType * const _UTTypeAppCategoryNavigation;
extern UTType * const _UTTypeAppCategoryNews;
extern UTType * const _UTTypeAppCategoryPhotoAndVideo;
extern UTType * const _UTTypeAppCategoryPhotography;
extern UTType * const _UTTypeAppCategoryProductivity;
extern UTType * const _UTTypeAppCategoryPuzzleGames;
extern UTType * const _UTTypeAppCategoryRacingGames;
extern UTType * const _UTTypeAppCategoryReference;
extern UTType * const _UTTypeAppCategoryRolePlayingGames;
extern UTType * const _UTTypeAppCategoryShopping;
extern UTType * const _UTTypeAppCategorySimulationGames;
extern UTType * const _UTTypeAppCategorySocialNetworking;
extern UTType * const _UTTypeAppCategorySports;
extern UTType * const _UTTypeAppCategorySportsGames;
extern UTType * const _UTTypeAppCategoryStrategyGames;
extern UTType * const _UTTypeAppCategoryTravel;
extern UTType * const _UTTypeAppCategoryTriviaGames;
extern UTType * const _UTTypeAppCategoryUtilities;
extern UTType * const _UTTypeAppCategoryVideo;
extern UTType * const _UTTypeAppCategoryWeather;
extern UTType * const _UTTypeAppCategoryWordGames;
extern UTType * const _UTTypeAppleDevice;
extern UTType * const _UTTypeAppleEncryptedArchive;
extern UTType * const _UTTypeAppleTV;
extern UTType * const _UTTypeAppleWatch;
extern UTType * const _UTTypeApplicationsFolder;
extern UTType * const _UTTypeBlockSpecial;
extern UTType * const _UTTypeCharacterSpecial;
extern UTType * const _UTTypeComputer;
extern UTType * const _UTTypeDataContainer;
extern UTType * const _UTTypeDevice;
extern UTType * const _UTTypeDisplay;
extern UTType * const _UTTypeDropFolder;
extern UTType * const _UTTypeGenericPC;
extern UTType * const _UTTypeHEIFStandard;
extern UTType * const _UTTypeHomePod;
extern UTType * const _UTTypeLibraryFolder;
extern UTType * const _UTTypeMac;
extern UTType * const _UTTypeMacBook;
extern UTType * const _UTTypeMacBookAir;
extern UTType * const _UTTypeMacBookPro;
extern UTType * const _UTTypeMacLaptop;
extern UTType * const _UTTypeMacMini;
extern UTType * const _UTTypeMacPro;
extern UTType * const _UTTypeNamedPipeOrFIFO;
extern UTType * const _UTTypeNetworkNeighborhood;
extern UTType * const _UTTypePassBundle;
extern UTType * const _UTTypePassData;
extern UTType * const _UTTypePassesData;
extern UTType * const _UTTypeServersFolder;
extern UTType * const _UTTypeSocket;
extern UTType * const _UTTypeSpeaker;
extern UTType * const _UTTypeiMac;
extern UTType * const _UTTypeiOSDevice;
extern UTType * const _UTTypeiOSSimulator;
extern UTType * const _UTTypeiPad;
extern UTType * const _UTTypeiPhone;
extern UTType * const _UTTypeiPodTouch;

NS_ASSUME_NONNULL_END

#endif