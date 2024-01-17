import 'package:flutter/services.dart';
import 'package:superwallkit_flutter/src/private/BridgingCreator.dart';
import 'package:superwallkit_flutter/src/public/PaywallInfo.dart';
import 'package:superwallkit_flutter/src/public/SubscriptionStatus.dart';
import 'package:superwallkit_flutter/src/public/SuperwallDelegate.dart';

class SuperwallDelegateProxy extends BridgeIdInstantiable {
  static const BridgeClass bridgeClass = "SuperwallDelegateProxyBridge";
  SuperwallDelegateProxy({required this.delegate, BridgeId? bridgeId}): super(bridgeClass: bridgeClass, bridgeId: bridgeId);

  SuperwallDelegate delegate;

  // Handle method calls from native
  @override
  Future<void> handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'willPresentPaywall':
        final bridgeId = call.bridgeId("paywallInfoBridgeId");
        final paywallInfo = PaywallInfo(bridgeId: bridgeId);
        delegate.willPresentPaywall(paywallInfo);
        break;
      case 'didPresentPaywall':
        final bridgeId = call.bridgeId("paywallInfoBridgeId");
        final paywallInfo = PaywallInfo(bridgeId: bridgeId);
        delegate.didPresentPaywall(paywallInfo);
        break;
      case 'willDismissPaywall':
        final bridgeId = call.bridgeId("paywallInfoBridgeId");
        final paywallInfo = PaywallInfo(bridgeId: bridgeId);
        delegate.willDismissPaywall(paywallInfo);
        break;
      case 'didDismissPaywall':
        final bridgeId = call.bridgeId("paywallInfoBridgeId");
        final paywallInfo = PaywallInfo(bridgeId: bridgeId);
        delegate.didDismissPaywall(paywallInfo);
        break;
      case 'handleCustomPaywallAction':
        final name = call.argument("name");
        delegate.handleCustomPaywallAction(name);
        break;
      case 'subscriptionStatusDidChange':
        final bridgeId = call.argument("subscriptionStatusBridgeId");
        final status = SubscriptionStatus.subscriptionStatusFrom(bridgeId);
        if (status != null) {
          delegate.subscriptionStatusDidChange(status);
        }
        break;
      case 'paywallWillOpenURL':
        final url = call.argument("url");
        delegate.paywallWillOpenURL(Uri.parse(url));
        break;
      case 'paywallWillOpenDeepLink':
        final url = call.argument("url");
        delegate.paywallWillOpenDeepLink(Uri.parse(url));
        break;
      default:
        throw ArgumentError('Method not implemented');
    }
  }

}