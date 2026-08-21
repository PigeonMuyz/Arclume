//
//  Launcher.swift
//  Procyon
//
//  Created by Italo Mandara on 24/02/2026.
//

import AppKit

func closeWineActivities() async throws {
    // Wait for graceful termination, then escalate to forceTerminate, then give a final wait
    let gracePeriod: UInt64 = 2_000_000_000 // 2 seconds in nanoseconds
    let pollInterval: UInt64 = 200_000_000  // 0.2 seconds in nanoseconds
//    let forceTimeout: UInt64 = 6_000_000_000 // ~6 seconds total before force
    let absoluteTimeout: UInt64 = 12_000_000_000 // ~12 seconds absolute timeout

    
    // Capture the target apps first to avoid the list changing while iterating
    let targets = NSWorkspace.shared.runningApplications.filter { app in
        guard let url = app.executableURL else { return false }
        return url.lastPathComponent.lowercased().hasSuffix(".exe") || url.lastPathComponent.lowercased().contains("wine")
    }

    // Send terminate to all matching apps
    for app in targets {
        if let name = app.executableURL?.lastPathComponent {
            console.warn("terminating \(name)")
        }
        app.terminate()
    }

    // Helper to check if all targets have terminated
    func allTerminated(_ apps: [NSRunningApplication]) -> Bool {
        apps.allSatisfy { $0.isTerminated }
    }

    var elapsed: UInt64 = 0
    // First grace period loop
    while !allTerminated(targets) && elapsed < gracePeriod {
        try await Task.sleep(nanoseconds: pollInterval)
        elapsed += pollInterval
    }

    // If still not all terminated after grace period, escalate with terminate
    if !allTerminated(targets) {
        for app in targets where !app.isTerminated {
            console.warn("force terminating \(app.executableURL?.lastPathComponent ?? "<unknown>")")
            app.forceTerminate()
        }
    }

    // Final wait until absolute timeout or done
    while !allTerminated(targets) && elapsed < absoluteTimeout {
        try await Task.sleep(nanoseconds: pollInterval)
        elapsed += pollInterval
    }
}

func trackPlaying(
    apps: [String],
    then: @escaping () -> Void,
    onTimeout: @escaping () -> Void,
    isNative: Bool,
    minimumStableDuration: UInt64 = 0
) async throws -> Void {
    let pollInterval: UInt64 = 500_000_000
    let gracePeriod: UInt64 = 70_000_000_000 // after 70 seconds give up tracking
    var elapsed: UInt64 = 0
    
    var nativeOrWineApps: [String] {
        isNative ? apps + apps.map { $0.replacingOccurrences(of: ".app", with: "") } : apps
    }
    let expectedAppNames = Set(nativeOrWineApps)
    
    while (elapsed < gracePeriod) {
        try await Task.sleep(nanoseconds: pollInterval)
        let runningTargets = NSWorkspace.shared.runningApplications.filter { app in
            guard !isNative else { return true }
            return app.executableURL?.lastPathComponent.lowercased().hasSuffix(".exe") == true
        }
        if let runningGame = runningTargets.first(where: {
            expectedAppNames.contains($0.executableURL?.lastPathComponent ?? "")
        }) {
            if minimumStableDuration > 0 {
                try await Task.sleep(nanoseconds: minimumStableDuration)
                elapsed += minimumStableDuration
                let isStillRunning = NSWorkspace.shared.runningApplications.contains {
                    $0.processIdentifier == runningGame.processIdentifier && !$0.isTerminated
                }
                guard isStillRunning else { continue }
            }
            if !isNative { // Attempts to select CrossOver games that do not foreground themselves.
                runningGame.activate(options: [.activateAllWindows])
            }
            then()
            return
        }
        elapsed += pollInterval
    }
    if(elapsed < gracePeriod){
        console.warn("\(nativeOrWineApps.description) crashed")
    } else {
        console.warn("couldn't find apps \(nativeOrWineApps.description) within the allowed grace period elapsed: \(elapsed/1_000_000_000)s ")
    }
    console.log("starting timeout callback...")
    onTimeout()
}

