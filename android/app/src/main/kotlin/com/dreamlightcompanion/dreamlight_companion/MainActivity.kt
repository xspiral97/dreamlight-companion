package com.dreamlightcompanion.dreamlight_companion

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var pendingApk: File? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dreamlight_companion/updates")
            .setMethodCallHandler { call, result ->
                if (call.method != "installApk") {
                    result.notImplemented()
                } else {
                    try {
                        val raw = call.argument<String>("path") ?: error("Missing APK path")
                        val apk = File(raw).canonicalFile
                        val updateDir = File(filesDir, "updates").canonicalFile
                        require(apk.path.startsWith(updateDir.path + File.separator) && apk.isFile && apk.extension == "apk") { "Invalid update file" }
                        if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
                            pendingApk = apk
                            startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                        } else {
                            install(apk)
                        }
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("UPDATE_FAILED", error.message, null)
                    }
                }
            }
    }

    override fun onResume() {
        super.onResume()
        val apk = pendingApk ?: return
        pendingApk = null
        if (Build.VERSION.SDK_INT < 26 || packageManager.canRequestPackageInstalls()) install(apk)
    }

    private fun install(apk: File) {
        val uri = FileProvider.getUriForFile(this, "$packageName.updates", apk)
        startActivity(Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        })
    }
}
