package com.iamv4g.dir_picker

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry.ActivityResultListener
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Flutter plugin for dir_picker on Android.
 *
 * Handles directory picking via Storage Access Framework (SAF).
 * Implements ActivityAware to access the Activity for launching the picker.
 */
class DirPickerPlugin : FlutterPlugin, ActivityAware, ActivityResultListener {

    companion object {
        private const val TAG = "DirPicker"
        private const val REQUEST_CODE_PICK_DIRECTORY = 47291
        private const val PICKER_REGISTRY_KEY = "com.iamv4g.dir_picker.picker"
    }

    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null

    // For ComponentActivity (AndroidX)
    private var pickerLauncher: ActivityResultLauncher<Uri?>? = null

    // Pending coroutine continuation. Only read and written on the main thread.
    private var pendingContinuation: CancellableContinuation<String?>? = null
    private var shouldPersistPermission: Boolean = true

    // ─────────────────────────────────────────────────────────────────────────
    // FlutterPlugin
    // ─────────────────────────────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        DirPicker.applicationContext = binding.applicationContext
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        DirPicker.applicationContext = null
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ActivityAware
    // ─────────────────────────────────────────────────────────────────────────

    override fun onAttachedToActivity(binding: ActivityPluginBinding) = attachActivity(binding)

    // The picker result is delivered to the recreated Activity, so a pending
    // pick survives a configuration change.
    override fun onDetachedFromActivityForConfigChanges() = detachActivity(cancelPick = false)

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = attachActivity(binding)

    override fun onDetachedFromActivity() = detachActivity(cancelPick = true)

    private fun attachActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
        setupPickerLauncher(binding.activity)
        setupPickerHandler()
    }

    private fun detachActivity(cancelPick: Boolean) {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        activity = null

        pickerLauncher?.unregister()
        pickerLauncher = null

        DirPicker.pickerHandler = null

        if (cancelPick) {
            // Resume any waiting coroutine with null (cancelled)
            pendingContinuation?.let { if (it.isActive) it.resume(null) }
            pendingContinuation = null
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Picker setup
    // ─────────────────────────────────────────────────────────────────────────

    private fun setupPickerLauncher(activity: Activity) {
        if (activity !is ComponentActivity) return

        pickerLauncher = activity.activityResultRegistry.register(
            PICKER_REGISTRY_KEY,
            ActivityResultContracts.OpenDocumentTree()
        ) { uri: Uri? ->
            handlePickerResult(uri)
        }
    }

    private fun setupPickerHandler() {
        DirPicker.pickerHandler = PickerHandler { shouldPersist, initialUri ->
            // Activity APIs must be called on the main thread.
            withContext(Dispatchers.Main) { launchPicker(shouldPersist, initialUri) }
        }
    }

    private suspend fun launchPicker(shouldPersist: Boolean, initialUri: Uri?): String? =
        suspendCancellableCoroutine { continuation ->
            if (pendingContinuation != null) {
                continuation.resumeWithException(
                    PickerException("ALREADY_ACTIVE", "A directory picker is already open")
                )
                return@suspendCancellableCoroutine
            }

            val currentActivity = activity
            if (currentActivity == null) {
                continuation.resumeWithException(
                    PickerException("NO_ACTIVITY", "No Activity available to show directory picker")
                )
                return@suspendCancellableCoroutine
            }

            pendingContinuation = continuation
            shouldPersistPermission = shouldPersist

            continuation.invokeOnCancellation {
                if (pendingContinuation === continuation) pendingContinuation = null
            }

            try {
                val initialDocument = initialUri?.let(::documentUri)
                val launcher = pickerLauncher
                if (launcher != null) {
                    // OpenDocumentTree sets EXTRA_INITIAL_URI on API 26+.
                    launcher.launch(initialDocument)
                } else {
                    // Fallback for non-ComponentActivity
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                    if (initialDocument != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        intent.putExtra(DocumentsContract.EXTRA_INITIAL_URI, initialDocument)
                    }
                    currentActivity.startActivityForResult(intent, REQUEST_CODE_PICK_DIRECTORY)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to launch directory picker: ${e.message}")
                pendingContinuation = null
                continuation.resumeWithException(
                    PickerException("PICKER_ERROR", "Failed to launch directory picker: ${e.message}")
                )
            }
        }

    /**
     * EXTRA_INITIAL_URI expects a document URI. A tree URI from an earlier
     * pick points at its root document; other URIs are passed as they are.
     */
    private fun documentUri(uri: Uri): Uri =
        if (DocumentsContract.isTreeUri(uri) && !isDocumentUri(uri)) {
            DocumentsContract.buildDocumentUriUsingTree(uri, DocumentsContract.getTreeDocumentId(uri))
        } else {
            uri
        }

    private fun isDocumentUri(uri: Uri): Boolean =
        activity?.let { DocumentsContract.isDocumentUri(it, uri) } ?: false

    private fun handlePickerResult(uri: Uri?) {
        val continuation = pendingContinuation ?: return
        pendingContinuation = null

        if (uri == null) {
            continuation.resume(null)
            return
        }

        if (shouldPersistPermission) {
            try {
                val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                activity?.contentResolver?.takePersistableUriPermission(uri, flags)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to persist permission: ${e.message}")
            }
        }

        continuation.resume(uri.toString())
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ActivityResultListener (fallback for non-ComponentActivity)
    // ─────────────────────────────────────────────────────────────────────────

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE_PICK_DIRECTORY) return false
        val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
        handlePickerResult(uri)
        return true
    }
}
