# Superwall Flutter Plugin 2.x Fix Plan (Minimal Approach)

## Overview

This document outlines a focused, minimal plan to address the `MissingPluginException` issue in the Superwall Flutter plugin 2.x version. The issue occurs when the app moves to background and then foreground, causing plugin registration loss during Flutter engine detachment events.

## Root Cause Analysis

The `MissingPluginException` in the 2.x version is primarily caused by:

1. During app backgrounding, Flutter's engine detaches from native C++
2. The plugin's `tearDown()` method completely nullifies the plugin instance
3. When the app returns to foreground, method calls fail before the plugin re-registers

## Focused Approach

We will apply a minimal, targeted approach focused on preserving plugin state during detachment events:

1. Maintain a reference to the last known FlutterPluginBinding
2. Prevent complete plugin teardown during detachment
3. Add minimal retry for method calls in the Dart layer

## Implementation Plan

### 1. BridgingCreator.kt Modifications

**File**: `/Users/lukememet/Developer/Superwall-Flutter/android/src/main/kotlin/com/superwall/superwallkit_flutter/BridgingCreator.kt`

Key changes:

- Add a static reference to the last known binding
- Modify `tearDown()` to preserve the instance

```kotlin
class BridgingCreator(
    val flutterPluginBinding: suspend () -> FlutterPlugin.FlutterPluginBinding,
    val scope: CoroutineScope = CoroutineScope(Dispatchers.IO)
) : MethodCallHandler {
    // Existing code...

    companion object {
        // Add static reference to last known binding
        @Volatile
        var lastKnownBinding: FlutterPlugin.FlutterPluginBinding? = null
            private set

        // Existing shared method and other companion object code...

        fun setFlutterPlugin(binding: FlutterPlugin.FlutterPluginBinding) {
            // Save last known binding first (even if we don't use it now)
            lastKnownBinding = binding

            // Rest of existing method remains unchanged...
            if (_flutterPluginBinding.value != null) {
                println("WARNING: Attempting to set a flutter plugin binding again.")
                return
            }

            binding?.let {
                synchronized(BridgingCreator::class.java) {
                    val bridge = BridgingCreator({ waitForPlugin() })
                    _shared.value = bridge
                    _flutterPluginBinding.value = binding
                    val communicator = Communicator(binding.binaryMessenger, "SWK_BridgingCreator")
                    communicator.setMethodCallHandler(bridge)
                }
            }
        }
    }

    // Critical change: Don't fully tear down the instance
    fun tearDown() {
        // Only print a log, don't nullify shared instance
        println("BridgingCreator tearDown called - maintaining instance for reattachment")
        // Do NOT set _shared.value = null
        // Do NOT set _flutterPluginBinding.value = null
    }

    // Rest of class remains unchanged...
}
```

### 2. SuperwallkitFlutterPlugin.kt Modifications

**File**: `/Users/lukememet/Developer/Superwall-Flutter/android/src/main/kotlin/com/superwall/superwallkit_flutter/SuperwallkitFlutterPlugin.kt`

Key change:

- Modify `onDetachedFromEngine` to only partially tear down the plugin

```kotlin
class SuperwallkitFlutterPlugin : FlutterPlugin, ActivityAware {
    // Existing code...

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // Minimal change: don't nullify instance
        CoroutineScope(Dispatchers.Main).launch {
            // Call tearDown, but our modified version preserves the instance
            BridgingCreator.shared().tearDown()
            // Don't set instance to null
            // instance = null
        }
    }

    // Rest of class remains unchanged...
}
```

### 3. BridgingCreator.dart Modifications

**File**: `/Users/lukememet/Developer/Superwall-Flutter/lib/src/private/BridgingCreator.dart`

Key change:

- Add basic retry for MissingPluginException only

```dart
// Update MethodChannelBridging extension with minimal retry
extension MethodChannelBridging on MethodChannel {
  Future<T?> invokeBridgeMethod<T>(String method,
      [Map<String, Object?>? arguments]) async {
    // Existing code for handling arguments and ensuring bridge created

    // Check if arguments is a Map and contains native IDs
    if (arguments != null) {
      for (var value in arguments.values) {
        if (value is String && value.isBridgeId) {
          BridgeId bridgeId = value;
          await bridgeId.ensureBridgeCreated();
        }
      }
    }

    await bridgeId.ensureBridgeCreated();

    try {
      return invokeMethod(method, arguments);
    } catch (e) {
      // Simple retry for MissingPluginException only
      if (e is PlatformException && e.code == 'MissingPluginException') {
        // Wait briefly and retry once
        await Future.delayed(Duration(milliseconds: 300));
        return invokeMethod(method, arguments);
      }
      rethrow;
    }
  }
}
```

### 4. Version Updates and Changelog

**File**: `/Users/lukememet/Developer/Superwall-Flutter/pubspec.yaml`
Update the version number from 2.0.7 to 2.0.8

**File**: `/Users/lukememet/Developer/Superwall-Flutter/CHANGELOG.md`
Add entry:

```markdown
## 2.0.8

### Fixes

- Fixes MissingPluginException during app backgrounding/foregrounding on Android
- Maintains plugin state across Flutter engine detachment events
```

## Testing Plan

After implementing these minimal changes, the fix should be tested in these scenarios:

1. Backgrounding the app (home button) and returning after 30+ seconds
2. App switching rapidly between multiple apps
3. Device sleep/wake cycles while the app is in foreground and background

## Implementation Sequence

1. Implement BridgingCreator.kt changes first (maintain instance)
2. Update SuperwallkitFlutterPlugin.kt to match (prevent instance nullification)
3. Add minimal retry logic to the Dart layer
4. Update version and changelog
5. Test the focused scenarios

This minimal approach addresses the core issue (plugin deregistration during backgrounding) without introducing extensive changes throughout the codebase that might be rejected by the maintainers.
