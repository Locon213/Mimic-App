package com.locon213.mimic_app

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.util.Log
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "MainActivity"
        private const val VPN_CHANNEL = "com.locon213.mimic_app/vpn"
        private const val VPN_EVENT_CHANNEL = "com.locon213.mimic_app/vpn_events"
        private const val VPN_PERMISSION_REQUEST = 1001
        private const val NOTIFICATION_PERMISSION_REQUEST = 1002
    }

    private var vpnMethodChannel: MethodChannel? = null
    private var vpnEventChannel: EventChannel? = null
    private var vpnEventSink: EventChannel.EventSink? = null
    private var pendingResult: MethodChannel.Result? = null
    private var pendingServerUrl: String = ""
    private var pendingServerName: String = ""
    private var pendingMode: String = "TUN"

    private val vpnReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                ACTION_VPN_CONNECTED -> {
                    Log.d(TAG, "VPN connected broadcast received")
                    vpnEventSink?.success(mapOf(
                        "event" to "connected",
                        "serverUrl" to intent.getStringExtra("server_url"),
                        "serverName" to intent.getStringExtra("server_name")
                    ))
                }
                ACTION_VPN_DISCONNECTED -> {
                    Log.d(TAG, "VPN disconnected broadcast received")
                    vpnEventSink?.success(mapOf(
                        "event" to "disconnected"
                    ))
                }
                ACTION_VPN_ERROR -> {
                    Log.d(TAG, "VPN error broadcast received")
                    vpnEventSink?.success(mapOf(
                        "event" to "error",
                        "error" to intent.getStringExtra("error")
                    ))
                }
            }
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Setup Method Channel for VPN commands
        vpnMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VPN_CHANNEL)
        vpnMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "prepareVpn" -> {
                    prepareVpn(result)
                }
                "connectVpn" -> {
                    val serverUrl = call.argument<String>("serverUrl") ?: ""
                    val serverName = call.argument<String>("serverName") ?: "Unknown Server"
                    val mode = call.argument<String>("mode") ?: "TUN"
                    connectVpn(serverUrl, serverName, mode, result)
                }
                "disconnectVpn" -> {
                    disconnectVpn(result)
                }
                "isVpnRunning" -> {
                    result.success(MimicVpnService.isVpnRunning)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Setup Event Channel for VPN status updates
        vpnEventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, VPN_EVENT_CHANNEL)
        vpnEventChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                vpnEventSink = events
            }

            override fun onCancel(arguments: Any?) {
                vpnEventSink = null
            }
        })

        // Register broadcast receiver
        val filter = IntentFilter().apply {
            addAction(ACTION_VPN_CONNECTED)
            addAction(ACTION_VPN_DISCONNECTED)
            addAction(ACTION_VPN_ERROR)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(vpnReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(vpnReceiver, filter)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            unregisterReceiver(vpnReceiver)
        } catch (e: Exception) {
            Log.e(TAG, "Error unregistering receiver: ${e.message}")
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        when (requestCode) {
            VPN_PERMISSION_REQUEST -> {
                if (resultCode == Activity.RESULT_OK) {
                    Log.d(TAG, "VPN permission granted, connecting...")
                    startVpnService(pendingServerUrl, pendingServerName, pendingMode)
                    pendingResult?.success(true)
                    pendingResult = null
                } else {
                    Log.d(TAG, "VPN permission denied")
                    pendingResult?.success(false)
                    pendingResult = null
                }
            }
            NOTIFICATION_PERMISSION_REQUEST -> {
                // Notification permission result - continue with VPN connection
                Log.d(TAG, "Notification permission result: $resultCode")
            }
        }
    }

    private fun prepareVpn(result: MethodChannel.Result) {
        try {
            // Request notification permission for Android 13+
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                if (ContextCompat.checkSelfPermission(
                        this,
                        android.Manifest.permission.POST_NOTIFICATIONS
                    ) != PackageManager.PERMISSION_GRANTED
                ) {
                    ActivityCompat.requestPermissions(
                        this,
                        arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                        NOTIFICATION_PERMISSION_REQUEST
                    )
                }
            }

            val prepareIntent = VpnService.prepare(this)
            if (prepareIntent != null) {
                Log.d(TAG, "VPN permission required, starting activity")
                pendingResult = result
                startActivityForResult(prepareIntent, VPN_PERMISSION_REQUEST)
            } else {
                Log.d(TAG, "VPN permission already granted")
                result.success(true)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error preparing VPN: ${e.message}", e)
            result.error("VPN_PREPARE_ERROR", e.message, null)
        }
    }

    private fun connectVpn(serverUrl: String, serverName: String, mode: String, result: MethodChannel.Result) {
        try {
            Log.d(TAG, "Connecting to VPN: $serverUrl ($serverName), mode: $mode")
            
            // First check if we need VPN permission
            val prepareIntent = VpnService.prepare(this)
            if (prepareIntent != null) {
                // Need to request permission first
                Log.d(TAG, "VPN permission required, storing pending connection")
                pendingServerUrl = serverUrl
                pendingServerName = serverName
                pendingMode = mode
                pendingResult = result
                startActivityForResult(prepareIntent, VPN_PERMISSION_REQUEST)
            } else {
                // Permission already granted, connect directly
                Log.d(TAG, "VPN permission already granted, connecting directly")
                startVpnService(serverUrl, serverName, mode)
                result.success(true)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error connecting to VPN: ${e.message}", e)
            result.error("VPN_CONNECT_ERROR", e.message, null)
        }
    }

    private fun startVpnService(serverUrl: String, serverName: String, mode: String) {
        val intent = Intent(this, MimicVpnService::class.java).apply {
            action = ACTION_CONNECT
            putExtra("server_url", serverUrl)
            putExtra("server_name", serverName)
            putExtra("mode", mode)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }

        MimicVpnService.isVpnRunning = true
    }

    private fun disconnectVpn(result: MethodChannel.Result) {
        try {
            Log.d(TAG, "Disconnecting VPN")
            
            val intent = Intent(this, MimicVpnService::class.java).apply {
                action = ACTION_DISCONNECT
            }

            startService(intent)
            MimicVpnService.isVpnRunning = false
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Error disconnecting VPN: ${e.message}", e)
            result.error("VPN_DISCONNECT_ERROR", e.message, null)
        }
    }
}
