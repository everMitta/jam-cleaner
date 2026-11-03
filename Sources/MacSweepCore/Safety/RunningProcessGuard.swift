import AppKit
import Foundation

/// Captures a snapshot of currently running macOS GUI applications and active CLI processes
/// so the safety engine can annotate or protect caches of actively running software.
public struct RunningProcessGuard: Sendable {
    public let runningBundleIdentifiers: Set<String>
    public let runningLocalizedAppNames: Set<String>
    public let runningProcessExecutables: Set<String>

    public init(
        runningBundleIdentifiers: Set<String>,
        runningLocalizedAppNames: Set<String>,
        runningProcessExecutables: Set<String>
    ) {
        self.runningBundleIdentifiers = runningBundleIdentifiers
        self.runningLocalizedAppNames = runningLocalizedAppNames
        self.runningProcessExecutables = runningProcessExecutables
    }

    /// Captures a live snapshot from `NSWorkspace` and `/bin/ps`.
    public static func captureCurrentSnapshot() -> RunningProcessGuard {
        var bundleIDs = Set<String>()
        var appNames = Set<String>()
        var executables = Set<String>()

        for app in NSWorkspace.shared.runningApplications {
            if let bundleID = app.bundleIdentifier?.lowercased() {
                bundleIDs.insert(bundleID)
            }
            if let name = app.localizedName?.lowercased() {
                appNames.insert(name)
            }
            if let exe = app.executableURL?.lastPathComponent.lowercased() {
                executables.insert(exe)
            }
        }

        // Supplement with lightweight BSD process table snapshot for CLI toolchains (go, npm, dart, uv, cargo, etc.)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "comm="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        if (try? process.run()) != nil {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if let text = String(data: data, encoding: .utf8) {
                for line in text.split(separator: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    let base = (trimmed as NSString).lastPathComponent.lowercased()
                    if !base.isEmpty {
                        executables.insert(base)
                    }
                }
            }
        }

        return RunningProcessGuard(
            runningBundleIdentifiers: bundleIDs,
            runningLocalizedAppNames: appNames,
            runningProcessExecutables: executables
        )
    }

    /// Checks whether a given bundle identifier, display name, or set of process names is currently active.
    public func isActive(
        bundleIdentifier: String?,
        displayName: String?,
        processNames: [String] = []
    ) -> Bool {
        if let bundleID = bundleIdentifier?.lowercased(), !bundleID.isEmpty {
            if runningBundleIdentifiers.contains(bundleID) {
                return true
            }
        }
        if let name = displayName?.lowercased(), !name.isEmpty {
            if runningLocalizedAppNames.contains(name) {
                return true
            }
        }
        for proc in processNames {
            if runningProcessExecutables.contains(proc.lowercased()) {
                return true
            }
        }
        return false
    }
}

/// Lightweight descriptor of a live GUI application for conflict detection and unit testing.
public struct RunningAppDescriptor: Sendable, Equatable {
    public let bundleIdentifier: String
    public let localizedName: String
    public let bundlePath: String?
    public let processIdentifier: pid_t
    public let isRegularApp: Bool

    public init(
        bundleIdentifier: String,
        localizedName: String,
        bundlePath: String? = nil,
        processIdentifier: pid_t = 0,
        isRegularApp: Bool = true
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.bundlePath = bundlePath
        self.processIdentifier = processIdentifier
        self.isRegularApp = isRegularApp
    }
}

/// Represents a currently open application whose selected caches or state files are queued for cleanup.
public struct RunningApplicationConflict: Identifiable, Sendable, Equatable {
    public var id: String { bundleIdentifier.lowercased() }
    public let bundleIdentifier: String
    public let displayName: String
    public let bundlePath: String?
    public let processIdentifier: pid_t
    public let affectedItemsCount: Int
    public let affectedAllocatedBytes: UInt64
    public let affectedItemIDs: Set<String>

    public init(
        bundleIdentifier: String,
        displayName: String,
        bundlePath: String?,
        processIdentifier: pid_t,
        affectedItemsCount: Int,
        affectedAllocatedBytes: UInt64,
        affectedItemIDs: Set<String>
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.bundlePath = bundlePath
        self.processIdentifier = processIdentifier
        self.affectedItemsCount = affectedItemsCount
        self.affectedAllocatedBytes = affectedAllocatedBytes
        self.affectedItemIDs = affectedItemIDs
    }
}

/// Protocol abstracting `NSRunningApplication` for safe, deterministic unit testing without terminating real user apps.
public protocol RunningApplicationControlling: AnyObject {
    var isTerminated: Bool { get }
    var bundleIdentifier: String? { get }
    var localizedName: String? { get }
    var bundleURL: URL? { get }
    var executableURL: URL? { get }
    var processIdentifier: pid_t { get }
    var activationPolicy: NSApplication.ActivationPolicy { get }
    @discardableResult func terminate() -> Bool
    @discardableResult func forceTerminate() -> Bool
}

extension NSRunningApplication: RunningApplicationControlling {}

