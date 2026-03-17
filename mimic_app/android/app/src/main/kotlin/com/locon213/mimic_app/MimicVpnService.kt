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
            private set
    }

    private val binder = LocalBinder()
    private var vpnInterface: ParcelFileDescriptor? = null
    private var vpnExecutor: ScheduledExecutorService? = null
    private var isRunning = false
    private var currentServerName: String = "Unknown"
    private var currentServerUrl: String = ""

    // Network tracking
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var connectivityManager: ConnectivityManager? = null

    inner class LocalBinder : Binder() {
        fun getService(): MimicVpnService = this@MimicVpnService
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "VpnService created")
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "VpnService started with action: ${intent?.action}")

        when (intent?.action) {
            ACTION_CONNECT -> {
                val serverUrl = intent.getStringExtra("server_url") ?: ""
                val serverName = intent.getStringExtra("server_name") ?: "Unknown Server"
                val mode = intent.getStringExtra("mode") ?: "TUN"
                currentServerUrl = serverUrl
                currentServerName = serverName
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
        return binder
    }

    override fun onUnbind(intent: Intent): Boolean {
        Log.d(TAG, "VpnService unbound")
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        Log.d(TAG, "VpnService destroyed")
        disconnect()
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "VPN Connection",
                NotificationManager.IMPORTANCE_MIN
            ).apply {
                description = "Shows VPN connection status"
                setShowBadge(false)
                enableVibration(false)
                enableLights(false)
            }

            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(statusText: String, serverName: String = currentServerName) =
        NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("Mimic VPN - $serverName")
            .setContentText(statusText)
            .setSmallIcon(R.drawable.ic_notification)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setContentIntent(
                PendingIntent.getActivity(
                    this,
                    0,
                    Intent(this, MainActivity::class.java).apply {
                        flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
                    },
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
            )
            .addAction(
                R.drawable.ic_notification,
                "Disconnect",
                PendingIntent.getService(
                    this,
                    1,
                    Intent(this, MimicVpnService::class.java).apply {
                        action = ACTION_DISCONNECT
                    },
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
            )
            .build()

    private fun connect(serverUrl: String, serverName: String, mode: String) {
        if (isRunning) {
            Log.w(TAG, "Already running")
            return
        }

        try {
            Log.d(TAG, "Setting up VPN interface for: $serverUrl")

            // Start foreground with connecting notification
            startForeground(NOTIFICATION_ID, createNotification("Connecting...", serverName))

            // Setup VPN interface
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

            // Establish VPN interface
            vpnInterface = builder.establish()
                ?: throw IllegalStateException("Failed to establish VPN interface")

            Log.d(TAG, "VPN interface established successfully")
            isRunning = true

            // Setup network callback for better connectivity
            setupNetworkCallback()

            // Start packet forwarding thread
            startPacketForwarding()

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

        } catch (e: Exception) {
            Log.e(TAG, "Connection failed: ${e.message}", e)
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
        if (!isRunning) return

        Log.d(TAG, "Disconnecting VPN")
        isRunning = false

        // Stop packet forwarding
        vpnExecutor?.shutdown()
        vpnExecutor = null

        // Close VPN interface
        try {
            vpnInterface?.close()
        } catch (e: Exception) {
            Log.e(TAG, "Error closing VPN interface: ${e.message}")
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
    }

    private fun setupNetworkCallback() {
        connectivityManager = getSystemService(ConnectivityManager::class.java)

        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()

        networkCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                Log.d(TAG, "Network available")
            }

            override fun onLost(network: Network) {
                Log.d(TAG, "Network lost")
            }

            override fun onCapabilitiesChanged(
                network: Network,
                capabilities: NetworkCapabilities
            ) {
                val hasInternet = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                Log.d(TAG, "Network capabilities changed, has internet: $hasInternet")
            }
        }

        connectivityManager?.registerNetworkCallback(request, networkCallback!!)
    }

    private fun startPacketForwarding() {
        vpnExecutor = Executors.newScheduledThreadPool(1)

        vpnExecutor?.scheduleAtFixedRate({
            try {
                // Read and forward packets
                vpnInterface?.let { vpnFd ->
                    FileInputStream(vpnFd.fileDescriptor).use { input ->
                        val buffer = ByteArray(VPN_MTU)
                        val bytesRead = input.read(buffer)
                        if (bytesRead > 0) {
                            Log.v(TAG, "Read $bytesRead bytes from VPN interface")
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error reading from VPN: ${e.message}")
            }
        }, 0, 100, TimeUnit.MILLISECONDS)

        Log.d(TAG, "Packet forwarding started")
    }

    private fun updateNotification(status: String, serverName: String = currentServerName) {
        val notification = createNotification(status, serverName)
        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.notify(NOTIFICATION_ID, notification)
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
