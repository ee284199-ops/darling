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

#import <Foundation/Foundation.h>

// implemented in UTType.m
@class UTType;
extern UTType *UTTypeCreateInternal(NSString *identifier);

//
// The public header declares these as `UTType * const`, but they have to be
// filled in at load time, so they are defined non-const here. Constness is a
// compile-time property and does not affect the exported symbol.
//

#define UT_TYPE_CONSTANTS(X) \
	X(UTType3DContent, "public.3d-content") \
	X(UTTypeAIFF, "public.aiff-audio") \
	X(UTTypeARReferenceObject, "com.apple.ar-reference-object") \
	X(UTTypeAVI, "public.avi") \
	X(UTTypeAliasFile, "com.apple.alias-file") \
	X(UTTypeAppleArchive, "com.apple.archive") \
	X(UTTypeAppleProtectedMPEG4Audio, "com.apple.protected-mpeg-4-audio") \
	X(UTTypeAppleProtectedMPEG4Video, "com.apple.protected-mpeg-4-video") \
	X(UTTypeAppleScript, "com.apple.applescript.text") \
	X(UTTypeApplication, "com.apple.application") \
	X(UTTypeApplicationBundle, "com.apple.application-bundle") \
	X(UTTypeApplicationExtension, "com.apple.application-extension") \
	X(UTTypeArchive, "public.archive") \
	X(UTTypeAssemblyLanguageSource, "public.assembly-source") \
	X(UTTypeAudio, "public.audio") \
	X(UTTypeAudiovisualContent, "public.audiovisual-content") \
	X(UTTypeBMP, "com.microsoft.bmp") \
	X(UTTypeBZ2, "public.bzip2-archive") \
	X(UTTypeBinaryPropertyList, "com.apple.binary-property-list") \
	X(UTTypeBookmark, "public.bookmark") \
	X(UTTypeBundle, "com.apple.bundle") \
	X(UTTypeCHeader, "public.c-header") \
	X(UTTypeCPlusPlusHeader, "public.c-plus-plus-header") \
	X(UTTypeCPlusPlusSource, "public.c-plus-plus-source") \
	X(UTTypeCSource, "public.c-source") \
	X(UTTypeCalendarEvent, "public.calendar-event") \
	X(UTTypeCommaSeparatedText, "public.comma-separated-values-text") \
	X(UTTypeCompositeContent, "public.composite-content") \
	X(UTTypeContact, "public.contact") \
	X(UTTypeContent, "public.content") \
	X(UTTypeData, "public.data") \
	X(UTTypeDatabase, "public.database") \
	X(UTTypeDelimitedText, "public.delimited-values-text") \
	X(UTTypeDirectory, "public.directory") \
	X(UTTypeDiskImage, "public.disk-image") \
	X(UTTypeEPUB, "org.idpf.epub-container") \
	X(UTTypeEXE, "com.microsoft.windows-executable") \
	X(UTTypeEmailMessage, "public.email-message") \
	X(UTTypeExecutable, "public.executable") \
	X(UTTypeFileURL, "public.file-url") \
	X(UTTypeFlatRTFD, "com.apple.flat-rtfd") \
	X(UTTypeFolder, "public.folder") \
	X(UTTypeFont, "public.font") \
	X(UTTypeFramework, "com.apple.framework") \
	X(UTTypeGIF, "com.compuserve.gif") \
	X(UTTypeGZIP, "org.gnu.gnu-zip-archive") \
	X(UTTypeHEIC, "public.heic") \
	X(UTTypeHEIF, "public.heif") \
	X(UTTypeHTML, "public.html") \
	X(UTTypeICNS, "com.apple.icns") \
	X(UTTypeICO, "com.microsoft.ico") \
	X(UTTypeImage, "public.image") \
	X(UTTypeInternetLocation, "com.apple.internet-location") \
	X(UTTypeInternetShortcut, "com.apple.internet-shortcut") \
	X(UTTypeItem, "public.item") \
	X(UTTypeJPEG, "public.jpeg") \
	X(UTTypeJSON, "public.json") \
	X(UTTypeJavaScript, "com.netscape.javascript-source") \
	X(UTTypeLivePhoto, "com.apple.live-photo") \
	X(UTTypeLog, "public.log") \
	X(UTTypeM3UPlaylist, "public.m3u-playlist") \
	X(UTTypeMIDI, "public.midi-audio") \
	X(UTTypeMP3, "public.mp3") \
	X(UTTypeMPEG, "public.mpeg") \
	X(UTTypeMPEG2TransportStream, "public.mpeg-2-transport-stream") \
	X(UTTypeMPEG2Video, "public.mpeg-2-video") \
	X(UTTypeMPEG4Audio, "public.mpeg-4-audio") \
	X(UTTypeMPEG4Movie, "public.mpeg-4") \
	X(UTTypeMakefile, "public.make-source") \
	X(UTTypeMessage, "public.message") \
	X(UTTypeMountPoint, "com.apple.mount-point") \
	X(UTTypeMovie, "public.movie") \
	X(UTTypeOSAScript, "com.apple.applescript.script") \
	X(UTTypeOSAScriptBundle, "com.apple.applescript.script-bundle") \
	X(UTTypeObjectiveCPlusPlusSource, "public.objective-c-plus-plus-source") \
	X(UTTypeObjectiveCSource, "public.objective-c-source") \
	X(UTTypePDF, "com.adobe.pdf") \
	X(UTTypePHPScript, "public.php-script") \
	X(UTTypePKCS12, "com.rsa.pkcs-12") \
	X(UTTypePNG, "public.png") \
	X(UTTypePackage, "com.apple.package") \
	X(UTTypePerlScript, "public.perl-script") \
	X(UTTypePlainText, "public.plain-text") \
	X(UTTypePlaylist, "public.playlist") \
	X(UTTypePluginBundle, "com.apple.plugin") \
	X(UTTypePresentation, "public.presentation") \
	X(UTTypePropertyList, "com.apple.property-list") \
	X(UTTypePythonScript, "public.python-script") \
	X(UTTypeQuickLookGenerator, "com.apple.quicklook-generator") \
	X(UTTypeQuickTimeMovie, "com.apple.quicktime-movie") \
	X(UTTypeRAWImage, "public.camera-raw-image") \
	X(UTTypeRTF, "public.rtf") \
	X(UTTypeRTFD, "com.apple.rtfd") \
	X(UTTypeRealityFile, "com.apple.reality") \
	X(UTTypeResolvable, "com.apple.resolvable") \
	X(UTTypeRubyScript, "public.ruby-script") \
	X(UTTypeSVG, "public.svg-image") \
	X(UTTypeSceneKitScene, "com.apple.scenekit.scene") \
	X(UTTypeScript, "public.script") \
	X(UTTypeShellScript, "public.shell-script") \
	X(UTTypeSourceCode, "public.source-code") \
	X(UTTypeSpotlightImporter, "com.apple.metadata-importer") \
	X(UTTypeSpreadsheet, "public.spreadsheet") \
	X(UTTypeSwiftSource, "public.swift-source") \
	X(UTTypeSymbolicLink, "public.symlink") \
	X(UTTypeSystemPreferencesPane, "com.apple.systempreference.prefpane") \
	X(UTTypeTIFF, "public.tiff") \
	X(UTTypeTabSeparatedText, "public.tab-separated-values-text") \
	X(UTTypeText, "public.text") \
	X(UTTypeToDoItem, "public.to-do-item") \
	X(UTTypeURL, "public.url") \
	X(UTTypeURLBookmarkData, "com.apple.bookmark") \
	X(UTTypeUSD, "com.pixar.universal-scene-description") \
	X(UTTypeUSDZ, "com.pixar.universal-scene-description-mobile") \
	X(UTTypeUTF16ExternalPlainText, "public.utf16-external-plain-text") \
	X(UTTypeUTF16PlainText, "public.utf16-plain-text") \
	X(UTTypeUTF8PlainText, "public.utf8-plain-text") \
	X(UTTypeUTF8TabSeparatedText, "public.utf8-tab-separated-values-text") \
	X(UTTypeUnixExecutable, "public.unix-executable") \
	X(UTTypeVCard, "public.vcard") \
	X(UTTypeVideo, "public.video") \
	X(UTTypeVolume, "public.volume") \
	X(UTTypeWAV, "com.microsoft.waveform-audio") \
	X(UTTypeWebArchive, "com.apple.webarchive") \
	X(UTTypeWebP, "org.webmproject.webp") \
	X(UTTypeX509Certificate, "public.x509-certificate") \
	X(UTTypeXML, "public.xml") \
	X(UTTypeXMLPropertyList, "com.apple.xml-property-list") \
	X(UTTypeXPCService, "com.apple.xpc-service") \
	X(UTTypeYAML, "public.yaml") \
	X(UTTypeZIP, "public.zip-archive") \
	X(_UTTagClassBluetoothVendorProductID, "public.bluetooth-vendor-product-id") \
	X(_UTTagClassDeviceModelCode, "com.apple.device-model-code") \
	X(_UTTagClassHFSTypeCode, "com.apple.ostype") \
	X(_UTTagClassPasteboardType, "com.apple.nspboard-type") \
	X(_UTTypeAppCategory, "public.app-category") \
	X(_UTTypeAppCategoryActionGames, "public.app-category.action-games") \
	X(_UTTypeAppCategoryAdventureGames, "public.app-category.adventure-games") \
	X(_UTTypeAppCategoryArcadeGames, "public.app-category.arcade-games") \
	X(_UTTypeAppCategoryBoardGames, "public.app-category.board-games") \
	X(_UTTypeAppCategoryBookmarks, "public.app-category.bookmarks") \
	X(_UTTypeAppCategoryBooks, "public.app-category.books") \
	X(_UTTypeAppCategoryBusiness, "public.app-category.business") \
	X(_UTTypeAppCategoryCardGames, "public.app-category.card-games") \
	X(_UTTypeAppCategoryCasinoGames, "public.app-category.casino-games") \
	X(_UTTypeAppCategoryDeveloperTools, "public.app-category.developer-tools") \
	X(_UTTypeAppCategoryDiceGames, "public.app-category.dice-games") \
	X(_UTTypeAppCategoryEducation, "public.app-category.education") \
	X(_UTTypeAppCategoryEducationalGames, "public.app-category.educational-games") \
	X(_UTTypeAppCategoryEntertainment, "public.app-category.entertainment") \
	X(_UTTypeAppCategoryFamilyGames, "public.app-category.family-games") \
	X(_UTTypeAppCategoryFinance, "public.app-category.finance") \
	X(_UTTypeAppCategoryFoodAndDrink, "public.app-category.food-and-drink") \
	X(_UTTypeAppCategoryGames, "public.app-category.games") \
	X(_UTTypeAppCategoryGraphicsDesign, "public.app-category.graphics-design") \
	X(_UTTypeAppCategoryHealthcareFitness, "public.app-category.healthcare-fitness") \
	X(_UTTypeAppCategoryKidsGames, "public.app-category.kids-games") \
	X(_UTTypeAppCategoryLifestyle, "public.app-category.lifestyle") \
	X(_UTTypeAppCategoryMagazinesAndNewspapers, "public.app-category.magazines-and-newspapers") \
	X(_UTTypeAppCategoryMedical, "public.app-category.medical") \
	X(_UTTypeAppCategoryMusic, "public.app-category.music") \
	X(_UTTypeAppCategoryMusicGames, "public.app-category.music-games") \
	X(_UTTypeAppCategoryNavigation, "public.app-category.navigation") \
	X(_UTTypeAppCategoryNews, "public.app-category.news") \
	X(_UTTypeAppCategoryPhotoAndVideo, "public.app-category.photo-and-video") \
	X(_UTTypeAppCategoryPhotography, "public.app-category.photography") \
	X(_UTTypeAppCategoryProductivity, "public.app-category.productivity") \
	X(_UTTypeAppCategoryPuzzleGames, "public.app-category.puzzle-games") \
	X(_UTTypeAppCategoryRacingGames, "public.app-category.racing-games") \
	X(_UTTypeAppCategoryReference, "public.app-category.reference") \
	X(_UTTypeAppCategoryRolePlayingGames, "public.app-category.role-playing-games") \
	X(_UTTypeAppCategoryShopping, "public.app-category.shopping") \
	X(_UTTypeAppCategorySimulationGames, "public.app-category.simulation-games") \
	X(_UTTypeAppCategorySocialNetworking, "public.app-category.social-networking") \
	X(_UTTypeAppCategorySports, "public.app-category.sports") \
	X(_UTTypeAppCategorySportsGames, "public.app-category.sports-games") \
	X(_UTTypeAppCategoryStrategyGames, "public.app-category.strategy-games") \
	X(_UTTypeAppCategoryTravel, "public.app-category.travel") \
	X(_UTTypeAppCategoryTriviaGames, "public.app-category.trivia-games") \
	X(_UTTypeAppCategoryUtilities, "public.app-category.utilities") \
	X(_UTTypeAppCategoryVideo, "public.app-category.video") \
	X(_UTTypeAppCategoryWeather, "public.app-category.weather") \
	X(_UTTypeAppCategoryWordGames, "public.app-category.word-games") \
	X(_UTTypeAppleDevice, "com.apple.apple-device") \
	X(_UTTypeAppleEncryptedArchive, "com.apple.encrypted-archive") \
	X(_UTTypeAppleTV, "com.apple.apple-tv") \
	X(_UTTypeAppleWatch, "com.apple.apple-watch") \
	X(_UTTypeApplicationsFolder, "com.apple.applications-folder") \
	X(_UTTypeBlockSpecial, "public.block-special") \
	X(_UTTypeCharacterSpecial, "public.character-special") \
	X(_UTTypeComputer, "com.apple.computer") \
	X(_UTTypeDataContainer, "com.apple.data-container") \
	X(_UTTypeDevice, "public.device") \
	X(_UTTypeDisplay, "com.apple.display") \
	X(_UTTypeDropFolder, "com.apple.drop-folder") \
	X(_UTTypeGenericPC, "com.apple.generic-pc") \
	X(_UTTypeHEIFStandard, "public.heif-standard") \
	X(_UTTypeHomePod, "com.apple.homepod") \
	X(_UTTypeLibraryFolder, "com.apple.library-folder") \
	X(_UTTypeMac, "com.apple.mac") \
	X(_UTTypeMacBook, "com.apple.macbook") \
	X(_UTTypeMacBookAir, "com.apple.macbook-air") \
	X(_UTTypeMacBookPro, "com.apple.macbook-pro") \
	X(_UTTypeMacLaptop, "com.apple.mac-laptop") \
	X(_UTTypeMacMini, "com.apple.mac-mini") \
	X(_UTTypeMacPro, "com.apple.mac-pro") \
	X(_UTTypeNamedPipeOrFIFO, "public.named-pipe-or-fifo") \
	X(_UTTypeNetworkNeighborhood, "com.apple.network-neighborhood") \
	X(_UTTypePassBundle, "com.apple.pass-bundle") \
	X(_UTTypePassData, "com.apple.pass-data") \
	X(_UTTypePassesData, "com.apple.passes-data") \
	X(_UTTypeServersFolder, "com.apple.servers-folder") \
	X(_UTTypeSocket, "public.socket") \
	X(_UTTypeSpeaker, "com.apple.speaker") \
	X(_UTTypeiMac, "com.apple.imac") \
	X(_UTTypeiOSDevice, "com.apple.ios-device") \
	X(_UTTypeiOSSimulator, "com.apple.ios-simulator") \
	X(_UTTypeiPad, "com.apple.ipad") \
	X(_UTTypeiPhone, "com.apple.iphone") \
	X(_UTTypeiPodTouch, "com.apple.ipod-touch")