/// Protocol abstracting `NSWorkspace.open(_:)` for non-destructive deep-link verification in unit tests.
public protocol WorkspaceURLOpening {
    @discardableResult func open(_ url: URL) -> Bool
}

extension NSWorkspace: WorkspaceURLOpening {}

/// Coordinates real-time detection and graceful termination of open applications before cache cleanup.
public enum RunningAppCleanupCoordinator {
    /// Bundle identifiers that JAM Cleaner must never offer to quit (itself and core macOS shell services).
    private static let nonTerminableBundleIDs: Set<String> = [
        "com.innoteclabs.jamcleaner",
        "com.innotec.jamcleaner",
        "jamcleaner",
        "jam cleaner",
        "com.innoteclabs.macsweep",
        "com.innotec.macsweep",
        "macsweep",
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.systemuiserver",
        "com.apple.windowserver",
    ]

    private static let logBundlePrefixes: [String] = [
        "logs.user.",
        "logs.diag.user.",
        "logs.crashreporter.",
        "logs.system.",
        "logs.var.",
    ]

    /// Captures live regular (Dock-visible) applications from `NSWorkspace.shared.runningApplications`.
    public static func liveRunningAppDescriptors(
        workspaceApps: [any RunningApplicationControlling] = NSWorkspace.shared.runningApplications
    ) -> [RunningAppDescriptor] {
        let selfBundleID = Bundle.main.bundleIdentifier?.lowercased()
        var descriptors: [RunningAppDescriptor] = []

        for app in workspaceApps {
            guard !app.isTerminated,
                let rawBundleID = app.bundleIdentifier,
                !rawBundleID.isEmpty
            else { continue }

            let lowerID = rawBundleID.lowercased()
            if lowerID == selfBundleID || nonTerminableBundleIDs.contains(lowerID) {
                continue
            }

            let isRegular = (app.activationPolicy == .regular)
            guard isRegular else { continue }

            let name =
                app.localizedName
                ?? ((app.bundleURL?.lastPathComponent as NSString?)?.deletingPathExtension ?? rawBundleID)
            descriptors.append(
                RunningAppDescriptor(
                    bundleIdentifier: rawBundleID,
                    localizedName: name,
                    bundlePath: app.bundleURL?.path,
                    processIdentifier: app.processIdentifier,
                    isRegularApp: isRegular
                )
            )
        }

        return descriptors
    }

    /// Detects which currently open regular GUI applications own any of the selected cleanup candidate items.
    public static func detectConflicts(
        for selectedItems: [ScanCandidateItem],
        runningApps: [RunningAppDescriptor]? = nil,
        appCatalog: ApplicationMetadataCatalog = ApplicationMetadataCatalog()
    ) -> [RunningApplicationConflict] {
        let activeItems = selectedItems.filter(\.isSelected)
        guard !activeItems.isEmpty else { return [] }

        let selfBundleID = Bundle.main.bundleIdentifier?.lowercased()
        let descriptors = (runningApps ?? liveRunningAppDescriptors()).filter { desc in
            let lower = desc.bundleIdentifier.lowercased()
            return desc.isRegularApp && lower != selfBundleID && !nonTerminableBundleIDs.contains(lower)
        }
        guard !descriptors.isEmpty else { return [] }

        var byLowerBundleID: [String: RunningAppDescriptor] = [:]
        var byLowerName: [String: RunningAppDescriptor] = [:]
        for desc in descriptors {
            byLowerBundleID[desc.bundleIdentifier.lowercased()] = desc
            byLowerName[desc.localizedName.lowercased()] = desc
        }

        struct Accumulator {
            let descriptor: RunningAppDescriptor
            var itemIDs: Set<String> = []
            var bytes: UInt64 = 0
        }

        var grouped: [String: Accumulator] = [:]

        for item in activeItems {
            if let matched = matchRunningApp(
                for: item,
                byLowerBundleID: byLowerBundleID,
                byLowerName: byLowerName,
                appCatalog: appCatalog
            ) {
                let key = matched.bundleIdentifier.lowercased()
                var acc = grouped[key] ?? Accumulator(descriptor: matched)
                if !acc.itemIDs.contains(item.id) {
                    acc.itemIDs.insert(item.id)
                    acc.bytes += item.allocatedBytes
                }
                grouped[key] = acc
            }
        }

        return grouped.values
            .map { acc in
                let resolved = appCatalog.resolve(folderOrBundleIdentifier: acc.descriptor.bundleIdentifier)
                let bundlePath = acc.descriptor.bundlePath ?? resolved.bundlePath
                return RunningApplicationConflict(
                    bundleIdentifier: acc.descriptor.bundleIdentifier,
                    displayName: acc.descriptor.localizedName,
                    bundlePath: bundlePath,
                    processIdentifier: acc.descriptor.processIdentifier,
                    affectedItemsCount: acc.itemIDs.count,
                    affectedAllocatedBytes: acc.bytes,
                    affectedItemIDs: acc.itemIDs
                )
            }
            .sorted { $0.affectedAllocatedBytes > $1.affectedAllocatedBytes }
    }

