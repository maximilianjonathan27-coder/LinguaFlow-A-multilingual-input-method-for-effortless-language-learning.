import AppKit
import Carbon
import Foundation
import Observation

@MainActor
@Observable
final class InputMethodInstaller {
    enum Status: Equatable {
        case notInstalled
        case installed
        case updateAvailable
        case embeddedInputMethodMissing
        case installing
        case failed(String)
    }

    static let inputMethodBundleIdentifier = "com.tianxq.inputmethod.LinguaFlow"
    static let inputModeIdentifier = "com.tianxq.inputmethod.LinguaFlow.pinyin"

    private(set) var status: Status = .notInstalled
    private(set) var isInputMethodEnabled = false
    private(set) var enableErrorMessage: String?

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        refreshStatus()
    }

    var installedURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Input Methods", isDirectory: true)
            .appendingPathComponent("LinguaFlow.app", isDirectory: true)
    }

    var embeddedURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("LinguaFlow.app", isDirectory: true)
    }

    func refreshStatus() {
        let parentEnabled = inputSource(identifier: Self.inputMethodBundleIdentifier).map {
            booleanProperty(kTISPropertyInputSourceIsEnabled, from: $0)
        } ?? false
        let modeEnabled = inputSource(identifier: Self.inputModeIdentifier).map {
            booleanProperty(kTISPropertyInputSourceIsEnabled, from: $0)
        } ?? false
        isInputMethodEnabled = parentEnabled && modeEnabled

        guard let embeddedURL, validInputMethod(at: embeddedURL) else {
            status = .embeddedInputMethodMissing
            return
        }

        guard fileManager.fileExists(atPath: installedURL.path) else {
            status = .notInstalled
            return
        }

        guard validInputMethod(at: installedURL) else {
            status = .updateAvailable
            return
        }

        status = bundleVersion(at: embeddedURL) == bundleVersion(at: installedURL)
            ? .installed
            : .updateAvailable
    }

    func installOrUpdate() {
        guard let embeddedURL, validInputMethod(at: embeddedURL) else {
            status = .embeddedInputMethodMissing
            return
        }

        status = .installing
        let directory = installedURL.deletingLastPathComponent()
        let identifier = UUID().uuidString
        let stagingURL = directory.appendingPathComponent(".LinguaFlow.installing-\(identifier).app")
        let backupURL = directory.appendingPathComponent(".LinguaFlow.backup-\(identifier).app")

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try removeIfPresent(stagingURL)
            try removeIfPresent(backupURL)
            try fileManager.copyItem(at: embeddedURL, to: stagingURL)

            guard validInputMethod(at: stagingURL) else {
                throw InstallerError.invalidEmbeddedBundle
            }

            terminateRunningInputMethod()

            let hadExistingInstallation = fileManager.fileExists(atPath: installedURL.path)
            if hadExistingInstallation {
                try fileManager.moveItem(at: installedURL, to: backupURL)
            }

            do {
                try fileManager.moveItem(at: stagingURL, to: installedURL)
            } catch {
                if hadExistingInstallation, fileManager.fileExists(atPath: backupURL.path) {
                    try? fileManager.moveItem(at: backupURL, to: installedURL)
                }
                throw error
            }

            try removeIfPresent(backupURL)

            let registrationStatus = TISRegisterInputSource(installedURL as CFURL)
            guard registrationStatus == noErr else {
                throw InstallerError.registrationFailed(registrationStatus)
            }

            refreshStatus()
        } catch {
            try? removeIfPresent(stagingURL)
            status = .failed(error.localizedDescription)
        }
    }

    func openKeyboardSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func enableInputMethod() {
        enableErrorMessage = nil

        guard fileManager.fileExists(atPath: installedURL.path) else {
            enableErrorMessage = "请先安装 LinguaFlow 输入法。"
            return
        }

        guard let parentSource = inputSource(identifier: Self.inputMethodBundleIdentifier),
              let modeSource = inputSource(identifier: Self.inputModeIdentifier) else {
            enableErrorMessage = "macOS 尚未识别 LinguaFlow，请重新安装后再试。"
            return
        }

        let parentResult = TISEnableInputSource(parentSource)
        guard parentResult == noErr else {
            enableErrorMessage = "macOS 无法启用 LinguaFlow（错误码 \(parentResult)）。"
            return
        }

        let modeResult = TISEnableInputSource(modeSource)
        guard modeResult == noErr else {
            enableErrorMessage = "macOS 无法启用 LinguaFlow 拼音模式（错误码 \(modeResult)）。"
            return
        }

        refreshStatus()
    }

    private func validInputMethod(at url: URL) -> Bool {
        guard let bundle = Bundle(url: url) else { return false }
        return bundle.bundleIdentifier == Self.inputMethodBundleIdentifier
    }

    private func bundleVersion(at url: URL) -> String? {
        Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    private func terminateRunningInputMethod() {
        for application in NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.inputMethodBundleIdentifier
        ) {
            application.terminate()
        }
    }

    private func inputSource(identifier: String) -> TISInputSource? {
        let filter = [
            kTISPropertyInputSourceID as String: identifier
        ] as CFDictionary
        let sources = TISCreateInputSourceList(filter, true).takeRetainedValue()
        guard CFArrayGetCount(sources) > 0,
              let pointer = CFArrayGetValueAtIndex(sources, 0) else {
            return nil
        }
        return Unmanaged<TISInputSource>.fromOpaque(pointer).takeUnretainedValue()
    }

    private func booleanProperty(_ key: CFString, from source: TISInputSource) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, key) else {
            return false
        }
        return (Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue() as? NSNumber)?.boolValue
            ?? false
    }

    private func removeIfPresent(_ url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
}

private enum InstallerError: LocalizedError {
    case invalidEmbeddedBundle
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidEmbeddedBundle:
            "内嵌输入法无效，请重新构建 LinguaFlow Setup。"
        case let .registrationFailed(status):
            "输入法已复制，但 macOS 注册失败（错误码 \(status)）。请退出登录后重新登录。"
        }
    }
}
