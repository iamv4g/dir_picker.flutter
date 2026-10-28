package com.iamv4g.dir_picker

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

/**
 * Entry point for directory picking, callable from Dart via JNI.
 *
 * [pickerHandler] is injected by [DirPickerPlugin] when an Activity is available.
 * [pick] launches a coroutine on IO dispatcher so it never blocks the Dart thread.
 */
class DirPicker {
    companion object {
        @Volatile
        var applicationContext: Context? = null

        /**
         * Set by [DirPickerPlugin] when Activity becomes available.
         * Cleared when Activity is detached.
         */
        @Volatile
        var pickerHandler: PickerHandler? = null

        /**
         * Shows the directory picker and delivers the result via [callback].
         *
         * Non-blocking: launches a coroutine internally so Dart can return
         * immediately and await the callback.
         *
         * @param shouldPersist Whether to take persistable URI permission (Android only)
         * @param initialUri A content URI to open the picker in (API 26+), or null
         * @param callback Receives onSuccess, onCancelled, or onError
         */
        @JvmStatic
        fun pick(shouldPersist: Boolean, initialUri: String?, callback: PickerCallback) {
            CoroutineScope(Dispatchers.IO).launch {
                val handler = pickerHandler
                if (handler == null) {
                    callback.onError("NO_ACTIVITY", "No Activity available to show directory picker")
                    return@launch
                }

                try {
                    val uri = handler.pick(shouldPersist, initialUri?.let(Uri::parse))
                    if (uri != null) {
                        callback.onSuccess(uri)
                    } else {
                        callback.onCancelled()
                    }
                } catch (e: PickerException) {
                    callback.onError(e.code, e.message ?: "Unknown error")
                } catch (e: Exception) {
                    callback.onError("PICKER_ERROR", e.message ?: "Unknown error")
                }
            }
        }

        /**
         * Lists files and directories inside a previously picked SAF tree URI.
         */
        @JvmStatic
        fun listEntries(treeUri: String, recursive: Boolean, callback: ListEntriesCallback) {
            CoroutineScope(Dispatchers.IO).launch {
                val context = applicationContext
                if (context == null) {
                    callback.onError("NO_CONTEXT", "No application context available")
                    return@launch
                }

                try {
                    val root = DocumentFile.fromTreeUri(context, Uri.parse(treeUri))
                    if (root == null || !root.isDirectory) {
                        callback.onError("INVALID_URI", "Cannot open directory URI")
                        return@launch
                    }

                    val entries = collectEntries(root, recursive)
                    val jsonArray = JSONArray()
                    for (entry in entries) {
                        jsonArray.put(
                            JSONObject().apply {
                                put("name", entry.name)
                                put("relativePath", entry.relativePath)
                                put("isDirectory", entry.document.isDirectory)
                                put("uri", entry.document.uri.toString())
                                if (entry.document.isFile) {
                                    put("size", entry.document.length())
                                } else {
                                    put("size", JSONObject.NULL)
                                }

                                val lastModified = entry.document.lastModified()
                                if (lastModified > 0L) {
                                    put("lastModified", lastModified)
                                } else {
                                    put("lastModified", JSONObject.NULL)
                                }
                            }
                        )
                    }
                    callback.onSuccess(jsonArray.toString())
                } catch (e: Exception) {
                    callback.onError("LIST_ERROR", e.message ?: "Unknown error")
                }
            }
        }
    }
}

/** A picker failure reported to Dart with [code] instead of `PICKER_ERROR`. */
internal class PickerException(val code: String, message: String) : Exception(message)

private data class ListedDocumentEntry(
    val document: DocumentFile,
    val name: String,
    val relativePath: String
)

private fun collectEntries(
    directory: DocumentFile,
    recursive: Boolean,
    parentRelativePath: String = ""
): List<ListedDocumentEntry> {
    val entries = mutableListOf<ListedDocumentEntry>()

    for (child in directory.listFiles()) {
        val name = child.name ?: child.uri.lastPathSegment ?: ""
        val relativePath = if (parentRelativePath.isEmpty()) {
            name
        } else {
            "$parentRelativePath/$name"
        }

        entries.add(
            ListedDocumentEntry(
                document = child,
                name = name,
                relativePath = relativePath
            )
        )

        if (recursive && child.isDirectory) {
            entries.addAll(collectEntries(child, recursive = true, parentRelativePath = relativePath))
        }
    }

    return entries
}
