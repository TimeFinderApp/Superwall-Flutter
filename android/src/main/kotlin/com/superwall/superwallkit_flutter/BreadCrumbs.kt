package com.superwall.superwallkit_flutter

import com.superwall.superwallkit_flutter.bridges.BridgeInstance

object BreadCrumbs {
    private val logBuilder = StringBuilder()

    fun append(debugString: String) {
        try {
            logBuilder.append(debugString.toString()).append("\n")
        } catch (e: Exception) {
            // Safely handle any string conversion errors
            logBuilder.append("[Error logging message]").append("\n")
        }
    }

    fun logs(): String {
        val output = StringBuilder()

        output.append("\n=======LOGS START========\n")
        output.append(logBuilder)
        output.append("=======LOGS END==========\n")
        return output.toString()
    }

    fun clear() {
        logBuilder.clear()
    }
}

fun MutableMap<String, BridgeInstance>.toFormattedString(): String {
    return this.entries.joinToString(separator = "\n") { (key, value) ->
        "Key: $key, Value: $value"
    }
}