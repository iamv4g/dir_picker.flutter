package com.iamv4g.dir_picker

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry.ActivityResultListener
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

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

    // Pending coroutine continuation
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

    override fun onDetachedFromActivityForConfigChanges() = detachActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = attachActivity(binding)

    override fun onDetachedFromActivity() = detachActivity()

    private fun attachActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
        setupPickerLauncher(binding.activity)
        setupPickerHandler()
    }

    private fun detachActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        activity = null

        pickerLauncher?.unregister()
        pickerLauncher = null

        DirPicker.pickerHandler = null

        // Resume any waiting coroutine with null (cancelled)
        pendingContinuation?.let { if (it.isActive) it.resume(null) }
        pendingContinuation = null
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
        DirPicker.pickerHandler = PickerHandler { shouldPersist ->
            suspendCancellableCoroutine { continuation ->
                pendingContinuation = continuation
                shouldPersistPermission = shouldPersist

                continuation.invokeOnCancellation {
                    pendingContinuation = null
                }

                val launcher = pickerLauncher
                if (launcher != null) {
                    try {
                        launcher.launch(null)
                        return@suspendCancellableCoroutine
                    } catch (_: Exception) {
                        // Fall back to startActivityForResult
                    }
                }

                // Fallback for non-ComponentActivity
                try {
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                    activity?.startActivityForResult(intent, REQUEST_CODE_PICK_DIRECTORY)
                        ?: run {
                            pendingContinuation = null
                            continuation.resume(null)
                        }
                } catch (e: Exception) {
                    pendingContinuation = null
                    continuation.resume(null)
                    Log.e(TAG, "Failed to launch directory picker: ${e.message}")
                }
            }
        }
    }

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
