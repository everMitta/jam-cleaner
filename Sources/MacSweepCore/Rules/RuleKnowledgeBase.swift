import Foundation

/// Curated recipe describing a known developer toolchain or application cache location.
public struct ToolchainCacheRecipe: Sendable {
    public let id: String
    public let displayName: String
    public let bundleIdentifier: String
    public let relativePathFromHome: String
    public let category: CleanupCategory
    public let confidence: SafetyConfidence
    public let processNames: [String]
    public let explanation: String

    public init(
        id: String,
        displayName: String,
        bundleIdentifier: String,
        relativePathFromHome: String,
        category: CleanupCategory,
        confidence: SafetyConfidence = .safeAutoSelect,
        processNames: [String] = [],
        explanation: String
    ) {
        self.id = id
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.relativePathFromHome = relativePathFromHome
        self.category = category
        self.confidence = confidence
        self.processNames = processNames
        self.explanation = explanation
    }
}

/// Browser cache target recipe that strictly targets HTTP/media/shader caches and never touches cookies, history, or passwords.
public struct BrowserCacheRecipe: Sendable {
    public let id: String
    public let browserName: String
    public let bundleIdentifier: String
    public let relativeCachePathsFromHome: [String]
    public let profileGlobBaseFromHome: String?
    public let profileCacheSubpaths: [String]
    public let explanation: String
}

/// Central repository of safety rules, protected paths, and curated cache recipes.
public struct RuleKnowledgeBase: Sendable {
    public static let shared = RuleKnowledgeBase()

    /// Layer 1 Hard-Blocked Root Paths: Never scanned, never traversed, never deleted under any circumstance.
    public let immutableSystemRoots: [String] = [
        "/System",
        "/bin",
        "/sbin",
        "/usr",
        "/etc",
        "/private/etc",
        "/private/var/log",
        "/var/log",
        "/Library/Logs",
        "/Library/Apple",
        "/Library/Security",
        "/Library/Keychains",
        "/Library/SystemExtensions",
        "/Library/Extensions",
        "/Applications",
    ]

    /// Layer 1 Hard-Blocked User Home Relative Paths: Credentials, cloud storage, user documents, keychains, and databases.
    public let protectedHomeRelativeRoots: [String] = [
        "Library/Keychains",
        "Library/CloudStorage",
        "Library/Mobile Documents",
        "Library/Application Support/MobileSync",
        "Library/Application Support/AddressBook",
        "Library/Application Support/CallHistoryDB",
        "Library/Application Support/CoreParsec",
        "Library/Application Support/com.apple.TCC",
        "Library/Application Support/FileProvider",
        "Library/Mail",
        "Library/Messages",
        "Library/Calendars",
        "Library/Contacts",
        "Library/Notes",
        "Library/Safari/Bookmarks.plist",
        "Library/Safari/History.db",
        "Library/Cookies",
        "Library/HTTPStorages",
        "Documents",
        "Desktop",
        "Pictures",
        "Music",
        "Movies",
        "Projects",
        "Development",
        ".ssh",
        ".gnupg",
        ".aws",
        ".azure",
        ".kube",
        ".config",
        ".gemini",
        ".claude",
        ".agents",
    ]

    /// Layer 2 Protected Cache Subpaths: Apple and system daemon cache identifiers whose removal degrades system state, iCloud sync, or Neural Engine compilation.
    public let protectedCacheComponents: Set<String> = [
        "CloudKit",
        "com.apple.CloudKit",
        "GeoServices",
        "com.apple.GeoServices",
        "com.apple.IconServices",
        "com.apple.iconservices.store",
        "com.apple.metal",
        "com.apple.ane",
        "com.apple.e5rt.e5bundlecache",
        "com.apple.VisualIntelligenceCore",
        "com.apple.HomeKit",
        "com.apple.bird",
        "com.apple.nsurlsessiond",
        "com.apple.amsengagementd",
        "com.apple.ap.adprivacyd",
        "com.apple.PassKit",
        "com.apple.parsecd",
        "com.apple.wallpaper.agent",
        "com.apple.wallpaper.caches",
        "com.apple.photoanalysisd",
        "com.apple.mediaanalysisd",
        "com.apple.remindd",
        "com.apple.AppleMediaServices",
        "com.apple.appstoreagent",
        "com.apple.feedbacklogger",
        "com.apple.nsservicescache.plist",
        "FamilyCircle",
        "PassKit",
        "Cleanup At Startup",
        "DiagnosticMessages",
        "apache2",
        "cups",
        "asl",
    ]

