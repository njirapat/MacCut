// MacCut - Cmd+X / Cmd+V to move files in Finder, like Ctrl+X on Windows.
//
// Normal mode: rewrites the key event in place.
//   Cmd+X in Finder -> Cmd+C, and remember the pasteboard state
//   Cmd+V in Finder while a cut is pending -> Cmd+Option+V (Finder's "Move Item Here")
// Reliable mode: swallows the keys and asks Finder (AppleScript) to move the
//   selected items directly, so it does not depend on key events reaching Finder.
// Text editing (renaming a file, search field) is left alone in both modes.
// No network access.

import Cocoa
import ApplicationServices
import ServiceManagement
import SwiftUI

private let keyX: Int64 = 7   // kVK_ANSI_X
private let keyC: Int64 = 8   // kVK_ANSI_C
private let keyV: Int64 = 9   // kVK_ANSI_V
private let finderID = "com.apple.finder"
private let repoURL = "https://github.com/njirapat/MacCut"

/// Shared with the help window so it can show whether access has been granted.
final class PermissionState: ObservableObject {
    @Published var granted = false
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var tap: CFMachPort?
    private var permissionTimer: Timer?
    private var helpWindow: NSWindow?
    private let permission = PermissionState()
    private let defaults = UserDefaults.standard

    // Normal mode: pasteboard changeCount right after Finder copied the cut items.
    private var cutCount: Int?
    // Reliable mode: POSIX paths of the cut items.
    private var cutItems: [String] = []

    private var enabled: Bool {
        get { defaults.object(forKey: "enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "enabled"); clearCut() }
    }
    private var reliableMode: Bool {
        get { defaults.bool(forKey: "reliableMode") }
        set { defaults.set(newValue, forKey: "reliableMode"); clearCut() }
    }
    private var cutPending: Bool { cutCount != nil || !cutItems.isEmpty }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        refreshUI()
        if AXIsProcessTrusted() {
            installTap()
        } else {
            // Wait until the user grants access in System Settings.
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
                guard AXIsProcessTrusted() else { return }
                t.invalidate()
                self?.installTap()
            }
        }
        // First launch, or no permission yet: show the guide with the permission banner.
        if !defaults.bool(forKey: "didShowWelcome") || !AXIsProcessTrusted() {
            defaults.set(true, forKey: "didShowWelcome")
            showHelp()
        }
    }

    // MARK: - Event tap

    private func installTap() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let me = Unmanaged<AppDelegate>.fromOpaque(refcon!).takeUnretainedValue()
            return me.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            NSLog("MacCut: could not create event tap")
            return
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        permission.granted = true
        refreshUI()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        guard enabled, type == .keyDown else { return pass }

        let flags = event.flags
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        guard [keyX, keyC, keyV].contains(key), flags.contains(.maskCommand),
              flags.intersection([.maskShift, .maskAlternate, .maskControl]).isEmpty,
              let finder = NSWorkspace.shared.frontmostApplication,
              finder.bundleIdentifier == finderID,
              !textRoles.contains(focusedRole(pid: finder.processIdentifier))
        else { return pass }

        switch key {
        case keyX:
            if reliableMode {
                DispatchQueue.main.async { self.cutViaFinder() }
                return nil
            }
            let before = NSPasteboard.general.changeCount
            event.setIntegerValueField(.keyboardEventKeycode, value: keyC)
            // Give Finder a moment to copy. Nothing selected = nothing copied = no cut.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let now = NSPasteboard.general.changeCount
                self.cutCount = now != before ? now : nil
                self.refreshUI()
            }
            return pass

        case keyC:
            clearCut()
            return pass

