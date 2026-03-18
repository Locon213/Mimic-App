package com.locon213.mimic_app

import android.app.*
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import mobile.MimicClient
import mobile.NetworkStats
import java.io.FileInputStream
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

/**
 * Mimic VpnService - Real VPN service using Android VpnService
 * Routes all traffic through the Mimic Go library via TUN interface
 */
class MimicVpnService : VpnService() {

    companion object {
        private const val TAG = "MimicVpnService"
        private const val NOTIFICATION_CHANNEL_ID = "mimic_vpn_channel"
        private const val NOTIFICATION_ID = 1001
        private const val VPN_MTU = 1500
        private const val VPN_ADDRESS = "10.0.0.1"
        private const val VPN_ADDRESS_V6 = "fd00::1"

        const val EXTRA_SERVER_NAME = "server_name"
        const val EXTRA_SERVER_URL = "server_url"

        var isVpnRunning: Boolean = false
            internal set
    }

    private val binder = LocalBinder()
    private var vpnInterface: ParcelFileDescriptor? = null
    private var vpnExecutor: ScheduledExecutorService? = null
    private var isRunning = false
    private var currentServerName: String = "Unknown"
    private var currentServerUrl: String = ""
    private var currentMode: String = "TUN"
    
    // Go Mobile client for VPN processing
    private var mimicClient: MimicClient? = null
    private var statsTimer: java.util.Timer? = null
    private var currentStats: NetworkStats? = null

    // Network tracking
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var connectivityManager: ConnectivityManager? = null

