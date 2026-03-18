package com.locon213.mimic_app

import android.util.Log

object NativeLogBridge {
    private const val MAX_BUFFERED_LOGS = 200

    private val bufferedLogs = mutableListOf<Map<String, Any?>>()
    private val listeners = mutableSetOf<(Map<String, Any?>) -> Unit>()

    @Synchronized
    fun addListener(replayBuffered: Boolean = true, listener: (Map<String, Any?>) -> Unit) {
        listeners.add(listener)
        if (replayBuffered) {
            bufferedLogs.forEach(listener)
        }
    }

    @Synchronized
    fun removeListener(listener: (Map<String, Any?>) -> Unit) {
        listeners.remove(listener)
    }

    fun debug(source: String, message: String) = emit("debug", source, message)
    fun info(source: String, message: String) = emit("info", source, message)
    fun warning(source: String, message: String) = emit("warning", source, message)
    fun error(source: String, message: String) = emit("error", source, message)

    private fun emit(level: String, source: String, message: String) {
        val priority = when (level) {
            "error" -> Log.ERROR
            "warning" -> Log.WARN
            "info" -> Log.INFO
            else -> Log.DEBUG
        }

        Log.println(priority, source, message)

        val payload = mapOf(
            "level" to level,
            "source" to source,
            "message" to message,
            "timestamp" to System.currentTimeMillis(),
        )

        synchronized(this) {
            bufferedLogs.add(payload)
            if (bufferedLogs.size > MAX_BUFFERED_LOGS) {
                bufferedLogs.removeAt(0)
            }
            listeners.forEach { it(payload) }
        }
    }
}
