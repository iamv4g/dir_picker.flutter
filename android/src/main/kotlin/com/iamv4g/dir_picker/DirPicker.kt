package com.iamv4g.dir_picker

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
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
         * @param callback Receives onSuccess, onCancelled, or onError
         */
        @JvmStatic
        fun pick(shouldPersist: Boolean, callback: PickerCallback) {
            CoroutineScope(Dispatchers.IO).launch {
                val handler = pickerHandler
                if (handler == null) {
                    callback.onError("NO_ACTIVITY", "No Activity available to show directory picker")
                    return@launch
                }

                try {
                    val uri = handler.pick(shouldPersist)
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
                    val tree = Uri.parse(treeUri)
                    // Like DocumentFile.fromTreeUri: a URI for a document inside
                    // the tree (e.g. an entry's uri) lists that document.
                    val rootId = try {
                        if (DocumentsContract.isDocumentUri(context, tree)) {
                            DocumentsContract.getDocumentId(tree)
                        } else {
                            DocumentsContract.getTreeDocumentId(tree)
                        }
                    } catch (_: IllegalArgumentException) {
                        null
                    }
                    if (rootId == null || !isDirectory(context.contentResolver, tree, rootId)) {
                        callback.onError("INVALID_URI", "Cannot open directory URI")
                        return@launch
                    }

                    val entries = JSONArray()
                    collectEntries(context.contentResolver, tree, rootId, "", recursive, entries)
                    callback.onSuccess(entries.toString())
                } catch (e: Exception) {
                    callback.onError("LIST_ERROR", e.message ?: "Unknown error")
                }
            }
        }
    }
}

/** A picker failure reported to Dart with [code] instead of `PICKER_ERROR`. */
internal class PickerException(val code: String, message: String) : Exception(message)

private val CHILD_COLUMNS = arrayOf(
    Document.COLUMN_DOCUMENT_ID,
    Document.COLUMN_DISPLAY_NAME,
    Document.COLUMN_MIME_TYPE,
    Document.COLUMN_SIZE,
    Document.COLUMN_LAST_MODIFIED,
)

private fun isDirectory(resolver: ContentResolver, tree: Uri, documentId: String): Boolean =
    resolver.query(
        DocumentsContract.buildDocumentUriUsingTree(tree, documentId),
        arrayOf(Document.COLUMN_MIME_TYPE),
        null,
        null,
        null,
    )?.use { it.moveToFirst() && it.getString(0) == Document.MIME_TYPE_DIR } ?: false

/**
 * Appends the children of [parentId] to [out], with one query per directory.
 * `DocumentFile` runs a separate query for every field of every child, which
 * is far slower on large trees.
 *
 * A subdirectory that can't be queried is skipped; only the root throws.
 */
private fun collectEntries(
    resolver: ContentResolver,
    tree: Uri,
    parentId: String,
    parentPath: String,
    recursive: Boolean,
    out: JSONArray,
) {
    val subdirectories = mutableListOf<Pair<String, String>>()

    val cursor = resolver.query(
        DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentId),
        CHILD_COLUMNS,
        null,
        null,
        null,
    ) ?: throw IllegalStateException("Cannot list $parentPath")

    cursor.use {
        while (it.moveToNext()) {
            val documentId = it.getString(0)
            val name = it.getString(1) ?: documentId
            val isDirectory = it.getString(2) == Document.MIME_TYPE_DIR
            val relativePath = if (parentPath.isEmpty()) name else "$parentPath/$name"
            val lastModified = if (it.isNull(4)) 0L else it.getLong(4)

            out.put(
                JSONObject().apply {
                    put("name", name)
                    put("relativePath", relativePath)
                    put("isDirectory", isDirectory)
                    put("uri", DocumentsContract.buildDocumentUriUsingTree(tree, documentId).toString())
                    put("size", if (isDirectory || it.isNull(3)) JSONObject.NULL else it.getLong(3))
                    put("lastModified", if (lastModified > 0L) lastModified else JSONObject.NULL)
                }
            )

            if (recursive && isDirectory) subdirectories.add(documentId to relativePath)
        }
    }

    // Recurse after closing the cursor, so only one is open at a time.
    for ((documentId, relativePath) in subdirectories) {
        try {
            collectEntries(resolver, tree, documentId, relativePath, recursive = true, out)
        } catch (_: Exception) {
            // Unreadable subdirectory: keep its entry, skip its contents.
        }
    }
}