    private static func matchRunningApp(
        for item: ScanCandidateItem,
        byLowerBundleID: [String: RunningAppDescriptor],
        byLowerName: [String: RunningAppDescriptor],
        appCatalog: ApplicationMetadataCatalog
    ) -> RunningAppDescriptor? {
        var candidateBundleID = item.bundleIdentifier.lowercased()
        if let prefix = logBundlePrefixes.first(where: { candidateBundleID.hasPrefix($0) }) {
            candidateBundleID = String(candidateBundleID.dropFirst(prefix.count))
        }

        if let direct = byLowerBundleID[candidateBundleID] {
            return direct
        }

        let resolvedByBundle = appCatalog.resolve(folderOrBundleIdentifier: candidateBundleID)
        if let matched = byLowerBundleID[resolvedByBundle.bundleID.lowercased()] {
            return matched
        }

        let lowerDisplay = item.appDisplayName.lowercased()
        if let byName = byLowerName[lowerDisplay] {
            return byName
        }

        let resolvedByName = appCatalog.resolve(folderOrBundleIdentifier: item.appDisplayName)
        if let matched = byLowerBundleID[resolvedByName.bundleID.lowercased()] {
            return matched
        }

        if item.category == .xcodeJunk {
            if candidateBundleID.contains("coresimulator"),
                let simApp = byLowerBundleID["com.apple.iphonesimulator"]
            {
                return simApp
            }
            if let xcodeApp = byLowerBundleID["com.apple.dt.xcode"] {
                return xcodeApp
            }
        }

        return nil
    }

    /// Sends a graceful termination request (`terminate()`) to each conflicting running application
    /// and waits up to `timeoutSeconds` for the processes to exit cleanly.
    public static func terminateApplications(
        _ conflicts: [RunningApplicationConflict],
        forceIfNeeded: Bool = false,
        timeoutSeconds: TimeInterval = 3.5,
        workspaceAppsProvider: @MainActor @Sendable () -> [any RunningApplicationControlling] = {
            NSWorkspace.shared.runningApplications
        }
    ) async -> Set<String> {
        let targetBundleIDs = Set(conflicts.map { $0.bundleIdentifier.lowercased() })
        guard !targetBundleIDs.isEmpty else { return [] }

        await MainActor.run {
            for app in workspaceAppsProvider() {
                guard !app.isTerminated,
                    let bundleID = app.bundleIdentifier?.lowercased(),
                    targetBundleIDs.contains(bundleID)
                else { continue }
                app.terminate()
            }
        }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            let stillRunning: Bool = await MainActor.run {
                workspaceAppsProvider().contains { app in
                    guard !app.isTerminated,
                        let bundleID = app.bundleIdentifier?.lowercased()
                    else { return false }
                    return targetBundleIDs.contains(bundleID)
                }
            }
            if !stillRunning {
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        }

        if forceIfNeeded {
            await MainActor.run {
                for app in workspaceAppsProvider() {
                    guard !app.isTerminated,
                        let bundleID = app.bundleIdentifier?.lowercased(),
                        targetBundleIDs.contains(bundleID)
                    else { continue }
                    app.forceTerminate()
                }
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        let remainingIDs: Set<String> = await MainActor.run {
            var set = Set<String>()
            for app in workspaceAppsProvider() {
                if !app.isTerminated, let bundleID = app.bundleIdentifier?.lowercased() {
                    set.insert(bundleID)
                }
            }
            return set
        }

        return targetBundleIDs.subtracting(remainingIDs)
    }
}

/// Checks macOS TCC Full Disk Access status and deep-links to System Settings -> Privacy & Security -> Full Disk Access.
public enum FullDiskAccessPermissionHelper {
    public static let systemSettingsDeepLinkURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
    )!

    /// Non-destructively probes TCC-protected directories inside the user's home Library (`~/Library/Safari`, `~/Library/Caches/com.apple.Safari`)
    /// to determine whether Full Disk Access is granted. If none of the TCC probe directories exist on disk, returns `true`.
    public static func hasFullDiskAccess(
        homeDirectoryPath: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> Bool {
        let fm = FileManager.default
        let candidateProbePaths = [
            "\(homeDirectoryPath)/Library/Safari",
            "\(homeDirectoryPath)/Library/Caches/com.apple.Safari",
            "\(homeDirectoryPath)/Library/Messages",
        ]

        var foundExistingProbeDirectory = false
        for probePath in candidateProbePaths {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: probePath, isDirectory: &isDir), isDir.boolValue {
                foundExistingProbeDirectory = true
                if (try? fm.contentsOfDirectory(atPath: probePath)) != nil {
                    return true
                }
            }
        }

        // If none of the TCC-protected probe folders exist (e.g. fresh test home directory), treat as accessible.
        return !foundExistingProbeDirectory
    }

    /// Opens macOS System Settings directly to Privacy & Security -> Full Disk Access.
    @MainActor
    @discardableResult
    public static func openSystemSettingsFullDiskAccess(
        workspace: any WorkspaceURLOpening = NSWorkspace.shared
    ) -> Bool {
        workspace.open(systemSettingsDeepLinkURL)
    }
}
