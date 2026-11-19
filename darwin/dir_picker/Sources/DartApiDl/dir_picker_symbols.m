/*
 * Gives Dart the addresses of the functions of dir_picker_ffi.h.
 *
 * Dart can't look them up by name (`DynamicLibrary.process().lookup`) in an
 * app that links the plugin statically, as Swift Package Manager and
 * CocoaPods with static linkage do: archiving it with STRIP_STYLE = all,
 * Xcode's default for apps, strips their names. Dart finds this class through
 * the Objective-C runtime instead, which keeps class names.
 */

#import <Foundation/Foundation.h>
#include <string.h>

// The header is in the Swift target's folder, which defines its functions
// (`@_cdecl`).
#include "../dir_picker/include/dir_picker_ffi.h"

typedef struct {
    const char *name;
    void *address;
} DirPickerSymbol;

#define DIR_PICKER_SYMBOL(function) {#function, (void *)&function},
static const DirPickerSymbol kSymbols[] = {DIR_PICKER_FUNCTIONS(DIR_PICKER_SYMBOL)};
#undef DIR_PICKER_SYMBOL

@interface DirPickerFFISymbols : NSObject
@end

@implementation DirPickerFFISymbols

/// The address of the function of dir_picker_ffi.h named [name], or NULL.
+ (void *)addressOf:(const char *)name {
    if (name == NULL) {
        return NULL;
    }
    for (size_t i = 0; i < sizeof(kSymbols) / sizeof(kSymbols[0]); i++) {
        if (strcmp(kSymbols[i].name, name) == 0) {
            return kSymbols[i].address;
        }
    }
    return NULL;
}

@end
