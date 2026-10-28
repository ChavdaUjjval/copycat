import AppKit

// Opened from Downloads, the Desktop or an unzipped folder, Copycat offers to move itself into
// Applications and relaunch from there, so tidying up that folder later doesn't leave a broken
// Dock icon and login item.
@MainActor
enum AppMover {
    // Returns true if the app is quitting to relaunch the moved copy.
    static func moveToApplicationsIfNeeded() -> Bool {
        let fm = FileManager.default
        let running = Bundle.main.bundleURL
        guard running.pathExtension == "app" else { return false }   // not running from a bundle
        let source = originalURL(ofTranslocated: running) ?? running
        if isInApplications(source) { return false }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Move Copycat to your Applications folder?"
        alert.informativeText = "Copycat keeps running in the background, so it belongs in Applications. " +
            "Left here, it stops opening if this folder is cleaned up."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        let userApps = fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        let appsDir = fm.isWritableFile(atPath: "/Applications") ? URL(fileURLWithPath: "/Applications") : userApps
        let dest = appsDir.appendingPathComponent("Copycat.app")
        do {
            try fm.createDirectory(at: appsDir, withIntermediateDirectories: true)
            // Replace an older copy, quitting it first if it's running.
            for other in NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
                where other != NSRunningApplication.current { other.terminate() }
            if fm.fileExists(atPath: dest.path) { try fm.trashItem(at: dest, resultingItemURL: nil) }
            try fm.copyItem(at: source, to: dest)
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
        // Gatekeeper has already been approved to get this far. Clearing the quarantine flag on the
        // copy stops macOS from running it from a temporary read-only location again.
        if let xattr = try? Process.run(URL(fileURLWithPath: "/usr/bin/xattr"),
                                        arguments: ["-dr", "com.apple.quarantine", dest.path]) {
            xattr.waitUntilExit()
        }
        try? fm.trashItem(at: source, resultingItemURL: nil)   // fails harmlessly on a read-only disk image

        // Relaunch from Applications once this process has exited.
        let pid = ProcessInfo.processInfo.processIdentifier
        _ = try? Process.run(URL(fileURLWithPath: "/bin/sh"), arguments: [
            "-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; /usr/bin/open \"$0\"", dest.path])
        NSApp.terminate(nil)
        return true
    }

    // Whether the app is in /Applications or ~/Applications, rather than a disk image or Downloads.
    static func isInApplications(_ url: URL = Bundle.main.bundleURL) -> Bool {
        let userApps = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        return url.path.hasPrefix("/Applications/") || url.path.hasPrefix(userApps.path + "/")
    }

    // A freshly downloaded app is run from a random read-only copy ("App Translocation"); this finds
    // where it really is. The functions are in Security.framework but not in its public headers.
    private static func originalURL(ofTranslocated url: URL) -> URL? {
        typealias IsTranslocated = @convention(c) (CFURL, UnsafeMutablePointer<Bool>, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> DarwinBoolean
        typealias OriginalPath = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        guard let sec = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let isSym = dlsym(sec, "SecTranslocateIsTranslocatedURL"),
              let origSym = dlsym(sec, "SecTranslocateCreateOriginalPathForURL") else { return nil }
        var translocated = false
        guard unsafeBitCast(isSym, to: IsTranslocated.self)(url as CFURL, &translocated, nil).boolValue,
              translocated else { return nil }
        return unsafeBitCast(origSym, to: OriginalPath.self)(url as CFURL, nil)?.takeRetainedValue() as URL?
    }
}
