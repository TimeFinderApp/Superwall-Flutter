import 'dart:async';
import 'dart:collection';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

// The name of the bridging class on the native side
typedef BridgeClass = String;

// The identifier of the bridge instance
typedef BridgeId = String;

// Plugin state management for tracking attachment status
enum _PluginState {
  attached,
  detached,
  attaching,
}

// Retry request class for queueing method calls during plugin reattachment
class _RetryRequest {
  final MethodChannel channel;
  final String method;
  final Map<String, Object?>? arguments;
  final Completer completer;
  
  _RetryRequest(this.channel, this.method, this.arguments, this.completer);
  
  void execute() {
    channel.invokeMethod(method, arguments).then((result) {
      completer.complete(result);
    }).catchError((error) {
      completer.completeError(error);
    });
  }
}

// Plugin state manager to track the plugin's attachment status
class _PluginStateManager {
  static _PluginState _state = _PluginState.attached;
  static final _retryQueue = Queue<_RetryRequest>();
  static final _lock = Object();
  static bool _isReattaching = false;
  
  // Mark plugin as detached
  static void markDetached() {
    _state = _PluginState.detached;
  }
  
  // Mark plugin as attached and process any queued requests
  static void markAttached() {
    _state = _PluginState.attached;
    _processRetryQueue();
  }
  
  // Mark plugin as being in the process of attaching
  static void markAttaching() {
    _state = _PluginState.attaching;
  }
  
  // Add a request to the retry queue
  static void queueRequest(_RetryRequest request) {
    _retryQueue.add(request);
  }
  
  // Get current plugin state
  static _PluginState get state => _state;
  
  // Process all queued requests
  static void _processRetryQueue() {
    if (_state == _PluginState.attached && _retryQueue.isNotEmpty) {
      // Execute all queued requests
      final requests = List<_RetryRequest>.from(_retryQueue);
      _retryQueue.clear();
      
      for (final request in requests) {
        request.execute();
      }
    }
  }
  
  // Force plugin reattachment
  static Future<bool> forceReattachment() async {
    if (_isReattaching) return false;
    
    try {
      _isReattaching = true;
      markAttaching();
      
      final result = await BridgingCreator._channel.invokeMethod('forceReattachment');
      markAttached();
      _isReattaching = false;
      return result == true;
    } catch (e) {
      debugPrint('Error during plugin reattachment: $e');
      _isReattaching = false;
      return false;
    }
  }
  
  // Check plugin health
  static Future<bool> checkPluginHealth() async {
    try {
      final result = await BridgingCreator._channel.invokeMethod('checkPluginHealth');
      if (result == true) {
        markAttached();
      } else {
        markDetached();
      }
      return result == true;
    } catch (e) {
      debugPrint('Error checking plugin health: $e');
      markDetached();
      return false;
    }
  }
}

class BridgingCreator {
  static const MethodChannel _channel = MethodChannel('SWK_BridgingCreator');

  // Stores argument metadata provided during the creation of the bridgeId.
  // This will later be used when invoking creation to pass in initialization arguments
  static final Map<String, Map<String, dynamic>> _metadataByBridgeId = {};
  
  // Initialize plugin state
  static bool _initialized = false;
  
  // Initialize the plugin state manager
  static void _ensureInitialized() {
    if (!_initialized) {
      _initialized = true;
      // Add an app lifecycle observer here if needed
    }
  }

  static BridgeId _createBridgeId({
    String? givenId,
    required BridgeClass bridgeClass,
    Map<String, dynamic>? initializationArgs,
  }) {
    _ensureInitialized();
    BridgeId bridgeId = givenId ?? bridgeClass.generateBridgeId();
    _metadataByBridgeId[bridgeId] = {'args': initializationArgs};

    return bridgeId;
  }

  static Future<void> _invokeBridgeInstanceCreation(BridgeId bridgeId) async {
    Map<String, dynamic> metadata =
        BridgingCreator._metadataByBridgeId[bridgeId] ?? {};
    Map<String, dynamic>? initializationArgs = metadata['args'];

    try {
      await _channel.invokeMethod('createBridgeInstance', {
        'bridgeId': bridgeId,
        'args': initializationArgs,
      });
      
      metadata['bridgeInstanceCreated'] = 'true';
      _metadataByBridgeId[bridgeId] = metadata;
      _PluginStateManager.markAttached();
    } catch (e) {
      if (e is PlatformException && e.code == 'MissingPluginException') {
        // Plugin is detached, try to reattach
        _PluginStateManager.markDetached();
        final reattached = await _PluginStateManager.forceReattachment();
        
        if (reattached) {
          // Try again after reattachment
          await _channel.invokeMethod('createBridgeInstance', {
            'bridgeId': bridgeId,
            'args': initializationArgs,
          });
          
          metadata['bridgeInstanceCreated'] = 'true';
          _metadataByBridgeId[bridgeId] = metadata;
        } else {
          throw PlatformException(
            code: 'ReattachmentFailed',
            message: 'Failed to reattach plugin after MissingPluginException',
          );
        }
      } else {
        rethrow;
      }
    }
  }

