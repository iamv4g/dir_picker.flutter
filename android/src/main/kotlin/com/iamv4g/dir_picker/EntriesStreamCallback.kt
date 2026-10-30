package com.iamv4g.dir_picker

/**
 * Callback interface for streamed directory listings.
 *
 * jnigen generates a Dart binding with [implement()] factory that creates
 * a Java object backed by a RawReceivePort (native port under the hood).
 *
 * [onBatch] is called any number of times, then exactly one of [onDone] or
 * [onError].
 */
interface EntriesStreamCallback {
    fun onBatch(json: String)
    fun onDone()
    fun onError(code: String, message: String)
}

/** A running [DirPicker.streamEntries] walk, which Dart can [cancel]. */
class EntriesStream {
    @Volatile
    var isCancelled: Boolean = false
        private set

    /** Stops the walk. No more batches are sent, only [EntriesStreamCallback.onDone]. */
    fun cancel() {
        isCancelled = true
    }
}
