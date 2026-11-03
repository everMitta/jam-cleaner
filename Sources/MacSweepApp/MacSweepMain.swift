import AppKit
import Foundation
import MacSweepCore
import SwiftUI

@main
struct MacSweepMain {
    static func main() {
        let args = CommandLine.arguments

        // Support headless CLI benchmark, JSON preview export, and UI snapshot rendering
        if args.contains("--print-summary")
            || args.contains("--export-preview")
            || args.contains("--render-snapshot")
            || args.contains("--render-welcome-snapshot")
            || args.contains("--render-scanning-snapshot")
            || args.contains("--render-cleaning-snapshot")
        {
            Task { @MainActor in
                await runCLIMode(args: args)
                Foundation.exit(0)
            }
            RunLoop.main.run()
            return
        }

        // Launch Native SwiftUI macOS Application directly on the main thread
        // (Must NOT be called inside `MainActor.run`, as `MacSweepGUIApp.main()` never returns
        // and would permanently block the Swift Concurrency MainActor serial executor.)
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        MacSweepGUIApp.main()
    }

    @MainActor
    private static func runCLIMode(args: [String]) async {
        let selectedLanguage: AppLanguage = {
            if let langIdx = args.firstIndex(of: "--lang"),
                langIdx + 1 < args.count,
                let parsed = AppLanguage(rawValue: args[langIdx + 1].lowercased())
            {
                return parsed
            }
            return AppLanguage.systemDefault()
        }()

        if let welcomeIndex = args.firstIndex(of: "--render-welcome-snapshot"),
            welcomeIndex + 1 < args.count
        {
            let pngPath = (args[welcomeIndex + 1] as NSString).expandingTildeInPath
            renderSnapshot(
                of: nil,
                startInScopeSelector: true,
                simulateScanningState: false,
                language: selectedLanguage,
                to: pngPath
            )
            if !args.contains("--print-summary")
                && !args.contains("--export-preview")
                && !args.contains("--render-snapshot")
                && !args.contains("--render-scanning-snapshot")
            {
                return
            }
        }

        if let scanningIndex = args.firstIndex(of: "--render-scanning-snapshot"),
            scanningIndex + 1 < args.count
        {
            let pngPath = (args[scanningIndex + 1] as NSString).expandingTildeInPath
            renderSnapshot(
                of: nil,
                startInScopeSelector: false,
                simulateScanningState: true,
                simulateCleaningState: false,
                language: selectedLanguage,
                to: pngPath
            )
            if !args.contains("--print-summary")
                && !args.contains("--export-preview")
                && !args.contains("--render-snapshot")
                && !args.contains("--render-cleaning-snapshot")
            {
                return
            }
        }

        if let cleaningIndex = args.firstIndex(of: "--render-cleaning-snapshot"),
            cleaningIndex + 1 < args.count
        {
            let pngPath = (args[cleaningIndex + 1] as NSString).expandingTildeInPath
            renderSnapshot(
                of: nil,
                startInScopeSelector: false,
                simulateScanningState: false,
                simulateCleaningState: true,
                language: selectedLanguage,
                to: pngPath
            )
            if !args.contains("--print-summary")
                && !args.contains("--export-preview")
                && !args.contains("--render-snapshot")
            {
                return
            }
        }

        let report: ScanReport
        if let jsonIdx = args.firstIndex(of: "--from-json"),
            jsonIdx + 1 < args.count,
            let data = try? Data(
                contentsOf: URL(fileURLWithPath: (args[jsonIdx + 1] as NSString).expandingTildeInPath)),
            let decoded = try? {
                let dec = JSONDecoder()
                dec.dateDecodingStrategy = .iso8601
                return try dec.decode(ScanReport.self, from: data)
            }()
        {
            report = decoded.upgradedWithAICategory()
        } else {
            let orchestrator = ScanOrchestrator()
            report = await Task.detached(priority: .userInitiated) {
                await orchestrator.runScan()
            }.value
        }

        if let exportIndex = args.firstIndex(of: "--export-preview"),
            exportIndex + 1 < args.count
        {
            let outputPath = (args[exportIndex + 1] as NSString).expandingTildeInPath
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(report) {
                try? data.write(to: URL(fileURLWithPath: outputPath))
            }
        }

        if let snapIndex = args.firstIndex(of: "--render-snapshot"),
            snapIndex + 1 < args.count
        {
            let pngPath = (args[snapIndex + 1] as NSString).expandingTildeInPath
            renderSnapshot(
                of: report,
                startInScopeSelector: false,
                simulateScanningState: false,
                language: selectedLanguage,
                to: pngPath
            )
        }

        printReportSummary(report)
    }