    /// Browser top-level folders in ~/Library/Caches that are handled separately by BrowserCacheSubscanner so they are never double-counted.
    public let browserCacheFolderIdentifiers: Set<String> = [
        "com.apple.Safari",
        "Google",
        "Firefox",
        "BraveSoftware",
        "com.operasoftware.Opera",
        "com.microsoft.edgemac",
        "com.vivaldi.Vivaldi",
        "Yandex",
    ]

    /// Developer toolchain cache folders in ~/Library/Caches that are handled by DeveloperCacheSubscanner so they are never double-counted.
    public let developerLibraryCacheFolderIdentifiers: Set<String> = [
        "go-build",
        "goimports",
        "gopls",
        "node-gyp",
        "Homebrew",
        "CocoaPods",
        "pip",
        "pypoetry",
        "Yarn",
        "ms-playwright",
        "Cypress",
        "typescript",
    ]

    /// Strictly verified subfolder names inside `~/Library/Application Support/<App>/` that contain ONLY regenerable Chromium/Electron caches and never user state, credentials, or settings.
    public let verifiedElectronCacheSubfolders: [(subpath: String, label: String, explanation: String)] = [
        (
            "Cache/Cache_Data", "HTTP & Media Disk Cache",
            "Chromium network resource cache; automatically rebuilt as pages load."
        ),
        (
            "Cache", "Application Disk Cache",
            "Electron/Chromium resource cache directory; contains no user credentials or settings."
        ),
        (
            "Code Cache", "V8 / WebAssembly Bytecode Cache",
            "Compiled JavaScript and WebAssembly bytecode cache; regenerated automatically on script execution."
        ),
        (
            "CachedData", "Precompiled UI & Extension Bundles",
            "Cached V8 code compilation units for installed workbench versions."
        ),
        (
            "CachedExtensionVSIXs", "Downloaded Extension Installer Packages",
            "Archived .vsix installer packages already extracted into the extensions directory."
        ),
        (
            "GPUCache", "Metal / WebGL Shader Cache",
            "Compiled GPU pipeline states and shaders; automatically recompiled by Metal."
        ),
        ("DawnCache", "WebGPU Pipeline Cache", "Dawn WebGPU compiled shader cache; rebuilt on demand."),
        ("ShaderCache", "Graphics Shader Cache", "Precompiled graphics shader binaries."),
        ("GrShaderCache", "Skia Ganesh Shader Cache", "Skia 2D graphics shader cache."),
        ("BrowserCache", "Embedded WebView Cache", "Embedded Chromium browser cache directory."),
        (
            "Service Worker/CacheStorage", "Service Worker Offline Asset Cache",
            "Cached static web assets stored by Service Workers; preserves IndexedDB and cookies."
        ),
        ("Service Worker/ScriptCache", "Service Worker Script Cache", "Cached Service Worker JavaScript files."),
    ]

