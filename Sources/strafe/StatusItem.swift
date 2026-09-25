import AppKit
import ServiceManagement
import Sparkle

/// The menu-bar controller. Owns the `NSStatusItem` and wires its menu to the
/// interceptor / permission state. LSUIElement is set in the bundled
/// Info.plist so there is no dock icon.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let interceptor: SwipeInterceptor
    private let engine: GestureSwitchEngine?
    private let hotkeys: HotkeyManager?
    private let updater: SPUStandardUpdaterController?
    private let launchAtStartup = LaunchAtStartup()
    private let launchAtStartupItem = NSMenuItem(
        title: "Launch at startup", action: #selector(toggleLaunchAtStartup), keyEquivalent: ""
    )
    private let approveLaunchAtStartupItem = NSMenuItem(
        title: "Allow launch in System Settings…", action: #selector(openLoginItemsSettings), keyEquivalent: ""
    )
    private let automaticUpdatesItem = NSMenuItem(
        title: "Automatically check for updates", action: #selector(toggleAutomaticUpdates), keyEquivalent: ""
    )

    private let toggleItem = NSMenuItem(
        title: "Enable", action: #selector(toggleEnabled), keyEquivalent: ""
    )
    private let speedItem = NSMenuItem(
        title: "Transition speed", action: nil, keyEquivalent: ""
    )
    private var speedItems: [NSMenuItem] = []
    private let hotkeysItem = NSMenuItem(
        title: "Space-switch hotkeys (⌃←/→)", action: #selector(toggleHotkeys), keyEquivalent: ""
    )
    private let accessibilityItem = NSMenuItem(
        title: "Accessibility granted: —", action: nil, keyEquivalent: ""
    )

    /// Shipped version, read from the bundle so `VERSION` stays the single
    /// source of truth (`Scripts/bundle.sh` stamps it into Info.plist). A bare
    /// `swift build` binary has no Info.plist, and "dev" is the honest answer
    /// there — it genuinely isn't a released build.
    private static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    init(
        interceptor: SwipeInterceptor, engine: GestureSwitchEngine? = nil,
        hotkeys: HotkeyManager? = nil, updater: SPUStandardUpdaterController? = nil
    ) {
        self.interceptor = interceptor
        self.engine = engine
        self.hotkeys = hotkeys
        self.updater = updater
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        // AppKit restores the previous visibility; every new launch starts visible.
        statusItem.isVisible = true

        if let button = statusItem.button {
            button.image = Bundle.main.image(forResource: "StrafeMenuBarTemplate")
                ?? NSImage(
                    systemSymbolName: "rectangle.on.rectangle",
                    accessibilityDescription: "strafe-tatoalo"
                )
            button.image?.size = NSSize(width: 18, height: 18)
            button.image?.isTemplate = true
            button.setAccessibilityLabel("strafe-tatoalo")
        }

        let menu = NSMenu()
        menu.delegate = self

        toggleItem.target = self
        accessibilityItem.isEnabled = false

        engine?.setTransitionSpeed(TransitionSpeed.stored)

        menu.addItem(toggleItem)
        buildSpeedSubmenu(into: menu)
        if hotkeys != nil {
            hotkeysItem.target = self
            menu.addItem(hotkeysItem)
        }
        menu.addItem(accessibilityItem)

        if Bundle.main.bundleIdentifier == Preferences.domain {
            menu.addItem(.separator())
            launchAtStartupItem.target = self
            menu.addItem(launchAtStartupItem)
            approveLaunchAtStartupItem.target = self
            menu.addItem(approveLaunchAtStartupItem)
        }

        menu.addItem(.separator())
        let versionItem = NSMenuItem(title: "strafe-tatoalo \(Self.version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        if let updater {
            let check = NSMenuItem(
                title: "Check for Updates…",
                action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: ""
            )
            check.target = updater
            menu.addItem(check)
            automaticUpdatesItem.target = self
            menu.addItem(automaticUpdatesItem)
        }

        menu.addItem(.separator())
        let hide = NSMenuItem(
            title: "Hide from menu bar", action: #selector(hideFromMenuBar), keyEquivalent: ""
        )
        hide.target = self
        menu.addItem(hide)
        let quit = NSMenuItem(title: "Quit strafe", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        refresh()
    }

    // Show the icon again. Called when the app is reopened while it is already running.
    func show() {
        statusItem.isVisible = true
    }

    /// The "Transition speed" submenu: one checkable item per preset.
    ///
    /// Hidden entirely when there is no real engine (stub engine / no
    /// Accessibility), because nothing it offers would take effect.
    private func buildSpeedSubmenu(into menu: NSMenu) {
        guard engine != nil else { return }

        let submenu = NSMenu()
        for speed in TransitionSpeed.allCases {
            let item = NSMenuItem(
                title: speed.title, action: #selector(selectSpeed(_:)), keyEquivalent: ""
            )
            item.target = self
            item.tag = speed.rawValue
            submenu.addItem(item)
            speedItems.append(item)
        }

        speedItem.submenu = submenu
        menu.addItem(speedItem)
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        // Toggle interception. The tap stays alive (so it can re-enable itself
        // after a system auto-disable); `overrideEnabled` gates whether real
        // swipes are actually suppressed and replaced (SPEC §2.2).
        interceptor.overrideEnabled.toggle()
        if interceptor.overrideEnabled && !interceptor.isRunning {
            interceptor.start()
        }
        refresh()
    }

    /// Pick a transition speed. Persisted so the choice survives a relaunch.
    @objc private func selectSpeed(_ sender: NSMenuItem) {
        let speed = TransitionSpeed.from(rawValue: sender.tag)
        engine?.setTransitionSpeed(speed)
        speed.persist()
        refresh()
    }

    /// Toggle the Ctrl+Left/Right global hotkeys, independent of the
    /// gesture tap (`toggleEnabled`). This is the mechanism that can conflict
    /// with third-party window-tiling shortcuts bound to the same chord.
    @objc private func toggleHotkeys() {
        guard let hotkeys else { return }
        let newValue = !HotkeyManager.enabled
        HotkeyManager.persist(enabled: newValue)
        hotkeys.applyStoredState()
        refresh()
    }

    @objc private func toggleAutomaticUpdates() {
        guard let updater else { return }
        updater.updater.automaticallyChecksForUpdates.toggle()
        refresh()
    }

    @objc private func toggleLaunchAtStartup() {
        do {
            try launchAtStartup.toggle()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t change launch at startup"
            alert.informativeText = error.localizedDescription
            NSApp.activate()
            alert.runModal()
        }
        refresh()
    }

    @objc private func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // AppKit saves visibility; initialization resets it on the next launch.
    @objc private func hideFromMenuBar() {
        let alert = NSAlert()
        alert.messageText = "Hide strafe-tatoalo from the menu bar?"
        alert.informativeText = """
            strafe-tatoalo stays running in the background. Swipes and keyboard \
            shortcuts keep working.

            To bring the icon back or to quit, open strafe-tatoalo again from \
            Applications or Spotlight.
            """
        alert.addButton(withTitle: "Hide")
        alert.addButton(withTitle: "Cancel")
        // An accessory app is never frontmost, so bring the alert forward.
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        statusItem.isVisible = false
    }

    @objc private func quit() {
        interceptor.teardown()
        NSApp.terminate(nil)
    }

    // MARK: - State

    private func refresh() {
        toggleItem.title = interceptor.overrideEnabled ? "Disable" : "Enable"
        if let engine {
            let current = engine.transitionSpeed
            speedItem.title = "Transition speed: \(current.title)"
            for item in speedItems { item.state = item.tag == current.rawValue ? .on : .off }
        }
        let granted = Permissions.isAccessibilityGranted
        accessibilityItem.title = "Accessibility granted: \(granted ? "yes" : "no")"
        hotkeysItem.state = HotkeyManager.enabled ? .on : .off
        automaticUpdatesItem.state = updater?.updater.automaticallyChecksForUpdates == true ? .on : .off
        let launchStatus = launchAtStartup.status
        launchAtStartupItem.state = switch launchStatus {
        case .enabled: .on
        case .requiresApproval: .mixed
        default: .off
        }
        launchAtStartupItem.title = launchStatus == .requiresApproval
            ? "Launch at startup (approval required)" : "Launch at startup"
        approveLaunchAtStartupItem.isHidden = launchStatus != .requiresApproval
    }
}