func quitSteam(cxAppPath: String, bottleName: String, isNative: Bool) async throws -> Void {
    console.log("quitting steam...")
    if(isNative) {
        let steamBundleID = "com.valvesoftware.steam"
        if let steamApp = NSRunningApplication.runningApplications(withBundleIdentifier: steamBundleID).first {
            steamApp.terminate() // polite request to quit
        }
    } else {
        if StandardGameRuntimeKind.selected() == .bundledWine,
           let bottleURL = OnlineGameDiscovery.selectedBottleURL(from: bottleName)
        {
            let configuration = try BundledWineRuntime.makeDefaultLaunchConfiguration()
            var environment = configuration.environment
            environment["WINEPREFIX"] = bottleURL.path
            let process = Process()
            process.executableURL = configuration.wineURL
            process.arguments = ["wineserver", "-k"]
            process.currentDirectoryURL = configuration.runtimeURL
            process.environment = environment
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            return
        }
        try safeShell("\(cxAppPath)/Contents/SharedSupport/CrossOver/bin/wine --bottle \(bottleName) \"C:\\Program Files (x86)\\Steam\\Steam.exe\" -shutdown")
    }
}

func quitWine(cxAppPath: String, bottleName: String) async throws -> Void {
    console.log("quitting wine...")
    try safeShell("\(cxAppPath)/Contents/SharedSupport/CrossOver/bin/wine --bottle \(bottleName) wineserver -k")
}

func openSteam(cxAppPath: String?, selectedBottle: String?, SteamX86AppPath: String) {
    if cxAppPath == nil || selectedBottle == nil {
        return
    }
    if let bottleName = URL(string: selectedBottle!)?.lastPathComponent {
        let steamLaunchCommand = "MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS=0 CX_GRAPHICS_BACKEND=\"auto\" \(cxAppPath!)/Contents/SharedSupport/CrossOver/bin/wine --bottle \(bottleName) \"\(SteamX86AppPath)\""
        do {
            try safeShell(steamLaunchCommand)
            console.log(steamLaunchCommand)
        } catch {
            console.error(String(reflecting: error))
        }
    }
}

func copyMoltenVK(cxAppPath: String, vulkanLibID: String) throws -> Void {
    let cxURL = URL(fileURLWithPath: cxAppPath)
    let moltenVKDest = cxURL.appendingPathComponent(SHARED_SUPPORT_COMPONENT + "/\(LIB_ROOT)/libMoltenVK.dylib")
    console.log(moltenVKDest.path())
    switch (vulkanLibID) {
    case "latest":
        console.log(Bundle.main.url(forResource: "libMoltenVK-latest", withExtension: "dylib")?.path() ?? "")
        try copyResource(name: "libMoltenVK-latest.dylib", destUrl: moltenVKDest)
    case "experimental":
        console.log(Bundle.main.url(forResource: "libMoltenVK-experimental", withExtension: "dylib")?.path() ?? "")
        try copyResource(name: "libMoltenVK-experimental.dylib", destUrl: moltenVKDest)
    case "dbh":
        console.log(Bundle.main.url(forResource: "libMoltenVK-dbh", withExtension: "dylib")?.path() ?? "")
        try copyResource(name: "libMoltenVK-dbh.dylib", destUrl: moltenVKDest)
//    case "kosmickrisp":
//        if let url = Bundle.main.url(forResource: "libvulkan_kosmickrisp", withExtension: "dylib") {
//             try copyResource(name: "libMoltenVK-experimental2.dylib", destUrl: cxURL)
//        }
    default:
        try restoreOrig(destUrl: moltenVKDest)
    }
}

private func applyWindowsInputOptions(to bottleURL: URL, options: GameOptions) throws {
    let values: [String: UInt32] = [
        "DisableHidraw": options.disableHidraw ? 1 : 0,
        "Enable SDL": options.enableSDL ? 1 : 0
    ]
    let registry = WineRegistryFile(
        fileURL: bottleURL.appendingPathComponent("system.reg")
    )
    try registry.load()
    guard let controllersSection = registry.section(
        forPath: "System\\\\CurrentControlSet\\\\Services\\winebus"
    ) else {
        console.error("\\\\winebus section not found in system.reg file for the bottle \(bottleURL.path)")
        return
    }
    for (key, value) in values {
        console.log("setting \(key) to \(value)")
        controllersSection.addOrSetDword(forKey: key, value: value)
    }
    try registry.save()
}