    @MainActor
    private static func renderSnapshot(
        of report: ScanReport?,
        startInScopeSelector: Bool,
        simulateScanningState: Bool,
        simulateCleaningState: Bool = false,
        language: AppLanguage,
        to path: String
    ) {
        let view = MainDashboardView(
            initialReport: startInScopeSelector || simulateScanningState || simulateCleaningState ? nil : report,
            showScopeSelectorInitially: startInScopeSelector,
            isStaticSnapshot: true,
            initialLanguage: language,
            simulateScanningState: simulateScanningState,
            simulateCleaningState: simulateCleaningState
        )
        .frame(width: 1440, height: 880)
        .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        if let nsImage = renderer.nsImage,
            let tiff = nsImage.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let pngData = bitmap.representation(using: .png, properties: [:])
        {
            try? pngData.write(to: URL(fileURLWithPath: path))
        }
    }

    private static func pad(_ text: String, width: Int, rightAlign: Bool = false) -> String {
        if text.count >= width {
            return String(text.prefix(width))
        }
        let spaces = String(repeating: " ", count: width - text.count)
        return rightAlign ? (spaces + text) : (text + spaces)
    }

    private static func printReportSummary(_ report: ScanReport) {
        print("================================================================================")
        print("JAM Cleaner — Just another MacOS Cleaner")
        print(String(format: "Scan Duration: %.2f seconds", report.scanDurationSeconds))
        print("Protected Paths Guarded: \(report.protectedPathsSkippedCount)")
        print("Active Applications Tracked: \(report.runningAppsDetectedCount)")
        print("--------------------------------------------------------------------------------")
        let header =
            "\(pad("Category", width: 38)) | \(pad("Safe Auto", width: 12, rightAlign: true)) | \(pad("Total Found", width: 12, rightAlign: true)) | \(pad("Items", width: 6, rightAlign: true))"
        print(header)
        print("--------------------------------------------------------------------------------")
        for cat in report.categories {
            let safeStr = ByteFormatter.string(from: cat.safeAutoSelectBytes)
            let totalStr = ByteFormatter.string(from: cat.totalAllocatedBytes)
            let itemStr = "\(cat.totalItemCount)"
            let row =
                "\(pad(cat.category.rawValue, width: 38)) | \(pad(safeStr, width: 12, rightAlign: true)) | \(pad(totalStr, width: 12, rightAlign: true)) | \(pad(itemStr, width: 6, rightAlign: true))"
            print(row)
        }
        print("--------------------------------------------------------------------------------")
        print("SAFE AUTO-SELECTED PREVIEW : \(ByteFormatter.string(from: report.safeAutoSelectedBytes))")
        print("OPTIONAL REVIEW PREVIEW    : \(ByteFormatter.string(from: report.reviewRecommendedBytes))")
        print("GRAND TOTAL DISCOVERED     : \(ByteFormatter.string(from: report.grandTotalBytes))")
        print("================================================================================")
    }
}

final class MacSweepAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

struct MacSweepGUIApp: App {
    @NSApplicationDelegateAdaptor(MacSweepAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("JAM Cleaner — Just another MacOS Cleaner") {
            MainDashboardView()
                .background(InnotecWindowConfigurator())
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 880)
    }
}

private struct InnotecWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            window.appearance = NSAppearance(named: .aqua)
            window.backgroundColor = NSColor(red: 0.985, green: 0.988, blue: 0.996, alpha: 1.0)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
