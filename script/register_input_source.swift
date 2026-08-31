import Carbon
import Foundation

private func fail(_ message: String, status: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(status)
}

private func property(_ key: CFString, from source: TISInputSource) -> Any? {
    guard let pointer = TISGetInputSourceProperty(source, key) else {
        return nil
    }
    return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
}

if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--verify" {
    let expectedBundleIdentifier = CommandLine.arguments[2]
    let sources = TISCreateInputSourceList(nil, true).takeRetainedValue() as NSArray
    var matchingIdentifiers: [String] = []

    for case let source as TISInputSource in sources {
        let sourceIdentifier = property(kTISPropertyInputSourceID, from: source) as? String ?? ""
        let bundleIdentifier = property(kTISPropertyBundleID, from: source) as? String ?? ""
        if bundleIdentifier == expectedBundleIdentifier
            || sourceIdentifier == expectedBundleIdentifier
            || sourceIdentifier.hasPrefix("\(expectedBundleIdentifier).") {
            matchingIdentifiers.append(sourceIdentifier)
        }
    }

    guard !matchingIdentifiers.isEmpty else {
        fail("Input source is not registered with macOS: \(expectedBundleIdentifier)")
    }

    print("Registered input sources: \(matchingIdentifiers.sorted().joined(separator: ", "))")
    exit(0)
}

guard CommandLine.arguments.count == 2 else {
    fail(
        "usage: register_input_source.swift <input-method.app> | --verify <bundle-id>",
        status: 2
    )
}

let inputMethodURL = URL(
    fileURLWithPath: CommandLine.arguments[1],
    isDirectory: true
).standardizedFileURL

guard FileManager.default.fileExists(atPath: inputMethodURL.path) else {
    fail("input method not found: \(inputMethodURL.path)", status: 2)
}

let registrationStatus = TISRegisterInputSource(inputMethodURL as CFURL)
guard registrationStatus == noErr else {
    fail("TISRegisterInputSource failed with status \(registrationStatus)")
}

print("Registered input source with Text Input Sources: \(inputMethodURL.path)")