    /// Curated developer & toolchain recipes covering modern macOS engineering workflows.
    public let developerToolchainRecipes: [ToolchainCacheRecipe] = [
        // Xcode & Apple Developer Data
        ToolchainCacheRecipe(
            id: "xcode.derived_data",
            displayName: "Xcode DerivedData",
            bundleIdentifier: "com.apple.dt.Xcode.DerivedData",
            relativePathFromHome: "Library/Developer/Xcode/DerivedData",
            category: .xcodeJunk,
            confidence: .safeAutoSelect,
            processNames: ["Xcode", "xcodebuild"],
            explanation:
                "Intermediate build products, module caches, and indexing databases generated by Xcode; safely rebuilt on next build."
        ),
        ToolchainCacheRecipe(
            id: "xcode.ios_device_support",
            displayName: "Xcode iOS DeviceSupport Symbols",
            bundleIdentifier: "com.apple.dt.Xcode.DeviceSupport",
            relativePathFromHome: "Library/Developer/Xcode/iOS DeviceSupport",
            category: .xcodeJunk,
            confidence: .safeAutoSelect,
            processNames: ["Xcode"],
            explanation:
                "Debug symbol cache extracted from connected iOS devices; re-downloaded automatically when a device is attached for debugging."
        ),
        ToolchainCacheRecipe(
            id: "xcode.watchos_device_support",
            displayName: "Xcode watchOS DeviceSupport Symbols",
            bundleIdentifier: "com.apple.dt.Xcode.WatchDeviceSupport",
            relativePathFromHome: "Library/Developer/Xcode/watchOS DeviceSupport",
            category: .xcodeJunk,
            confidence: .safeAutoSelect,
            processNames: ["Xcode"],
            explanation: "Debug symbol cache for watchOS devices."
        ),
        ToolchainCacheRecipe(
            id: "xcode.coresimulator_caches",
            displayName: "CoreSimulator Dyld & Runtime Caches",
            bundleIdentifier: "com.apple.CoreSimulator.Caches",
            relativePathFromHome: "Library/Developer/CoreSimulator/Caches",
            category: .xcodeJunk,
            confidence: .safeAutoSelect,
            processNames: ["Simulator", "launchd_sim"],
            explanation:
                "Shared dyld cache files generated for iOS/watchOS simulator runtimes; rebuilt automatically when booting a simulator."
        ),
        // Go Toolchain
        ToolchainCacheRecipe(
            id: "dev.go_build",
            displayName: "Go Compiler Build Cache (go-build)",
            bundleIdentifier: "org.golang.go-build",
            relativePathFromHome: "Library/Caches/go-build",
            category: .developerToolchains,
            confidence: .safeAutoSelect,
            processNames: ["go", "gopls"],
            explanation:
                "Content-addressed compiled object cache produced by 'go build' and 'go test'; completely regenerable."
        ),
        ToolchainCacheRecipe(
            id: "dev.gopls",
            displayName: "Go Language Server Cache (gopls)",
            bundleIdentifier: "org.golang.gopls",
            relativePathFromHome: "Library/Caches/gopls",
            category: .developerToolchains,
            confidence: .safeAutoSelect,
            processNames: ["gopls"],
            explanation: "Persistent analysis and symbol index cache for the Go language server."
        ),
        ToolchainCacheRecipe(
            id: "dev.goimports",
            displayName: "Go Imports Index Cache",
            bundleIdentifier: "org.golang.goimports",
            relativePathFromHome: "Library/Caches/goimports",
            category: .developerToolchains,
            confidence: .safeAutoSelect,
            processNames: ["goimports"],
            explanation: "Cached module import index used by goimports."
        ),
        // Python / uv / pip
        ToolchainCacheRecipe(
            id: "dev.uv_cache",
            displayName: "Astral uv Python Package & Wheel Cache",
            bundleIdentifier: "sh.astral.uv",
            relativePathFromHome: ".cache/uv",
            category: .developerToolchains,
            confidence: .safeAutoSelect,
            processNames: ["uv", "uvx"],
            explanation: "Downloaded Python wheels, source distributions, and virtual environment cache managed by uv."
        ),
        ToolchainCacheRecipe(
            id: "dev.pip_cache",
            displayName: "Python pip HTTP & Wheel Cache",
            bundleIdentifier: "org.pypa.pip",
            relativePathFromHome: "Library/Caches/pip",
            category: .developerToolchains,
            confidence: .safeAutoSelect,
            processNames: ["pip", "pip3"],
            explanation: "Cached HTTP responses and built wheels from PyPI."
        ),
        // Dart & Flutter
        ToolchainCacheRecipe(
            id: "dev.dart_server",
            displayName: "Dart Analysis Server Cache (.dartServer)",
            bundleIdentifier: "dev.dart.analysis-server",
            relativePathFromHome: ".dartServer",
            category: .developerToolchains,
            confidence: .safeAutoSelect,
            processNames: ["dart"],
            explanation:
                "AST and bytecode analysis cache created by the Dart Analysis Server; automatically regenerated on IDE launch."
        ),
        ToolchainCacheRecipe(
            id: "dev.pub_cache",
            displayName: "Flutter / Dart Pub Package Cache (.pub-cache)",
            bundleIdentifier: "dev.dart.pub-cache",
            relativePathFromHome: ".pub-cache",
            category: .developerToolchains,
            confidence: .safeAutoSelect,
            processNames: ["dart", "flutter"],
            explanation: "Downloaded pub.dev package archives; restored via 'flutter pub get' or 'dart pub get'."
        ),
        // Node.js / npm / Browser Automation
        ToolchainCacheRecipe(
            id: "dev.npm_cacache",
            displayName: "NPM Content-Addressable Package Cache (_cacache)",
            bundleIdentifier: "com.npmjs.cli",
            relativePathFromHome: ".npm/_cacache",
            category: .developerToolchains,
            confidence: .safeAutoSelect,
            processNames: ["npm"],
            explanation: "Tarball and metadata cache stored by npm; preserves ~/.npmrc authentication tokens."
        ),
        ToolchainCacheRecipe(
            id: "dev.npm_logs",
            displayName: "NPM Debug Logs (_logs)",
            bundleIdentifier: "com.npmjs.cli",
            relativePathFromHome: ".npm/_logs",
            category: .logsAndDiagnostics,
            confidence: .safeAutoSelect,
            processNames: [],
            explanation: "Historical npm install failure and debug logs."
        ),
        ToolchainCacheRecipe(
            id: "dev.node_gyp",
            displayName: "Node-Gyp Native Header Cache",
            bundleIdentifier: "org.nodejs.node-gyp",
            relativePathFromHome: "Library/Caches/node-gyp",
            category: .developerToolchains,
            confidence: .safeAutoSelect,
            processNames: ["node-gyp"],
            explanation: "Downloaded Node.js C++ header tarballs used when compiling native addons."
        ),
        ToolchainCacheRecipe(
            id: "dev.puppeteer_cache",
            displayName: "Puppeteer Headless Browser Binaries Cache",
            bundleIdentifier: "dev.pptr.puppeteer",
            relativePathFromHome: ".cache/puppeteer",
            category: .aiAndAgentRuntimes,
            confidence: .safeAutoSelect,
            processNames: [],
            explanation:
                "Cached Chromium/Chrome for Testing browser binaries downloaded by Puppeteer automation agents."
        ),
        ToolchainCacheRecipe(
            id: "dev.chrome_devtools_mcp_cache",
            displayName: "Chrome DevTools MCP Automation Profile Cache",
            bundleIdentifier: "org.chromium.devtools-mcp",
            relativePathFromHome: ".cache/chrome-devtools-mcp",
            category: .aiAndAgentRuntimes,
            confidence: .safeAutoSelect,
            processNames: [],
            explanation:
                "Ephemeral headless browser profile and cache directories created by AI MCP DevTools automation sessions."
        ),
        ToolchainCacheRecipe(
            id: "dev.codex_runtimes_cache",
            displayName: "Coding Agent Sandboxed Runtime Cache (codex-runtimes)",
            bundleIdentifier: "io.sandbox.codex-runtimes",
            relativePathFromHome: ".cache/codex-runtimes",
            category: .aiAndAgentRuntimes,
            confidence: .safeAutoSelect,
            processNames: [],
            explanation: "Cached ephemeral agent runtime toolchains inside ~/.cache/codex-runtimes."
        ),
        ToolchainCacheRecipe(
            id: "ai.huggingface_cache",
            displayName: "Hugging Face Hub & Transformers Cache",
            bundleIdentifier: "co.huggingface.cache",
            relativePathFromHome: ".cache/huggingface",
            category: .aiAndAgentRuntimes,
            confidence: .reviewRecommended,
            processNames: [],
            explanation:
                "Downloaded Hugging Face Hub model weights, tokenizers, and dataset shards in ~/.cache/huggingface. Marked 'Review Recommended' (unselected by default) to prevent accidental multi-GB model re-downloads."
        ),
        ToolchainCacheRecipe(
            id: "ai.ollama_models",
            displayName: "Ollama Local LLM Weights & Manifests",
            bundleIdentifier: "com.ollama.app",
            relativePathFromHome: ".ollama/models",
            category: .aiAndAgentRuntimes,
            confidence: .reviewRecommended,
            processNames: ["Ollama", "ollama"],
            explanation:
                "Local GGUF model blobs and manifests stored by Ollama in ~/.ollama/models. Marked 'Review Recommended' (unselected by default) so multi-GB local LLMs are never removed without explicit confirmation."
        ),
        ToolchainCacheRecipe(
            id: "ai.lmstudio_models",
            displayName: "LM Studio Downloaded LLM Weights",
            bundleIdentifier: "ai.elementlabs.lmstudio",
            relativePathFromHome: ".cache/lm-studio/models",
            category: .aiAndAgentRuntimes,
            confidence: .reviewRecommended,
            processNames: ["LM Studio"],
            explanation:
                "Downloaded GGUF/MLX model weights managed by LM Studio in ~/.cache/lm-studio/models. Marked 'Review Recommended' (unselected by default) to prevent unintended model re-downloads."
        ),
        ToolchainCacheRecipe(
            id: "dev.firebase_cache",
            displayName: "Firebase Emulator & CLI Cache",
            bundleIdentifier: "com.google.firebase.cli",
            relativePathFromHome: ".cache/firebase",
            category: .developerToolchains,
            confidence: .safeAutoSelect,
            processNames: ["firebase"],
            explanation: "Downloaded Firebase emulator JARs and runtime binaries."
        ),
        ToolchainCacheRecipe(
            id: "dev.homebrew_cache",
            displayName: "Homebrew Bottle & Source Download Cache",
            bundleIdentifier: "sh.brew.homebrew",
            relativePathFromHome: "Library/Caches/Homebrew",
            category: .developerToolchains,
            confidence: .safeAutoSelect,
            processNames: ["brew"],
            explanation: "Archived .tar.gz bottles and installers already installed by Homebrew."
        ),
        ToolchainCacheRecipe(
            id: "dev.cocoapods_MasterRepo",
            displayName: "CocoaPods Spec Repo & Pod Cache",
            bundleIdentifier: "org.cocoapods.CocoaPods",
            relativePathFromHome: ".cocoapods/repos",
            category: .developerToolchains,
            confidence: .safeAutoSelect,
            processNames: ["pod"],
            explanation: "Local mirror of CocoaPods specifications; rebuilt on demand when running pod install."
        ),
        ToolchainCacheRecipe(
            id: "dev.cargo_registry_cache",
            displayName: "Rust Cargo Crate Registry Cache",
            bundleIdentifier: "org.rust-lang.cargo",
            relativePathFromHome: ".cargo/registry/cache",
            category: .developerToolchains,
            confidence: .safeAutoSelect,
            processNames: ["cargo", "rustc"],
            explanation: "Downloaded .crate archives from crates.io."
        ),
    ]

