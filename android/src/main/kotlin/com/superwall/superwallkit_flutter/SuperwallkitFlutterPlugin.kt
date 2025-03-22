package com.superwall.superwallkit_flutter

import android.app.Activity
import android.os.Debug
import android.util.Log
import com.superwall.sdk.misc.runOnUiThread
import com.superwall.superwallkit_flutter.bridges.BridgeId
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import java.util.WeakHashMap
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

// Application lifecycle tracking enum
enum class ApplicationLifecycle {
    FOREGROUND, BACKGROUND, TRANSITIONING
}

class SuperwallkitFlutterPlugin : FlutterPlugin, ActivityAware {
    var currentActivity: Activity? = null
    
    // Add application lifecycle tracking
    private val applicationLifecycle = AtomicReference(ApplicationLifecycle.BACKGROUND)

    companion object {
        var instance: SuperwallkitFlutterPlugin? = null
            private set
        val reattachementCount = AtomicInteger(0)
        val lock = Object()
        val currentActivity: Activity?
            get() = instance?.currentActivity
    }

    init {
        if (BuildConfig.DEBUG && BuildConfig.WAIT_FOR_DEBUGGER) {
            Debug.waitForDebugger()
        }

        // Only allow instance to get set once.
        if (instance == null) {
            instance = this
        }
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        synchronized(lock) {
            BridgingCreator.setFlutterPlugin(flutterPluginBinding)
            reattachementCount.incrementAndGet()
            println("SuperwallkitFlutterPlugin: onAttachedToEngine - reattachment count: ${reattachementCount.get()}")
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationLifecycle.set(ApplicationLifecycle.TRANSITIONING)
        CoroutineScope(Dispatchers.Main).launch {
            try {
                // Call tearDown, but our modified version preserves the instance
                BridgingCreator.shared().tearDown()
                println("SuperwallkitFlutterPlugin: onDetachedFromEngine - plugin instance preserved")
                // Don't set instance to null - we need to maintain the reference
            } catch (e: Exception) {
                println("Error during plugin detachment: ${e.message}")
                e.printStackTrace()
            }
        }
    }

    //region ActivityAware

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        currentActivity = binding.activity
        applicationLifecycle.set(ApplicationLifecycle.FOREGROUND)
        
        // Proactively check and reattach if needed when coming to foreground
        CoroutineScope(Dispatchers.Main).launch {
            try {
                if (!BridgingCreator.checkPluginHealth()) {
                    // App is coming to foreground, ensure plugin is registered
                    println("SuperwallkitFlutterPlugin: Plugin health check failed, forcing reattachment")
                    val flutterBinding = BridgingCreator.lastKnownBinding
                    BridgingCreator.forceReattachment(flutterBinding)
                } else {
                    println("SuperwallkitFlutterPlugin: Plugin health check passed")
                }
            } catch (e: Exception) {
                println("Error during health check in onAttachedToActivity: ${e.message}")
                e.printStackTrace()
            }
        }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        applicationLifecycle.set(ApplicationLifecycle.TRANSITIONING)
        currentActivity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        currentActivity = binding.activity
        applicationLifecycle.set(ApplicationLifecycle.FOREGROUND)
        
        // Check health after configuration changes too
        CoroutineScope(Dispatchers.Main).launch {
            try {
                if (!BridgingCreator.checkPluginHealth()) {
                    println("SuperwallkitFlutterPlugin: Plugin health check failed after config change, forcing reattachment")
                    val flutterBinding = BridgingCreator.lastKnownBinding
                    BridgingCreator.forceReattachment(flutterBinding)
                }
            } catch (e: Exception) {
                println("Error during health check in onReattachedToActivityForConfigChanges: ${e.message}")
                e.printStackTrace()
            }
        }
    }

    override fun onDetachedFromActivity() {
        applicationLifecycle.set(ApplicationLifecycle.BACKGROUND)
        currentActivity = null
    }

    //endregion
}

fun <T> MethodCall.argumentForKey(key: String): T? {
    return this.argument(key)
}

