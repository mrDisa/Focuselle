// Compile-only checks. None of these functions are invoked by the probe.
// This file is deliberately excluded from the application target.
import AppKit
import NetworkExtension
import SafariServices
import SystemExtensions
import EndpointSecurity

@MainActor
func checkSoftProtectionAPIs(application: NSRunningApplication) {
    let _: Notification.Name = NSWorkspace.didActivateApplicationNotification
    let _: NotificationCenter = NSWorkspace.shared.notificationCenter
    let _: Bool = application.hide()
}

func checkNetworkFilterAPIs(flow: NEFilterFlow) {
    let _: NEFilterManager.Type = NEFilterManager.self
    let _: NEFilterDataProvider.Type = NEFilterDataProvider.self
    let _: NEFilterNewFlowVerdict = .allow()
    let _: NEFilterNewFlowVerdict = .drop()
    let _: URL? = flow.url
}

func checkSystemExtensionAPIs(identifier: String) {
    let _: OSSystemExtensionRequest = .activationRequest(forExtensionWithIdentifier: identifier, queue: .main)
    let _: OSSystemExtensionRequest = .deactivationRequest(forExtensionWithIdentifier: identifier, queue: .main)
}

func checkSafariAPIs(identifier: String) {
    SFContentBlockerManager.reloadContentBlocker(withIdentifier: identifier) { _ in }
}

func checkEndpointSecurityAPI() {
    let _: es_event_type_t = ES_EVENT_TYPE_AUTH_EXEC
}
