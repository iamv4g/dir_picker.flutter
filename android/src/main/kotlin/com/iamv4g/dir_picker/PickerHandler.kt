package com.iamv4g.dir_picker

/**
 * Bridge interface for picking a directory via SAF.
 *
 * Connects [DirPicker] (called from Dart via JNI) to [DirPickerPlugin]
 * which has Activity access via ActivityAware.
 */
fun interface PickerHandler {
    /**
     * Shows the system directory picker and returns the selected URI string,
     * or null if the user cancelled.
     *
     * Implementation must run the picker on the main thread and suspend
     * until the user responds.
     *
     * @param shouldPersist Whether to take persistable URI permission
     * @return Selected directory URI string, or null if cancelled
     */
    suspend fun pick(shouldPersist: Boolean): String?
}