    inner class LocalBinder : Binder() {
        fun getService(): MimicVpnService = this@MimicVpnService
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "VpnService created")
        NativeLogBridge.info(TAG, "VpnService created")
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "VpnService started with action: ${intent?.action}")
        NativeLogBridge.info(TAG, "VpnService started with action: ${intent?.action}")

        when (intent?.action) {
            ACTION_CONNECT -> {
                val serverUrl = intent.getStringExtra("server_url") ?: ""
                val serverName = intent.getStringExtra("server_name") ?: "Unknown Server"
                val mode = intent.getStringExtra("mode") ?: "TUN"
                currentServerUrl = serverUrl
                currentServerName = serverName
                currentMode = mode
                connect(serverUrl, serverName, mode)
            }
            ACTION_DISCONNECT -> {
                disconnect()
            }
        }

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? {
        Log.d(TAG, "VpnService bound")
        NativeLogBridge.debug(TAG, "VpnService bound")
        return binder
    }

    override fun onUnbind(intent: Intent): Boolean {
        Log.d(TAG, "VpnService unbound")
        NativeLogBridge.debug(TAG, "VpnService unbound")
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        Log.d(TAG, "VpnService destroyed")
        NativeLogBridge.info(TAG, "VpnService destroyed")
        disconnect()
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "VPN Connection",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows VPN connection status and speed"
                setShowBadge(false)
                enableVibration(false)
                enableLights(false)
            }

            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(
        statusText: String,
        serverName: String = currentServerName,
        downloadSpeed: Long = 0,
        uploadSpeed: Long = 0
    ): Notification {
        // Format speed
        val downloadStr = formatSpeed(downloadSpeed)
        val uploadStr = formatSpeed(uploadSpeed)

        // Create disconnect intent
        val disconnectIntent = Intent(this, MimicVpnService::class.java).apply {
            action = ACTION_DISCONNECT
        }
        val disconnectPendingIntent = PendingIntent.getService(
            this,
            1,
            disconnectIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        // Create open app intent
        val openAppIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val openAppPendingIntent = PendingIntent.getActivity(
            this,
            0,
            openAppIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        // Build notification with BigText style for speed info
        val builder = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("Mimic VPN - $serverName")
            .setContentText(statusText)
            .setStyle(
                NotificationCompat.BigTextStyle()
                    .bigText("$statusText\n⬇ $downloadStr  ⬆ $uploadStr")
            )
            .setSmallIcon(R.drawable.ic_notification)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setContentIntent(openAppPendingIntent)
            .addAction(
                R.drawable.ic_notification,
                "Disconnect",
                disconnectPendingIntent
            )
            .setDeleteIntent(null) // Prevent swipe dismiss

        // Make notification non-dismissible on Android 8+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            builder.setCategory(Notification.CATEGORY_SERVICE)
            builder.setPriority(Notification.PRIORITY_LOW)
        }

        return builder.build()
    }

    private fun formatSpeed(bytesPerSecond: Long): String {
        return when {
            bytesPerSecond < 1024 -> "$bytesPerSecond B/s"
            bytesPerSecond < 1024 * 1024 -> "${bytesPerSecond / 1024} KB/s"
            else -> String.format("%.1f MB/s", bytesPerSecond / (1024.0 * 1024.0))
        }
    }

    private fun connect(serverUrl: String, serverName: String, mode: String) {
        if (isRunning) {
            Log.w(TAG, "Already running")
            NativeLogBridge.warning(TAG, "Connect ignored because VPN is already running")
            return
        }

        try {
            Log.d(TAG, "Setting up VPN interface for: $serverUrl, mode: $mode")
            NativeLogBridge.info(TAG, "Setting up VPN interface for $serverName in $mode mode")

            // Start foreground with connecting notification
            startForeground(NOTIFICATION_ID, createNotification("Connecting...", serverName))

            // Initialize Go Mobile client
            mimicClient = MimicClient()
            
            // Setup VPN interface FIRST (required for TUN mode)
            val builder = Builder()
            builder.addAddress(VPN_ADDRESS, 32)
            builder.addAddress(VPN_ADDRESS_V6, 128)
            builder.addRoute("0.0.0.0", 0)
            builder.addRoute("::", 0)
            builder.addDnsServer("1.1.1.1")
            builder.addDnsServer("8.8.8.8")
            builder.setMtu(VPN_MTU)
            builder.setSession("Mimic VPN")

            // Set metered flag for Android 11+
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                builder.setMetered(false)
            }

            // Establish VPN interface and get file descriptor
            vpnInterface = builder.establish()
                ?: throw IllegalStateException("Failed to establish VPN interface")

            Log.d(TAG, "VPN interface established successfully")
            NativeLogBridge.info(TAG, "VPN interface established successfully")
            
            // Start Go Mobile client with TUN mode
            // The Go client will handle tun2socks internally
            try {
                mimicClient?.connect(serverUrl, mode)
                Log.d(TAG, "Go Mobile client started successfully")
                NativeLogBridge.info(TAG, "Go Mobile client started successfully")
            } catch (goException: Exception) {
                Log.e(TAG, "Failed to start Go client: ${goException.message}", goException)
                NativeLogBridge.error(TAG, "Failed to start Go client: ${goException.message}")
                throw goException
            }

            isRunning = true

            // Setup network callback for better connectivity
            setupNetworkCallback()

            // Start stats polling for notification
            startStatsPolling()

            // Update notification to connected
            updateNotification("Connected • ${formatServerName(serverName)}", serverName)

            // Notify Flutter via broadcast
            sendBroadcast(
                Intent(ACTION_VPN_CONNECTED).apply {
                    setPackage(packageName)
                    putExtra("server_url", serverUrl)
                    putExtra("server_name", serverName)
                }
            )

            Log.d(TAG, "VPN connection completed successfully")
            NativeLogBridge.info(TAG, "VPN connection completed successfully")

        } catch (e: Exception) {
            Log.e(TAG, "Connection failed: ${e.message}", e)
            NativeLogBridge.error(TAG, "Connection failed: ${e.message}")
            updateNotification("Connection failed: ${e.message}")
            disconnect()

            sendBroadcast(
                Intent(ACTION_VPN_ERROR).apply {
                    setPackage(packageName)
                    putExtra("error", e.message)
                }
            )
        }
    }

    fun disconnect() {
        if (!isRunning && mimicClient == null) return

        Log.d(TAG, "Disconnecting VPN")
        NativeLogBridge.info(TAG, "Disconnecting VPN session")
        
        // Stop stats polling
        stopStatsPolling()
        
        // Stop Go Mobile client first
        try {
            mimicClient?.disconnect()
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping Go client: ${e.message}")
            NativeLogBridge.error(TAG, "Error stopping Go client: ${e.message}")
        }
        mimicClient = null

        isRunning = false

        // Stop packet forwarding
        vpnExecutor?.shutdown()
        vpnExecutor = null

        // Close VPN interface
        try {
            vpnInterface?.close()
        } catch (e: Exception) {
            Log.e(TAG, "Error closing VPN interface: ${e.message}")
            NativeLogBridge.error(TAG, "Error closing VPN interface: ${e.message}")
        }
        vpnInterface = null

        // Unregister network callback
        networkCallback?.let {
            connectivityManager?.unregisterNetworkCallback(it)
        }
        networkCallback = null

        // Stop foreground service
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()

        // Notify Flutter
        sendBroadcast(
            Intent(ACTION_VPN_DISCONNECTED).apply {
                setPackage(packageName)
            }
        )

        Log.d(TAG, "VPN disconnected")
        NativeLogBridge.info(TAG, "VPN disconnected")
    }

    private fun setupNetworkCallback() {
        connectivityManager = getSystemService(ConnectivityManager::class.java)

        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()

        networkCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                Log.d(TAG, "Network available")
                NativeLogBridge.debug(TAG, "Network available")
            }

            override fun onLost(network: Network) {
                Log.d(TAG, "Network lost")
                NativeLogBridge.warning(TAG, "Network lost")
            }

            override fun onCapabilitiesChanged(
                network: Network,
                capabilities: NetworkCapabilities
            ) {
                val hasInternet = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                Log.d(TAG, "Network capabilities changed, has internet: $hasInternet")
                NativeLogBridge.debug(TAG, "Network capabilities changed, has internet: $hasInternet")
            }
        }

        connectivityManager?.registerNetworkCallback(request, networkCallback!!)
    }

    private fun updateNotification(status: String, serverName: String = currentServerName) {
        val notification = createNotification(status, serverName)
        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    private fun startStatsPolling() {
        stopStatsPolling()
        statsTimer = java.util.Timer()
        statsTimer?.scheduleAtFixedRate(object : java.util.TimerTask() {
            override fun run() {
                try {
                    mimicClient?.let { client ->
                        val stats = client.GetStats()
                        currentStats = stats

                        val statusText = "Connected • ${formatServerName(currentServerName)}"

                        updateNotificationWithStats(statusText, currentServerName, stats.downloadSpeed, stats.uploadSpeed)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error polling stats: ${e.message}")
                    NativeLogBridge.error(TAG, "Error polling stats: ${e.message}")
                }
            }
        }, 0, 1000) // Update every second
    }

    private fun stopStatsPolling() {
        statsTimer?.cancel()
        statsTimer = null
    }

    private fun updateNotificationWithStats(
        status: String,
        serverName: String,
        downloadSpeed: Long,
        uploadSpeed: Long
    ) {
        try {
            val notification = createNotification(status, serverName, downloadSpeed, uploadSpeed)
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.notify(NOTIFICATION_ID, notification)
        } catch (e: Exception) {
            Log.e(TAG, "Error updating notification: ${e.message}")
            NativeLogBridge.error(TAG, "Error updating notification: ${e.message}")
        }
    }

    private fun formatServerName(name: String): String {
        // Extract short name from full server name
        return if (name.length > 30) "${name.take(27)}..." else name
    }
}

// Broadcast actions for Flutter to listen to
const val ACTION_CONNECT = "com.locon213.mimic_app.CONNECT"
const val ACTION_DISCONNECT = "com.locon213.mimic_app.DISCONNECT"
const val ACTION_VPN_CONNECTED = "com.locon213.mimic_app.VPN_CONNECTED"
const val ACTION_VPN_DISCONNECTED = "com.locon213.mimic_app.VPN_DISCONNECTED"
const val ACTION_VPN_ERROR = "com.locon213.mimic_app.VPN_ERROR"