  static Future<void> _ensureBridgeCreated(
    BridgeId bridgeId, {
    bool forceRecreate = false,
  }) async {
    Map<String, dynamic>? metadata = _metadataByBridgeId[bridgeId];

    // Force recreation if requested
    if (forceRecreate && metadata != null) {
      metadata.remove('bridgeInstanceCreated');
      _metadataByBridgeId[bridgeId] = metadata;
    }

    // If metadata is not null, this bridge was already created on the Dart
    // side here, so you must invoke creation of the instance on the native side.
    if (metadata != null && metadata['bridgeInstanceCreated'] == null) {
      await _invokeBridgeInstanceCreation(bridgeId);
    }
  }
}

// A protocol that Dart classes should conform to if they want to be able to
// create a BridgeId, or instantiate themselves from a BridgeID
abstract class BridgeIdInstantiable {
  BridgeId bridgeId;

  BridgeIdInstantiable({
    required BridgeClass bridgeClass,
    BridgeId? bridgeId,
    BridgeId? givenId,
    Map<String, dynamic>? initializationArgs,
  }) : bridgeId =
           bridgeId ??
           BridgingCreator._createBridgeId(
             givenId: givenId,
             bridgeClass: bridgeClass,
             initializationArgs: initializationArgs,
           ) {
    assert(
      this.bridgeId.endsWith('-bridgeId'),
      'Make sure bridgeIds end with "-bridgeId"',
    );
    this.bridgeId.associate(this);
    this.bridgeId.communicator.setMethodCallHandler(handleMethodCall);
  }

  // Handle method calls from native (subclasses should implement)
  Future<dynamic> handleMethodCall(MethodCall call) async {}
}

extension MethodChannelBridging on MethodChannel {
  // Enhanced invokeBridgeMethod with exponential backoff
  Future<T?> invokeBridgeMethod<T>(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
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
    
    // Use robust retry mechanism with exponential backoff
    int attempts = 0;
    int maxAttempts = 5;
    int baseDelayMs = 100;
    
    while (attempts < maxAttempts) {
      try {
        return await invokeMethod(method, arguments);
      } catch (e) {
        if (e is PlatformException && e.code == 'MissingPluginException') {
          attempts++;
          
          if (attempts >= maxAttempts) {
            // Create a meaningful error message
            throw PlatformException(
              code: 'MissingPluginException',
              message: 'Plugin not available after $maxAttempts attempts',
              details: 'Channel: ${name}, Method: $method'
            );
          }
          
          // Mark plugin as detached
          _PluginStateManager.markDetached();
          
          // Try plugin health check and reattachment for more serious issues
          if (attempts > 2) {
            // Create a completer for this request
            final completer = Completer<T?>();
            
            // Add to retry queue
            _PluginStateManager.queueRequest(
              _RetryRequest(this, method, arguments, completer)
            );
            
            // Try to force reattachment
            final reattached = await _PluginStateManager.forceReattachment();
            if (!reattached) {
              // If we can't reattach, try to force recreation of bridge
              await bridgeId.ensureBridgeCreated(forceRecreate: true);
            }
            
            return completer.future as Future<T?>;
          }
          
          // Exponential backoff
          final delayMs = baseDelayMs * (1 << (attempts - 1));
          await Future.delayed(Duration(milliseconds: delayMs));
          continue;
        }
        rethrow;
      }
    }
    
    throw StateError('Unexpected state in invokeBridgeMethod');
  }

  BridgeId get bridgeId {
    return name;
  }
}

extension FlutterMethodCall on MethodCall {
  T? argument<T>(String key) {
    return arguments[key] as T?;
  }

  BridgeId bridgeId(String key) {
    final BridgeId? bridgeId = argument<String>(key);
    assert(
      bridgeId != null,
      'Attempting to fetch a bridge Id in Dart that has '
      'not been created by the BridgeCreator natively.',
    );

    return bridgeId ?? '';
  }
}

// Stores a reference to a dart instance that receives responses from the native side.
extension BridgeAssociation on BridgeId {
  static final List<dynamic> associatedInstances = [];

  associate(dynamic dartInstance) {
    BridgeAssociation.associatedInstances.add(dartInstance);
  }
}

extension BridgeAdditions on BridgeId {
  MethodChannel get communicator {
    return MethodChannel(this);
  }

  EventChannel get eventStream {
    return EventChannel("$this/events");
  }

  BridgeClass get bridgeClass {
    return split('-').first;
  }

  // Enhanced ensureBridgeCreated with force option
  Future<void> ensureBridgeCreated({bool forceRecreate = false}) async {
    await BridgingCreator._ensureBridgeCreated(this, forceRecreate: forceRecreate);
    if (!forceRecreate) {
      _PluginStateManager.markAttached();
    }
  }
}

extension StringExtension on String {
  bool get isBridgeId {
    return endsWith('-bridgeId');
  }
}

extension Additions on BridgeClass {
  // Make sure this is the same on the Native side.
  BridgeId generateBridgeId() {
    final bridgeId = '$this-bridgeId';
    return bridgeId;
  }
}
