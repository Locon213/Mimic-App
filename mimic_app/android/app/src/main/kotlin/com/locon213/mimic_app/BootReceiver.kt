package com.locon213.mimic_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * BootReceiver - Starts VPN service on device boot if needed
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "BootReceiver"
        private const val PREFS_NAME = "vpn_prefs"
        private const val KEY_AUTO_START = "auto_start_vpn"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == "android.intent.action.QUICKBOOT_POWERON") {
            
            Log.d(TAG, "Boot completed, checking auto-start")
            
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val autoStart = prefs.getBoolean(KEY_AUTO_START, false)
            
            if (autoStart) {
                try {
                    val vpnIntent = Intent(context, MimicVpnService::class.java)
                    vpnIntent.action = ACTION_CONNECT
                    
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        context.startForegroundService(vpnIntent)
                    } else {
                        context.startService(vpnIntent)
                    }
                    
                    Log.d(TAG, "VPN service started on boot")
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to start VPN on boot: ${e.message}")
                }
            }
        }
    }
}
