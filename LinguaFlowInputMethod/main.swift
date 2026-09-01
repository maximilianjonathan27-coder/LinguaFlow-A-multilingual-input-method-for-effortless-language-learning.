import AppKit
import InputMethodKit

private let connectionName = Bundle.main.object(
    forInfoDictionaryKey: "InputMethodConnectionName"
) as? String ?? "com.tianxq.inputmethod.LinguaFlow_Connection"

private let server = IMKServer(
    name: connectionName,
    bundleIdentifier: Bundle.main.bundleIdentifier
)

NSApplication.shared.run()

withExtendedLifetime(server) {}
