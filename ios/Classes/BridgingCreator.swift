import Flutter
import SuperwallKit
import UIKit

/// Plugin state enum to track attachment status
enum PluginState {
  case attached
  case detached
  case attaching
}

/// Creates a method channel for a particular unique instance of a class
public class BridgingCreator: NSObject, FlutterPlugin {
  static private var _shared: BridgingCreator? = nil
  static var shared: BridgingCreator {
    guard let shared = _shared else {
      fatalError(
        "Attempting to access the shared BridgingCreator before `register(with registrar: FlutterPluginRegistrar)` has been called."
      )
    }

    return shared
  }
  
  // Add state tracking
  private static var pluginState: PluginState = .detached
  
  // Keep reference to last registrar for reattachment
  private static var lastRegistrar: FlutterPluginRegistrar?
  
  // Check if plugin is healthy
  static func checkPluginHealth() -> Bool {
    return pluginState == .attached && _shared != nil
  }
  
  // Force plugin reattachment
  static func forceReattachment() -> Bool {
    if pluginState == .attached {
      return true // Already attached
    }
    
    // Set state to attaching to prevent concurrent attempts
    pluginState = .attaching
    
    guard let registrar = lastRegistrar else {
      pluginState = .detached
      print("ERROR: No registrar available for reattachment")
      return false
    }
    
    do {
      let communicator = Communicator(
        name: "SWK_BridgingCreator", binaryMessenger: registrar.messenger())
      
      let bridge = BridgingCreator(registrar: registrar, communicator: communicator)
      BridgingCreator._shared = bridge
      
      registrar.addMethodCallDelegate(bridge, channel: communicator)
      pluginState = .attached
      print("Successfully reattached Superwall plugin")
      return true
    } catch {
      pluginState = .detached
      print("Error during plugin reattachment: \(error)")
      return false
    }
  }

  let registrar: FlutterPluginRegistrar

  private let communicator: Communicator
  private var instances: [String: BridgeInstance] = [:]

  init(registrar: FlutterPluginRegistrar, communicator: Communicator) {
    self.registrar = registrar
    self.communicator = communicator
    super.init()
  }

  // Enhanced bridgeInstance with better error handling and retry
  func bridgeInstance(for bridgeInstance: BridgeId) -> Any? {
    // Try to retrieve the instance
    if let instance = instances[bridgeInstance] {
      return instance
    }
    
    // If not found, check if we're detached and try to reattach
    if BridgingCreator.pluginState != .attached {
      if BridgingCreator.forceReattachment() {
        // Try again after reattachment
        return instances[bridgeInstance]
      }
    }
    
    // Still not found, provide better error message
    assertionFailure("Unable to find a bridge instance for \(bridgeInstance) after reattachment attempt.")
    return nil
  }
  
  // Type-specific convenience method
  func bridgeInstanceTyped<T>(for bridgeInstance: BridgeId) -> T? {
    if let instance = self.bridgeInstance(for: bridgeInstance) as? T {
      return instance
    }
    return nil
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    // Store registrar for later reattachment if needed
    lastRegistrar = registrar
    
    let communicator = Communicator(
      name: "SWK_BridgingCreator", binaryMessenger: registrar.messenger())

    let bridge = BridgingCreator(registrar: registrar, communicator: communicator)
    BridgingCreator._shared = bridge
    
    // Set plugin state to attached
    pluginState = .attached
    print("Superwall plugin successfully attached")

    registrar.addMethodCallDelegate(bridge, channel: communicator)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "createBridgeInstance":
      guard
        let bridgeId: String = call.argument(for: "bridgeId")
      else {
        print("WARNING: Unable to create bridge instance")
        result(FlutterError(code: "BAD_ARGS", message: "Missing bridgeId", details: nil))
        return
      }

      let initializationArgs: [String: Any]? = call.argument(for: "args")

      do {
        createBridgeInstance(bridgeId: bridgeId, initializationArgs: initializationArgs)
        result(nil)
      } catch {
        result(FlutterError(code: "CREATION_FAILED", message: "Bridge creation failed: \(error)", details: nil))
      }
    
    case "checkPluginHealth":
      // New method to allow Dart side to check plugin health
      result(BridgingCreator.checkPluginHealth())
      
    case "forceReattachment":
      // New method to allow Dart side to force reattachment
      result(BridgingCreator.forceReattachment())

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // Create the bridge instance as instructed from Dart
  @discardableResult
  private func createBridgeInstance(
    bridgeId: BridgeId, initializationArgs: [String: Any]? = nil
  ) -> BridgeInstance {
    // An existing bridge instance might exist if it were created natively, instead of from Dart
    if let existingBridgeInstance = instances[bridgeId] {
      return existingBridgeInstance
    }

    guard let bridgeClass = BridgingCreator.Constants.bridgeMap[bridgeId.bridgeClass] else {
      assertionFailure(
        "Unable to find a bridgeClass for \(bridgeId.bridgeClass). Make sure to add to BridgingCreator+Constants.swift"
      )
      return BridgeInstance(bridgeId: bridgeId, initializationArgs: initializationArgs)
    }

    let bridgeInstance = bridgeClass.init(
      bridgeId: bridgeId, initializationArgs: initializationArgs)
    instances.updateValue(bridgeInstance, forKey: bridgeId)

    registrar.addMethodCallDelegate(bridgeInstance, channel: bridgeInstance.communicator)
    bridgeInstance.events()
    return bridgeInstance
  }

  // Create the bridge instance as instructed from native
  func createBridgeInstance(bridgeClass: BridgeClass, initializationArgs: [String: Any]? = nil)
    -> BridgeInstance
  {
    return createBridgeInstance(
      bridgeId: bridgeClass.generateBridgeId(), initializationArgs: initializationArgs)
  }
}