#define UT_TYPE_DEFINE(symbol, identifier) UTType *symbol = nil;
UT_TYPE_CONSTANTS(UT_TYPE_DEFINE)
#undef UT_TYPE_DEFINE

typedef struct {
	UTType **slot;
	const char *identifier;
} UTTypeConstantEntry;

static UTTypeConstantEntry const kUTTypeConstants[] = {
#define UT_TYPE_ENTRY(symbol, identifier) { &symbol, identifier },
UT_TYPE_CONSTANTS(UT_TYPE_ENTRY)
#undef UT_TYPE_ENTRY
};

NSString * const UTTagClassFilenameExtension = @"public.filename-extension";
NSString * const UTTagClassMIMEType = @"public.mime-type";

// these are C++ typeinfo names that some binaries resolve through this framework
void* const _ZTSSt11logic_error = (void*)0;
void* const _ZTSSt12length_error = (void*)0;
void* const _ZTSSt19bad_optional_access = (void*)0;
void* const _ZTSSt20bad_array_new_length = (void*)0;
void* const _ZTSSt9bad_alloc = (void*)0;
void* const _ZTSSt9exception = (void*)0;

__attribute__((constructor))
static void UTTypeInitializeConstants(void)
{
	size_t i;

	for (i = 0; i < sizeof(kUTTypeConstants) / sizeof(kUTTypeConstants[0]); i++)
		*kUTTypeConstants[i].slot = UTTypeCreateInternal([NSString stringWithUTF8String: kUTTypeConstants[i].identifier]);
}