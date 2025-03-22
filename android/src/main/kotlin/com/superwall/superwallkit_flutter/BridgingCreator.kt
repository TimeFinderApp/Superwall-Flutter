package com.superwall.superwallkit_flutter

import android.os.Handler
import android.os.Looper
import android.util.Log
import com.superwall.superwallkit_flutter.bridges.BridgeClass
import com.superwall.superwallkit_flutter.bridges.BridgeId
import com.superwall.superwallkit_flutter.bridges.BridgeInstance
import com.superwall.superwallkit_flutter.bridges.Communicator
import com.superwall.superwallkit_flutter.bridges.bridgeClass
import com.superwall.superwallkit_flutter.bridges.generateBridgeId
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.filterNotNull
import java.util.concurrent.ConcurrentHashMap
import io.flutter.embedding.android.FlutterActivity
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.atomic.AtomicReference

// Plugin state enum to track attachment status
enum class PluginState {
    ATTACHED, DETACHED, ATTACHING
}

class BridgingCreator(
    val flutterPluginBinding: suspend () -> FlutterPlugin.FlutterPluginBinding,
    val scope: CoroutineScope = CoroutineScope(Dispatchers.IO)
) : MethodCallHandler {
    private val instances: MutableMap<String, BridgeInstance> = ConcurrentHashMap()

    object Constants {}

    companion object {
        private val lock = Any()
        private var _shared: MutableStateFlow<BridgingCreator?> = MutableStateFlow(null)
        
        // Add plugin state tracking
        private val pluginState = AtomicReference<PluginState>(PluginState.DETACHED)
        
        // Static reference to last known binding
        @Volatile
        var lastKnownBinding: FlutterPlugin.FlutterPluginBinding? = null
            private set

        // Main thread handler for UI operations
        private val mainHandler = Handler(Looper.getMainLooper())
            
        suspend fun shared() : BridgingCreator = _shared.filterNotNull().first()

        private var _flutterPluginBinding: MutableStateFlow<FlutterPlugin.FlutterPluginBinding?> =
            MutableStateFlow(null)

        suspend fun waitForPlugin() : FlutterPlugin.FlutterPluginBinding {
            return _flutterPluginBinding.filterNotNull().first()
        }
        
        // Add method to force reattachment
        fun forceReattachment(binding: FlutterPlugin.FlutterPluginBinding?) {
            val currentState = pluginState.get()
            if (currentState != PluginState.ATTACHED) {
                // Set state to attaching to prevent concurrent attempts
                if (!pluginState.compareAndSet(currentState, PluginState.ATTACHING)) {
                    // Another thread is already attaching
                    return
                }
                
                synchronized(lock) {
                    try {
                        // Use last known binding if available
                        val bindingToUse = binding ?: lastKnownBinding
                        if (bindingToUse == null) {
                            pluginState.set(PluginState.DETACHED) // Reset state
                            println("ERROR: No binding available for reattachment")
                            return
                        }
                        
                        // Execute on main thread to avoid potential threading issues
                        mainHandler.post {
                            try {
                                // Create new bridge instance
                                val bridge = BridgingCreator({ bindingToUse })
                                _shared.value = bridge
                                _flutterPluginBinding.value = bindingToUse
                                val communicator = Communicator(bindingToUse.binaryMessenger, "SWK_BridgingCreator")
                                communicator.setMethodCallHandler(bridge)
                                
                                pluginState.set(PluginState.ATTACHED)
                                println("Successfully reattached Superwall plugin")
                            } catch (e: Exception) {
                                pluginState.set(PluginState.DETACHED) // Reset state on error
                                println("Error during plugin reattachment on main thread: ${e.message}")
                                e.printStackTrace()
                            }
                        }
                    } catch (e: Exception) {
                        pluginState.set(PluginState.DETACHED) // Reset state on error
                        println("Error during plugin reattachment: ${e.message}")
                        e.printStackTrace()
                    }
                }
            }
        }
        
        // Add method to check plugin health
        fun checkPluginHealth(): Boolean {
            return pluginState.get() == PluginState.ATTACHED && _shared.value != null
        }
        
        fun setFlutterPlugin(binding: FlutterPlugin.FlutterPluginBinding) {
            // Save last known binding first (even if we don't use it now)
            lastKnownBinding = binding
            
            // Only allow binding to occur once unless we're deliberately reattaching
            if (_flutterPluginBinding.value != null && pluginState.get() == PluginState.ATTACHED) {
                println("WARNING: Attempting to set a flutter plugin binding again. Current state: ${pluginState.get()}")
                return
            }

            binding?.let {
                synchronized(lock) {
                    val bridge = BridgingCreator({ waitForPlugin() })
                    _shared.value = bridge
                    _flutterPluginBinding.value = binding
                    val communicator = Communicator(binding.binaryMessenger, "SWK_BridgingCreator")
                    communicator.setMethodCallHandler(bridge)
                    
                    // Update plugin state to attached
                    pluginState.set(PluginState.ATTACHED)
                    println("Superwall plugin successfully attached")
                }
            }
        }
    }

    // Enhanced tearDown that tracks state but preserves instance
    fun tearDown() {
        // Mark as detached but maintain references for later reattachment
        pluginState.set(PluginState.DETACHED)
        println("BridgingCreator tearDown called - maintaining instance for reattachment")
        // Do NOT set _shared.value = null
        // Do NOT set _flutterPluginBinding.value = null
    }

    // Enhanced bridgeInstance with retry logic
    suspend fun <T> bridgeInstance(bridgeId: BridgeId): T? {
        var attempts = 0
        val maxAttempts = 3
        
        while (attempts < maxAttempts) {
            try {
                BreadCrumbs.append("BridgingCreator.kt: Searching for $bridgeId among ${instances.count()}: ${instances.toFormattedString()}")
                var instance = instances[bridgeId] as? T
                
                if (instance == null) {
                    if (attempts < maxAttempts - 1) {
                        // Try reattachment before final attempt
                        val binding = SuperwallkitFlutterPlugin.instance?.let { 
                            _flutterPluginBinding.value ?: lastKnownBinding 
                        }
                        forceReattachment(binding)
                        delay(300L * (attempts + 1)) // Exponential backoff
                        attempts++
                        continue
                    }
                    throw AssertionError("Unable to find a native instance for $bridgeId after $attempts attempts. Logs: ${BreadCrumbs.logs()}")
                }
                
                return instance
            } catch (e: Exception) {
                if (attempts < maxAttempts - 1) {
                    attempts++
                    delay(300L * (attempts + 1)) // Exponential backoff
                    continue
                }
                throw e
            }
        }
        
        throw AssertionError("Maximum retry attempts exceeded for $bridgeId")
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        scope.launch {
            try {
                when (call.method) {
                    "createBridgeInstance" -> {
                        val bridgeId = call.argument<String>("bridgeId")
                        val initializationArgs = call.argument<Map<String, Any>>("args")
                        if (bridgeId != null) {
                            createBridgeInstanceFromBridgeId(bridgeId, initializationArgs)
                            result.success(null)
                        } else {
                            println("WARNING: Unable to create bridge")
                            result.badArgs(call)
                        }
                    }
                    "checkPluginHealth" -> {
                        // New method to allow Dart side to check plugin health
                        result.success(checkPluginHealth())
                    }
                    "forceReattachment" -> {
                        // New method to allow Dart side to force reattachment
                        val binding = _flutterPluginBinding.value ?: lastKnownBinding
                        forceReattachment(binding)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                println("Error in BridgingCreator.onMethodCall: ${e.message}")
                e.printStackTrace()
                result.error("EXCEPTION", e.message, null)
            }
        }
    }

    // Create the bridge instance as instructed from Dart
    private suspend fun createBridgeInstanceFromBridgeId(
        bridgeId: BridgeId,
        initializationArgs: Map<String, Any>?
    ): BridgeInstance {
        val existingBridgeInstance = instances[bridgeId]

        existingBridgeInstance?.let {
            if(existingBridgeInstance.cachable)
                return it
        }

        val bridgeInstance = bridgeInitializers[bridgeId.bridgeClass()]?.invoke(
            flutterPluginBinding().applicationContext,
            bridgeId,
            initializationArgs
        )

        bridgeInstance?.let { bridgeInstance ->
            instances[bridgeId] = bridgeInstance
            bridgeInstance.communicator().setMethodCallHandler(bridgeInstance)
            bridgeInstance.events()
            return bridgeInstance
        } ?: run {
            throw AssertionError("Unable to find a bridge initializer for ${bridgeId}. Make sure to add to BridgingCreator+Constants.kt.}")
        }
    }

    // Create the bridge instance as instructed from native
    suspend fun createBridgeInstanceFromBridgeClass(
        bridgeClass: BridgeClass,
        initializationArgs: Map<String, Any>? = null
    ): BridgeInstance {
        return createBridgeInstanceFromBridgeId(bridgeClass.generateBridgeId(), initializationArgs)
    }
}