package com.iamv4g.dir_picker

/**
 * Callback interface for directory listing results.
 *
 * jnigen generates a Dart binding with [implement()] factory that creates
 * a Java object backed by a RawReceivePort (native port under the hood).
 */
interface ListEntriesCallback {
    fun onSuccess(json: String)
    fun onError(code: String, message: String)
}
