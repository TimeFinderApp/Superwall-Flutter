package com.superwall.superwallkit_flutter.bridges

import android.content.Context
import com.superwall.sdk.paywall.presentation.internal.state.PaywallSkippedReason
import com.superwall.superwallkit_flutter.BridgingCreator
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

abstract class PaywallSkippedReasonBridge(
    context: Context,
    bridgeId: BridgeId,
    initializationArgs: Map<String, Any>? = null
) : BridgeInstance(context, bridgeId, initializationArgs), MethodChannel.MethodCallHandler {

    abstract val reason: PaywallSkippedReason

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getDescription" -> {
                val description = reason.toString()
                result.success(description)
            }
            else -> result.notImplemented()
        }
    }
}

class PaywallSkippedReasonHoldoutBridge(
    context: Context,
    bridgeId: BridgeId,
    initializationArgs: Map<String, Any>? = null
) : PaywallSkippedReasonBridge(context, bridgeId, initializationArgs) {

    companion object {
        fun bridgeClass(): BridgeClass = "PaywallSkippedReasonHoldoutBridge"
    }

    override val reason: PaywallSkippedReason = initializationArgs?.get("reason") as? PaywallSkippedReason
        ?: throw IllegalArgumentException("Attempting to create a `PaywallSkippedReasonHoldoutBridge` without providing a reason.")

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getExperimentBridgeId" -> {
                if (reason is PaywallSkippedReason.Holdout) {
                    val experiment = reason.experiment
                    val experimentBridgeId = BridgingCreator.shared.createBridgeInstanceFromBridgeClass(
                        ExperimentBridge.bridgeClass(),
                        mapOf("experiment" to experiment)
                    )
                    result.success(experimentBridgeId)
                } else {
                    result.notImplemented()
                }
            }
            else -> super.onMethodCall(call, result)
        }
    }
}

class PaywallSkippedReasonNoRuleMatchBridge(
    context: Context,
    bridgeId: BridgeId,
    initializationArgs: Map<String, Any>? = null
) : PaywallSkippedReasonBridge(context, bridgeId, initializationArgs) {

    companion object {
        fun bridgeClass(): BridgeClass = "PaywallSkippedReasonNoRuleMatchBridge"
    }

    override val reason: PaywallSkippedReason = PaywallSkippedReason.NoRuleMatch()
}

class PaywallSkippedReasonEventNotFoundBridge(
    context: Context,
    bridgeId: BridgeId,
    initializationArgs: Map<String, Any>? = null
) : PaywallSkippedReasonBridge(context, bridgeId, initializationArgs) {

    companion object {
        fun bridgeClass(): BridgeClass = "PaywallSkippedReasonEventNotFoundBridge"
    }

    override val reason: PaywallSkippedReason = PaywallSkippedReason.EventNotFound()
}

class PaywallSkippedReasonUserIsSubscribedBridge(
    context: Context,
    bridgeId: BridgeId,
    initializationArgs: Map<String, Any>? = null
) : PaywallSkippedReasonBridge(context, bridgeId, initializationArgs) {

    companion object {
        fun bridgeClass(): BridgeClass = "PaywallSkippedReasonUserIsSubscribedBridge"
    }

    override val reason: PaywallSkippedReason = PaywallSkippedReason.UserIsSubscribed()
}

fun PaywallSkippedReason.createBridgeId(): BridgeId {
    return when (this) {
        is PaywallSkippedReason.Holdout -> {
            val bridgeInstance = BridgingCreator.shared.createBridgeInstanceFromBridgeClass(
                PaywallSkippedReasonHoldoutBridge.bridgeClass(),
                mapOf("reason" to this)
            )
            return bridgeInstance.bridgeId
        }
        is PaywallSkippedReason.NoRuleMatch -> {
            val bridgeInstance = BridgingCreator.shared.createBridgeInstanceFromBridgeClass(
                PaywallSkippedReasonNoRuleMatchBridge.bridgeClass(),
                mapOf("reason" to this)
            )
            return bridgeInstance.bridgeId
        }
        is PaywallSkippedReason.EventNotFound -> {
            val bridgeInstance = BridgingCreator.shared.createBridgeInstanceFromBridgeClass(
                PaywallSkippedReasonEventNotFoundBridge.bridgeClass(),
                mapOf("reason" to this)
            )
            return bridgeInstance.bridgeId
        }
        is PaywallSkippedReason.UserIsSubscribed -> {
            val bridgeInstance = BridgingCreator.shared.createBridgeInstanceFromBridgeClass(
                PaywallSkippedReasonUserIsSubscribedBridge.bridgeClass(),
                mapOf("reason" to this)
            )
            return bridgeInstance.bridgeId
        }
    }
}
