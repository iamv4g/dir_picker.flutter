package com.iamv4g.dir_picker

/**
 * Callback interface for directory picker results.
 *
 * jnigen generates a Dart binding with [implement()] factory that creates
 * a Java object backed by a RawReceivePort (native port under the hood).
 */
interface PickerCallback {
    fun onSuccess(uri: String)
    fun onCancelled()
    fun onError(code: String, message: String)
}
