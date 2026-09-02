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

if CommandLine.arguments.count == 2, CommandLine.arguments[1] == "--current" {
    let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    let sourceIdentifier = property(kTISPropertyInputSourceID, from: source) as? String ?? "unknown"
    print(sourceIdentifier)
    exit(0)
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

if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--select" {
    let expectedSourceIdentifier = CommandLine.arguments[2]
    let sources = TISCreateInputSourceList(nil, true).takeRetainedValue() as NSArray

    for case let source as TISInputSource in sources {
        let sourceIdentifier = property(kTISPropertyInputSourceID, from: source) as? String ?? ""
        guard sourceIdentifier == expectedSourceIdentifier else {
            continue
        }

        let bundleIdentifier = property(kTISPropertyBundleID, from: source) as? String
        var parentSource: TISInputSource?
        if let bundleIdentifier, bundleIdentifier != sourceIdentifier {
            for case let candidateSource as TISInputSource in sources {
                let candidateIdentifier = property(
                    kTISPropertyInputSourceID,
                    from: candidateSource
                ) as? String
                if candidateIdentifier == bundleIdentifier {
                    parentSource = candidateSource
                    break
                }
            }
        }
        if let parentSource {
            let parentEnableStatus = TISEnableInputSource(parentSource)
            guard parentEnableStatus == noErr else {
                fail("TISEnableInputSource for parent failed with status \(parentEnableStatus)")
            }
        }

        let enableStatus = TISEnableInputSource(source)
        guard enableStatus == noErr else {
            fail("TISEnableInputSource failed with status \(enableStatus)")
        }

        let selectionStatus = TISSelectInputSource(source)
        guard selectionStatus == noErr else {
            fail("TISSelectInputSource failed with status \(selectionStatus)")
        }

        let selectedSource = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let selectedIdentifier = property(kTISPropertyInputSourceID, from: selectedSource) as? String
        guard selectedIdentifier == expectedSourceIdentifier else {
            fail("macOS did not retain the selected input source; current source is \(selectedIdentifier ?? "unknown")")
        }

        print("Selected input source: \(sourceIdentifier)")
        exit(0)
    }

    fail("Input source was not found: \(expectedSourceIdentifier)")
}

guard CommandLine.arguments.count == 2 else {
    fail(
        "usage: register_input_source.swift <input-method.app> | --current | --verify <bundle-id> | --select <source-id>",
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