// Enhanced bridgeInstance with better error handling
suspend fun <T> MethodCall.bridgeInstance(key: String): T? {
    BreadCrumbs.append("SuperwallKitFlutterPlugin.kt: Invoke bridgeInstance(key:) on $this. Key is $key")
    val bridgeId = this.argument<String>(key)
    if (bridgeId == null) {
        Log.e("SWKP", "No bridgeId found for key: $key")
        return null
    }
    
    try {
        BreadCrumbs.append("SuperwallKitFlutterPlugin.kt: Invoke bridgeInstance(key:) in on $this. Found bridgeId $bridgeId")
        return BridgingCreator.shared().bridgeInstance(bridgeId)
    } catch (e: Exception) {
        // If we can't get the instance, try to force reattachment and retry once
        Log.e("SWKP", "Error getting bridge instance: ${e.message}")
        BridgingCreator.forceReattachment(BridgingCreator.lastKnownBinding)
        kotlinx.coroutines.delay(300) // Brief delay to allow reattachment
        
        // One more try
        try {
            return BridgingCreator.shared().bridgeInstance(bridgeId)
        } catch (e2: Exception) {
            Log.e("SWKP", "Failed to get bridge instance after reattachment: ${e2.message}")
            throw e2
        }
    }
}

suspend fun <T> BridgeId.bridgeInstance(): T? {
    BreadCrumbs.append("SuperwallKitFlutterPlugin.kt: Invoke bridgeInstance() in on $this")
    try {
        return BridgingCreator.shared().bridgeInstance(this)
    } catch (e: Exception) {
        // If we can't get the instance, try to force reattachment and retry once
        Log.e("SWKP", "Error getting bridge instance: ${e.message}")
        BridgingCreator.forceReattachment(BridgingCreator.lastKnownBinding)
        kotlinx.coroutines.delay(300) // Brief delay to allow reattachment
        
        // One more try
        return BridgingCreator.shared().bridgeInstance(this)
    }
}

fun MethodChannel.Result.badArgs(call: MethodCall) {
    return badArgs(call.method)
}

fun MethodChannel.Result.badArgs(method: String) {
    return error("BAD_ARGS", "Missing or invalid arguments for '$method'", null)
}

fun MethodChannel.invokeMethodOnMain(method: String, arguments: Any? = null) {
    runOnUiThread {
        try {
            invokeMethod(method, arguments);
        } catch (e: Exception) {
            Log.e("SWKP", "Error invoking method $method: ${e.message}")
        }
    }
}

suspend fun MethodChannel.asyncInvokeMethodOnMain(method: String, arguments: Any? = null): Any? =
    suspendCancellableCoroutine { continuation ->
        runOnUiThread {
            try {
                invokeMethod(method, arguments, object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        if (!continuation.isCompleted) {
                            continuation.resume(result)
                        }
                    }

                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                        if (!continuation.isCompleted) {
                            continuation.resumeWithException(
                                RuntimeException("Error invoking method: $errorCode, $errorMessage")
                            )
                        }
                    }

                    override fun notImplemented() {
                        if (!continuation.isCompleted) {
                            continuation.resumeWithException(
                                UnsupportedOperationException("Method not implemented: $method")
                            )
                        }
                    }
                })
            } catch (e: Exception) {
                if (!continuation.isCompleted) {
                    continuation.resumeWithException(e)
                }
            }
        }
    }

fun <T> Map<String, Any?>.argument(key: String): T? {
    return this[key] as? T
}

object MethodChannelAssociations {
    private val bridgeIds = WeakHashMap<MethodChannel, String>()

    fun setBridgeId(methodChannel: MethodChannel, bridgeId: String) {
        bridgeIds[methodChannel] = bridgeId
    }

    fun getBridgeId(methodChannel: MethodChannel): String {
        return bridgeIds[methodChannel]
            ?: throw IllegalStateException("bridgeId must be set at initialization of MethodChannel")
    }
}

fun MethodChannel.setBridgeId(bridgeId: String) {
    MethodChannelAssociations.setBridgeId(this, bridgeId)
}

fun MethodChannel.getBridgeId(): String {
    return MethodChannelAssociations.getBridgeId(this)
}