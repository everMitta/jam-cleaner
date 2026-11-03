import Foundation

/// Metadata entry for an installed macOS application bundle.
public struct InstalledAppMetadata: Sendable {
    public let bundleIdentifier: String
    public let displayName: String
    public let bundlePath: String
}

/// Indexes installed `.app` bundles across `/Applications`, `/System/Applications`, and `~/Applications`
/// to resolve cache directory names and container identifiers into human-readable app groups.
public final class ApplicationMetadataCatalog: Sendable {
    private let byBundleID: [String: InstalledAppMetadata]
    private let byLowerName: [String: InstalledAppMetadata]

    /// Known well-established mappings for common macOS / Electron / developer folders whose folder names differ from their `.app` bundle names.
    private let knownFolderAliases: [String: (bundleID: String, displayName: String)] = [
        "code": ("com.microsoft.VSCode", "Visual Studio Code"),
        "com.microsoft.vscode": ("com.microsoft.VSCode", "Visual Studio Code"),
        "cursor": ("com.todesktop.230313mzl4w4u92", "Cursor"),
        "claude": ("com.anthropic.claudefordesktop", "Claude Desktop"),
        "discord": ("com.hnc.Discord", "Discord"),
        "antigravity": ("com.google.antigravity", "Antigravity"),
        "slack": ("com.tinyspeck.slackmacgap", "Slack"),
        "us.zoom.xos": ("us.zoom.xos", "Zoom"),
        "net.whatsapp.whatsapp": ("net.whatsapp.WhatsApp", "WhatsApp"),
        "com.adobe.acrobat.pro": ("com.adobe.Acrobat.Pro", "Adobe Acrobat Pro"),
        "com.microsoft.excel": ("com.microsoft.Excel", "Microsoft Excel"),
        "com.microsoft.word": ("com.microsoft.Word", "Microsoft Word"),
        "com.microsoft.powerpoint": ("com.microsoft.Powerpoint", "Microsoft PowerPoint"),
        "battle.net": ("net.battle.app", "Battle.net"),
        "binance": ("com.binance.mac", "Binance"),
        "pgadmin 4": ("org.pgadmin.pgadmin4", "pgAdmin 4"),
        "rave": ("io.rave.desktop", "Rave"),
        "postman": ("com.postmanlabs.mac", "Postman"),
        "com.apple.helpd": ("com.apple.helpd", "macOS Help Viewer Daemon"),
        "com.apple.parsecd": ("com.apple.parsecd", "Siri & Spotlight Suggestions (parsecd)"),
        "com.apple.mediaanalysisd": ("com.apple.mediaanalysisd", "macOS Media Analysis Service"),
        "com.apple.wallpaper.agent": ("com.apple.wallpaper.agent", "macOS Wallpaper Agent"),
        "com.apple.appstore": ("com.apple.AppStore", "Mac App Store"),
    ]

    public init(homeDirectoryPath: String = NSHomeDirectory()) {
        let searchRoots = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            (homeDirectoryPath as NSString).appendingPathComponent("Applications"),
        ]

        var bundleMap: [String: InstalledAppMetadata] = [:]
        var nameMap: [String: InstalledAppMetadata] = [:]
        let fm = FileManager.default
        for root in searchRoots {
            guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let fullPath = (root as NSString).appendingPathComponent(entry)
                Self.registerAppBundle(at: fullPath, byBundleID: &bundleMap, byLowerName: &nameMap)
            }
        }
        self.byBundleID = bundleMap
        self.byLowerName = nameMap
    }

    private static func registerAppBundle(
        at appPath: String,
        byBundleID: inout [String: InstalledAppMetadata],
        byLowerName: inout [String: InstalledAppMetadata]
    ) {
        let plistPath = (appPath as NSString).appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOfFile: plistPath) as? [String: Any] else { return }
        let rawBundleID = (dict["CFBundleIdentifier"] as? String) ?? ""
        let fallbackName = ((appPath as NSString).lastPathComponent as NSString).deletingPathExtension
        let displayName =
            (dict["CFBundleDisplayName"] as? String)
            ?? (dict["CFBundleName"] as? String)
            ?? fallbackName

        guard !rawBundleID.isEmpty else { return }
        let metadata = InstalledAppMetadata(
            bundleIdentifier: rawBundleID,
            displayName: displayName,
            bundlePath: appPath
        )
        byBundleID[rawBundleID.lowercased()] = metadata
        byLowerName[displayName.lowercased()] = metadata
        byLowerName[fallbackName.lowercased()] = metadata
    }

    /// Resolves a folder name or bundle identifier into `(bundleIdentifier, displayName, bundlePath)`.
    public func resolve(
        folderOrBundleIdentifier rawToken: String
    ) -> (bundleID: String, displayName: String, bundlePath: String?) {
        let lower = rawToken.lowercased()

        if let exact = byBundleID[lower] {
            return (exact.bundleIdentifier, exact.displayName, exact.bundlePath)
        }
        if let byName = byLowerName[lower] {
            return (byName.bundleIdentifier, byName.displayName, byName.bundlePath)
        }
        if let alias = knownFolderAliases[lower] {
            let bundlePath =
                byBundleID[alias.bundleID.lowercased()]?.bundlePath
                ?? byLowerName[alias.displayName.lowercased()]?.bundlePath
            return (alias.bundleID, alias.displayName, bundlePath)
        }

        // Heuristic cleanup for reverse-DNS bundle identifiers (e.g. com.vendor.AppName -> AppName)
        let parts = rawToken.split(separator: ".").map(String.init)
        if parts.count >= 3
            && (parts[0] == "com" || parts[0] == "org" || parts[0] == "io" || parts[0] == "net" || parts[0] == "us"
                || parts[0] == "dev")
        {
            let tail = parts.dropFirst(2).joined(separator: " ")
            if let matched = byLowerName[tail.lowercased()] {
                return (matched.bundleIdentifier, matched.displayName, matched.bundlePath)
            }
            let readable = tail.replacingOccurrences(of: "-", with: " ")
            return (rawToken, readable, nil)
        }

        return (rawToken, rawToken, nil)
    }
}