    /// Non-destructive Browser Cache recipes: cleans ONLY network/media/shader caches, never history, cookies, or logins.
    public let browserCacheRecipes: [BrowserCacheRecipe] = [
        BrowserCacheRecipe(
            id: "browser.safari",
            browserName: "Apple Safari",
            bundleIdentifier: "com.apple.Safari",
            relativeCachePathsFromHome: [
                "Library/Containers/com.apple.Safari/Data/Library/Caches/com.apple.Safari",
                "Library/Caches/com.apple.Safari",
            ],
            profileGlobBaseFromHome: nil,
            profileCacheSubpaths: [],
            explanation:
                "WebKit network and page rendering caches; preserves Safari bookmarks, history, tabs, and AutoFill credentials."
        ),
        BrowserCacheRecipe(
            id: "browser.chrome",
            browserName: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            relativeCachePathsFromHome: [
                "Library/Caches/Google/Chrome"
            ],
            profileGlobBaseFromHome: "Library/Application Support/Google/Chrome",
            profileCacheSubpaths: [
                "Service Worker/CacheStorage",
                "Service Worker/ScriptCache",
                "GPUCache",
                "ShaderCache",
                "GrShaderCache",
                "DawnCache",
            ],
            explanation:
                "Chrome network cache, GPU shader cache, and Service Worker static cache; preserves cookies, passwords, history, and open tabs."
        ),
        BrowserCacheRecipe(
            id: "browser.brave",
            browserName: "Brave Browser",
            bundleIdentifier: "com.brave.Browser",
            relativeCachePathsFromHome: [
                "Library/Caches/BraveSoftware/Brave-Browser"
            ],
            profileGlobBaseFromHome: "Library/Application Support/BraveSoftware/Brave-Browser",
            profileCacheSubpaths: [
                "Service Worker/CacheStorage",
                "GPUCache",
                "ShaderCache",
            ],
            explanation: "Brave network and GPU shader caches; preserves wallets, shields, cookies, and history."
        ),
        BrowserCacheRecipe(
            id: "browser.edge",
            browserName: "Microsoft Edge",
            bundleIdentifier: "com.microsoft.edgemac",
            relativeCachePathsFromHome: [
                "Library/Caches/Microsoft Edge",
                "Library/Caches/com.microsoft.edgemac",
            ],
            profileGlobBaseFromHome: "Library/Application Support/Microsoft Edge",
            profileCacheSubpaths: [
                "Service Worker/CacheStorage",
                "GPUCache",
                "ShaderCache",
            ],
            explanation: "Edge HTTP and shader caches; preserves user profiles, history, and cookies."
        ),
        BrowserCacheRecipe(
            id: "browser.firefox",
            browserName: "Mozilla Firefox",
            bundleIdentifier: "org.mozilla.firefox",
            relativeCachePathsFromHome: [
                "Library/Caches/Firefox"
            ],
            profileGlobBaseFromHome: nil,
            profileCacheSubpaths: [],
            explanation:
                "Firefox disk cache2 and startup cache directories; preserves places.sqlite (bookmarks/history) and logins."
        ),
    ]

    public init() {}
}
