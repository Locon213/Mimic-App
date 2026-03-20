package com.locon213.mimic_app

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.util.Base64
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.ByteArrayOutputStream

class AppListPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.locon213.mimic/app_list")
        channel.setMethodCallHandler(this)
        context = binding.applicationContext
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getInstalledApps" -> {
                try {
                    val apps = getInstalledApps()
                    result.success(apps)
                } catch (e: Exception) {
                    result.error("ERROR", "Failed to get installed apps: ${e.message}", null)
                }
            }
            "getAppIcon" -> {
                val packageName = call.argument<String>("packageName")
                if (packageName != null) {
                    try {
                        val icon = getAppIcon(packageName)
                        result.success(icon)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to get app icon: ${e.message}", null)
                    }
                } else {
                    result.error("INVALID_ARGUMENT", "Package name is required", null)
                }
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun getInstalledApps(): List<Map<String, String>> {
        val packageManager = context.packageManager
        val apps = mutableListOf<Map<String, String>>()

        val packages = packageManager.getInstalledApplications(PackageManager.GET_META_DATA)
        
        for (appInfo in packages) {
            // Skip system apps that are not user-installed
            if (appInfo.flags and ApplicationInfo.FLAG_SYSTEM != 0) {
                continue
            }

            val packageName = appInfo.packageName
            val appName = appInfo.loadLabel(packageManager).toString()

            apps.add(mapOf(
                "packageName" to packageName,
                "appName" to appName
            ))
        }

        // Sort by app name
        apps.sortBy { it["appName"]?.lowercase() ?: "" }

        return apps
    }

    private fun getAppIcon(packageName: String): String? {
        return try {
            val packageManager = context.packageManager
            val drawable = packageManager.getApplicationIcon(packageName)
            drawableToBase64(drawable)
        } catch (e: PackageManager.NameNotFoundException) {
            null
        }
    }

    private fun drawableToBase64(drawable: Drawable): String {
        val bitmap = Bitmap.createBitmap(
            drawable.intrinsicWidth.coerceAtLeast(1),
            drawable.intrinsicHeight.coerceAtLeast(1),
            Bitmap.Config.ARGB_8888
        )
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)

        val outputStream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, outputStream)
        val byteArray = outputStream.toByteArray()
        
        return Base64.encodeToString(byteArray, Base64.NO_WRAP)
    }
}
