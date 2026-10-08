import Foundation

nonisolated enum SteamClientCompatibility {
    /// These are Steam CEF switches, not Wine graphics overrides. Games retain
    /// their selected graphics backend and CrossOver retains its own defaults.
    static func arguments(bundledWine: Bool) -> [String] {
        bundledWine ? ["-cef-disable-gpu", "-cef-disable-gpu-compositing"] : []
    }
}