        default: // keyV
            if reliableMode {
                guard !cutItems.isEmpty else { return pass }
                DispatchQueue.main.async { self.pasteViaFinder() }
                return nil
            }
            // Something else was copied since the cut: behave as a normal paste.
            guard let count = cutCount, count == NSPasteboard.general.changeCount else {
                clearCut()
                return pass
            }
            event.flags = flags.union(.maskAlternate)
            clearCut()
            return pass
        }
    }

    /// Roles that mean the user is editing text (renaming, search field).
    private let textRoles = [kAXTextFieldRole as String, kAXTextAreaRole as String, kAXComboBoxRole as String]

    /// Accessibility role of the focused element in the given app, or "?" if unavailable.
    private func focusedRole(pid: pid_t) -> String {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID() else { return "?" }
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element as! AXUIElement, kAXRoleAttribute as CFString, &role)
        return role as? String ?? "?"
    }

    // MARK: - Reliable mode (Finder scripting)

    private func cutViaFinder() {
        let script = """
        tell application "Finder"
            set out to ""
            repeat with anItem in (get selection)
                set out to out & POSIX path of (anItem as alias) & linefeed
            end repeat
            return out
        end tell
        """
        guard let result = runScript(script) else { return }
        cutItems = result.split(separator: "\n").map(String.init)
        refreshUI()
    }

    private enum ClashChoice { case replace, keepBoth, stop }

    private func pasteViaFinder() {
        // "insertion location" is where Finder itself would paste: the front window's folder, or the Desktop.
        guard let destinationPath = runScript("""
        tell application "Finder" to return POSIX path of (insertion location as alias)
        """) else { return }
        let destination = URL(fileURLWithPath: destinationPath, isDirectory: true)
        let fileManager = FileManager.default

        // Decide every name clash before touching anything, so Stop leaves all files as they were.
        let sources = cutItems.map { URL(fileURLWithPath: $0) }
            .filter { $0.deletingLastPathComponent().standardizedFileURL != destination.standardizedFileURL }
        let clashes = sources.filter { fileManager.fileExists(atPath: destination.appendingPathComponent($0.lastPathComponent).path) }
        var toFinder = sources.filter { !clashes.contains($0) }
        var replaceTargets: [URL] = []
        var keepBoth: [URL] = []
        var choiceForAll: ClashChoice?
        for (index, source) in clashes.enumerated() {
            let choice: ClashChoice
            if let choiceForAll {
                choice = choiceForAll
            } else {
                let (picked, applyToAll) = askAboutClash(name: source.lastPathComponent, moreToCome: index < clashes.count - 1)
                choice = picked
                if applyToAll { choiceForAll = picked }
            }
            switch choice {
            case .stop:
                return   // nothing moved; the cut is kept
            case .replace:
                replaceTargets.append(destination.appendingPathComponent(source.lastPathComponent))
                toFinder.append(source)
            case .keepBoth:
                keepBoth.append(source)
            }
        }

        do {
            // Finder's "move ... with replacing" deletes the old item permanently (tested on macOS 27),
            // so replaced items go to the Trash first and can be restored.
            for target in replaceTargets {
                try fileManager.trashItem(at: target, resultingItemURL: nil)
            }
            if !toFinder.isEmpty {
                let files = toFinder.map { appleScriptFile($0.path) }.joined(separator: ", ")
                guard runScript("""
                tell application "Finder" to move {\(files)} to (\(appleScriptFile(destination.path)) as alias)
                """) != nil else { return }
            }
            for source in keepBoth {
                try fileManager.moveItem(at: source, to: uniqueURL(in: destination, for: source.lastPathComponent))
            }
            clearCut()
        } catch {
            showFailure(error.localizedDescription)
        }
    }

    private func askAboutClash(name: String, moreToCome: Bool) -> (ClashChoice, Bool) {
        let alert = NSAlert()
        alert.messageText = "An item named \u{201C}\(name)\u{201D} already exists in this location."
        alert.informativeText = "Replace moves the existing item to the Trash, so you can restore it."
        alert.addButton(withTitle: "Keep Both")
        alert.addButton(withTitle: "Stop").keyEquivalent = "\u{1b}"
        alert.addButton(withTitle: "Replace")
        if moreToCome {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Apply to all"
        }
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        let choice: ClashChoice = response == .alertFirstButtonReturn ? .keepBoth
            : response == .alertSecondButtonReturn ? .stop : .replace
        return (choice, alert.suppressionButton?.state == .on)
    }

    /// "name 2.ext", "name 3.ext", ... like Finder's Keep Both.
    private func uniqueURL(in folder: URL, for name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var number = 2
        while true {
            let candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            number += 1
        }
    }

    private func appleScriptFile(_ path: String) -> String {
        "POSIX file \"\(path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private func runScript(_ source: String) -> String? {
        var error: NSDictionary?
        let output = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            // Name clash, missing file, no Automation permission, etc. Keep the cut so the user can retry.
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error."
            NSLog("MacCut: AppleScript error \(error)")
            showFailure(message)
            return nil
        }
        return output?.stringValue ?? ""
    }

    private func showFailure(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Could not move the items"
        alert.informativeText = "\(message)\n\nThe cut is kept, so you can fix the problem and press \u{2318}V again."
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - Menu bar

    private func clearCut() {
        cutCount = nil
        cutItems = []
        refreshUI()
    }

    private func refreshUI() {
        guard let button = statusItem?.button else { return }
        let symbol = cutPending ? "scissors.circle.fill" : "scissors"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "MacCut")
        button.appearsDisabled = !enabled || tap == nil

        let menu = NSMenu()
        if tap == nil {
            menu.addItem(NSMenuItem(title: "\u{26A0}\u{FE0E} Needs Permission", action: nil, keyEquivalent: ""))
            menu.addItem(item("Grant Permission...", #selector(grantPermission)))
        } else {
            let status = !enabled ? "Paused" : (cutPending ? "Cut pending, press \u{2318}V in Finder" : "Active")
            menu.addItem(NSMenuItem(title: status, action: nil, keyEquivalent: ""))
        }
        menu.addItem(.separator())
        menu.addItem(item("Enabled", #selector(toggleEnabled), on: enabled))
        menu.addItem(item("Open at Login", #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled))
        menu.addItem(item("Reliable Mode", #selector(toggleReliable), on: reliableMode))
        menu.addItem(.separator())
        menu.addItem(item("How to Use...", #selector(showHelp)))
        menu.addItem(item("About", #selector(showAbout)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector, on: Bool? = nil) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        if let on { menuItem.state = on ? .on : .off }
        return menuItem
    }

    @objc private func toggleEnabled() { enabled.toggle() }
    @objc private func toggleReliable() { reliableMode.toggle() }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change Open at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nYou can add MacCut in System Settings > General > Login Items."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        refreshUI()
    }

    @objc private func grantPermission() {
        // Adds MacCut to the list in System Settings and shows the system prompt.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @objc private func showHelp() {
        if helpWindow == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable],
                                  backing: .buffered, defer: false)
            window.title = "How to Use MacCut"
            window.isReleasedWhenClosed = false
            let view = HelpView(icon: NSApp.applicationIconImage, permission: permission,
                                grantPermission: { [weak self] in self?.grantPermission() },
                                close: { [weak window] in window?.close() })
            window.contentView = NSHostingView(rootView: view)
            window.center()
            helpWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        helpWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func showAbout() {
        let small = NSFont.systemFont(ofSize: 11)
        // Name and license come from NSHumanReadableCopyright, shown by the panel below the credits.
        let credits = NSMutableAttributedString(
            string: "Cut and paste files in Finder with \u{2318}X and \u{2318}V.\nRuns locally. No network access.\n",
            attributes: [.font: small, .foregroundColor: NSColor.secondaryLabelColor])
        credits.append(NSAttributedString(string: "github.com/njirapat/MacCut",
                                          attributes: [.font: small, .link: URL(string: repoURL)!]))
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        credits.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: credits.length))
        NSApp.activate(ignoringOtherApps: true)
        // The About panel does not pick up AppIcon.icns on its own; pass the icon explicitly.
        // An empty .version hides the "(build number)" the panel adds after the version.
        NSApp.orderFrontStandardAboutPanel(options: [.applicationIcon: NSApp.applicationIconImage as Any,
                                                     .version: "",
                                                     .credits: credits])
    }
}

@main
enum MacCutApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
