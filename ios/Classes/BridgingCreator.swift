import Flutter
import UIKit
import SuperwallKit

/// Creates a method channel for a particular unique instance of a class
public class BridgingCreator: NSObject, FlutterPlugin {
  // TODO: CHANGE
  static var shared: BridgingCreator!

  struct Constants {
    static let bridgeMap: [String: BaseBridge.Type] = [
      "SuperwallBridge": SuperwallBridge.self,
      "SuperwallDelegateProxyBridge": SuperwallDelegateProxyBridge.self,
      "PurchaseControllerProxyBridge": PurchaseControllerProxyBridge.self,
      "CompletionBlockProxyBridge": CompletionBlockProxyBridge.self,
      "SubscriptionStatusActiveBridge": SubscriptionStatusActiveBridge.self,
      "SubscriptionStatusInactiveBridge": SubscriptionStatusInactiveBridge.self,
      "SubscriptionStatusUnknownBridge": SubscriptionStatusUnknownBridge.self,
      "PaywallPresentationHandlerProxyBridge": PaywallPresentationHandlerProxyBridge.self,
    ]
  }

  private let registrar: FlutterPluginRegistrar
  private var instances: [String: Any] = [:]

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
  }

  func bridge<T>(for channelName: String) -> T? {
    var instance = instances[channelName] as? T

    if instance == nil {
      guard let bridgeName = channelName.components(separatedBy: "-").first else {
        assertionFailure("Unable to parse bridge name from \(channelName).")
        return nil
      }

      instance = createBridge(bridgeName: bridgeName, channelName: channelName) as? T

      guard instance != nil else {
        assertionFailure("Unable to create bridge name from \(channelName).")
        return nil
      }
    }

    return instance
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "SWK_BridgingCreator", binaryMessenger: registrar.messenger())

    let bridge = BridgingCreator(registrar: registrar)
    BridgingCreator.shared = bridge

    registrar.addMethodCallDelegate(bridge, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
      case "createBridge":
        guard
          let bridgeName: String = call.argument(for: "bridgeName"),
          let channelName: String = call.argument(for: "channelName") else {
          print("WARNING: Unable to create bridge")
          return
        }

        createBridge(bridgeName: bridgeName, channelName: channelName)
        result(nil)

      default:
        result(FlutterMethodNotImplemented)
    }
  }

  @discardableResult private func createBridge(bridgeName: String, channelName: String) -> BaseBridge? {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())

    guard let classType = BridgingCreator.Constants.bridgeMap[bridgeName] else {
      assertionFailure("Unable to find a bridge type for \(bridgeName). Make sure to add to BridgingCreator.swift")
      return nil
    }

    let bridge = classType.init(channel: channel)
    instances.updateValue(bridge, forKey: channelName)

    registrar.addMethodCallDelegate(bridge, channel: channel)

    return bridge
  }
}

extension String {
  func toJson() -> [String: String] {
    return ["value": self]
  }
}