func launchWindowsGame(id: String, cxAppPath: String?, selectedBottle: String, steamExePath: String, options: GameOptions? = nil, appExeURL: URL? = nil) async throws -> Void {
    console.log("options: \(options.debugDescription)")
    guard let options else { throw CocoaError(.fileNoSuchFile) }
    guard let bottleURL = OnlineGameDiscovery.selectedBottleURL(from: selectedBottle) else {
        throw CocoaError(.fileNoSuchFile)
    }
    if StandardGameRuntimeKind.selected() == .bundledWine {
        guard BundledWineRuntime.ownsStandardSteamPrefix(bottleURL),
              BundledWineRuntime.isValidPrefix(at: bottleURL)
        else {
            throw BundledWineRuntimeError.invalidPrefix
        }
        try applyWindowsInputOptions(to: bottleURL, options: options)
        let configuration = try BundledWineRuntime.makeLaunchConfiguration(options: options)
        var environment = configuration.environment
        environment["WINEPREFIX"] = bottleURL.path
        let steamBootOptions = [
            "-nochatui", "-nofriendsui", "-silent", "-no-browser",
            "-no-cef-sandbox", "-skipinitialbootstrap"
        ]
        let extraArguments = options.gameArguments.split(
            whereSeparator: { $0.isWhitespace }
        ).map(String.init)
        let target = appExeURL?.path(percentEncoded: false) ?? steamExePath
        let arguments = appExeURL == nil
            ? [target] + steamBootOptions + ["-applaunch", id] + extraArguments
            : [target] + extraArguments
        let process = Process()
        process.executableURL = configuration.wineURL
        process.arguments = arguments
        process.currentDirectoryURL = appExeURL?.deletingLastPathComponent()
            ?? URL(fileURLWithPath: steamExePath).deletingLastPathComponent()
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return
    }
    guard let cxAppPath else { throw CocoaError(.fileNoSuchFile) }
    try applyWindowsInputOptions(to: bottleURL, options: options)
    if !options.vulkanLib.isEmpty {
        try copyMoltenVK(cxAppPath: cxAppPath, vulkanLibID: options.vulkanLib)
    }
    var command = ""
    
    console.warn("applying config changes to the bottle \(selectedBottle)...")
    
    let bottleName = bottleURL.lastPathComponent
    console.warn("attempting to run steam.exe on game id \(id)")
    let arguments = " " + options.gameArguments
    let steamBootOptions = "-nochatui -nofriendsui -silent -no-browser -no-cef-sandbox -skipinitialbootstrap"
    let wineEnvs = "CX_ROOT=\"\(cxAppPath)/Contents/SharedSupport/CrossOver\" WINEPREFIX=\"\(bottleURL.path)\" WINEDEBUG=-all WINEMSYNC=\(options.wineMSync ? "1" : "0")"
    
//    try cpyd8d9DLLs(to: bottleURL, enable: options!.dx9PatchEnabled)
    
    let gameLaunchCommand = appExeURL != nil ? "\"\(appExeURL!.path(percentEncoded: false))\"" : "\"\(steamExePath)\" \(steamBootOptions) -applaunch \(String(id))"
    let cxAppURL = URL(fileURLWithPath: cxAppPath)
    switch options.cxGraphicsBackend {
        case "d3dmetal4":
            try installd3dMetal(at: cxAppURL, version: "4")
        case "d3dmetal3":
            try installd3dMetal(at: cxAppURL, version: "3")
        default:
            try  installd3dMetal(at: cxAppURL, version: "3")
    }
    
    command = "env \(getInlineEnvs(from: options) + wineEnvs) \(cxAppPath)/Contents/SharedSupport/CrossOver/bin/wine --bottle \(bottleName) \(gameLaunchCommand) \(arguments)"
    
    #if DEBUG
    console.log(command)
    #endif
    try safeShell(command)
}

func nativeInlineEnvs(from options: GameOptions?) -> String {
    options?.mtlHudEnabled == true ? "MTL_HUD_ENABLED=1 " : ""
}

func launchNativeGame(id: String, cxAppPath: String, selectedBottle: String, options: GameOptions? = nil, appExeURL: URL? = nil) async throws {
    let arguments = options != nil ? " " + options!.gameArguments : ""
    let steamBootOptions = "-nochatui -nofriendsui -silent -no-browser -applaunch"
    let nativeEnvs = nativeInlineEnvs(from: options)
    var command = ""
    if(appExeURL != nil) {
        command = "env \(nativeEnvs)open \"\(appExeURL!.path(percentEncoded: false))\" \(arguments)"
    } else {
        command = "env \(nativeEnvs)/Applications/Steam.app/Contents/MacOS/steam_osx \(steamBootOptions) \(String(id)) \(arguments)"
    }
    console.warn(command)
    try safeShell(command)
}

func installGame(id: String) {
//    https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip
//    steamcmd +login YOUR_USERNAME +app_update 1489410 validate +quit
//    steamcmd +login USER +force_install_dir "C:\Program Files (x86)\Steam\steamapps\common\MyGame" +app_update 1489410 validate +quit
}
