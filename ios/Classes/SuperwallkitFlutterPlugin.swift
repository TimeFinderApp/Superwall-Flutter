import Flutter
import UIKit
import SuperwallKit

// Application lifecycle tracking enum
enum ApplicationLifecycle {
  case foreground
  case background
  case transitioning
}

public class SuperwallkitFlutterPlugin: NSObject, FlutterPlugin {
  private static var alreadyRegistered = false
  
  // Track application lifecycle
  private static var applicationLifecycle: ApplicationLifecycle = .background
  
  // Count for debugging purposes
  private static var reattachmentCount = 0

  public static func register(with registrar: FlutterPluginRegistrar) {
    // This should get called on the main thread by default
    if alreadyRegistered {
      // Even if already registered, update the registrar for potential reattachment
      reattachmentCount += 1
      print("SuperwallkitFlutterPlugin: register called again, count: \(reattachmentCount)")
      return
    }
    
    alreadyRegistered = true
    print("SuperwallkitFlutterPlugin: First registration")

    // Register for app lifecycle notifications
    NotificationCenter.default.addObserver(
      forName: UIApplication.didEnterBackgroundNotification, 
      object: nil, 
      queue: nil
    ) { _ in
      applicationLifecycle = .background
      print("SuperwallkitFlutterPlugin: App entered background")
    }
    
    NotificationCenter.default.addObserver(
      forName: UIApplication.willEnterForegroundNotification, 
      object: nil, 
      queue: nil
    ) { _ in
      applicationLifecycle = .transitioning
      print("SuperwallkitFlutterPlugin: App will enter foreground")
      
      // Check plugin health when coming to foreground
      DispatchQueue.main.async {
        if !BridgingCreator.checkPluginHealth() {
          print("SuperwallkitFlutterPlugin: Plugin health check failed, forcing reattachment")
          _ = BridgingCreator.forceReattachment()
        } else {
          print("SuperwallkitFlutterPlugin: Plugin health check passed")
        }
      }
    }
    
    NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification, 
      object: nil, 
      queue: nil
    ) { _ in
      applicationLifecycle = .foreground
      print("SuperwallkitFlutterPlugin: App became active")
    }

    BridgingCreator.register(with: registrar)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    result(FlutterMethodNotImplemented)
  }
  
  deinit {
    NotificationCenter.default.removeObserver(self)
  }
}

extension FlutterMethodCall {
  func argument<T>(for key: String) -> T? {
    return (arguments as? [String: Any])?[key] as? T
  }

  // Enhanced bridgeInstance with retry
  func bridgeInstance(for key: String) -> Any? {
    guard let bridgeId: String = argument(for: key) else {
      return nil
    }

    // First attempt
    if let instance = BridgingCreator.shared.bridgeInstance(for: bridgeId) {
      return instance
    }
    
    // Not found, try reattachment and try again
    if BridgingCreator.forceReattachment() {
      print("Reattached plugin, trying to get bridge instance again")
      if let instance = BridgingCreator.shared.bridgeInstance(for: bridgeId) {
        return instance
      }
    }
    
    return nil
  }
  
  // Type-specific convenience method
  func bridgeInstanceTyped<T>(for key: String) -> T? {
    guard let instance = bridgeInstance(for: key) else {
      return nil
    }
    return instance as? T
  }
}

extension BridgeId {
  func bridgeInstance() -> Any? {
    // First attempt
    if let instance = BridgingCreator.shared.bridgeInstance(for: self) {
      return instance
    }
    
    // Not found, try reattachment and try again
    if BridgingCreator.forceReattachment() {
      print("Reattached plugin, trying to get bridge instance again")
      if let instance = BridgingCreator.shared.bridgeInstance(for: self) {
        return instance
      }
    }
    
    return nil
  }
  
  // Type-specific convenience method
  func bridgeInstanceTyped<T>() -> T? {
    guard let instance = bridgeInstance() else {
      return nil
    }
    return instance as? T
  }
}

extension FlutterMethodCall {
  var badArgs: FlutterError {
    return FlutterError(code: "BAD_ARGS", message: "Missing or invalid arguments for '\(method)'", details: nil)
  }
}

extension FlutterMethodChannel {
  func invokeMethodOnMain(_ method: String, arguments: Any? = nil) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        invokeMethod(method, arguments: arguments)
      } catch {
        print("Error invoking method \(method): \(error)")
      }
    }
  }

  @MainActor
  @discardableResult func asyncInvokeMethodOnMain(_ method: String, arguments: Any? = nil) async -> Any? {
    return await withCheckedContinuation { [weak self] continuation in
      guard let self else { 
        continuation.resume(returning: nil)
        return
      }
      
      do {
        invokeMethod(method, arguments: arguments) { result in
          continuation.resume(returning: result)
        }
      } catch {
        continuation.resume(returning: nil)
      }
    }
  }
}

extension Dictionary where Key == String {
  func argument<T>(for key: String) -> T? {
    return self[key] as? T
  }
}

extension FlutterMethodChannel {
  private static var bridgeIdKey: UInt8 = 0

  var bridgeId: String {
    get {
      guard let name = objc_getAssociatedObject(self, &FlutterMethodChannel.bridgeIdKey) as? String else {
        assertionFailure("bridgeId must be set at initialization of FlutterMethodChannel")
        return ""
      }

      return name
    }
    set(newValue) {
      objc_setAssociatedObject(self, &FlutterMethodChannel.bridgeIdKey, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }
}
