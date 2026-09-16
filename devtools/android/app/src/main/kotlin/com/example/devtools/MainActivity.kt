package com.example.devtools

import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var permissionChannel: MethodChannel? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        permissionChannel =
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                "devtools/permissions",
            ).also { channel ->
                channel.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "ensureMediaPermissions" -> {
                            val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                            val needsCamera = (args["camera"] as? Boolean) ?: false
                            val needsMicrophone = (args["microphone"] as? Boolean) ?: false
                            ensureMediaPermissions(
                                needsCamera = needsCamera,
                                needsMicrophone = needsMicrophone,
                                result = result,
                            )
                        }
                        else -> result.notImplemented()
                    }
                }
            }
    }

    private fun ensureMediaPermissions(
        needsCamera: Boolean,
        needsMicrophone: Boolean,
        result: MethodChannel.Result,
    ) {
        val permissions = mutableListOf<String>()
        if (needsCamera &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED
        ) {
            permissions.add(Manifest.permission.CAMERA)
        }
        if (needsMicrophone &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED
        ) {
            permissions.add(Manifest.permission.RECORD_AUDIO)
        }
        if (permissions.isEmpty()) {
            result.success(true)
            return
        }

        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            this,
            permissions.toTypedArray(),
            REQUEST_MEDIA_PERMISSIONS,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_MEDIA_PERMISSIONS) {
            return
        }

        val result = pendingPermissionResult ?: return
        pendingPermissionResult = null
        result.success(grantResults.all { it == PackageManager.PERMISSION_GRANTED })
    }

    companion object {
        private const val REQUEST_MEDIA_PERMISSIONS = 1001
    }
}
