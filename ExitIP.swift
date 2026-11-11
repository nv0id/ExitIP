// ExitIP: menu bar app that shows your public IPv4 address,
// green if it is a Mullvad exit IP, red if it is anything else.
//
// The only network call is to Mullvad's own "am I Mullvad" check.
// Build with ./build.sh (needs Xcode command line tools, macOS 13+).

import AppKit
import Network
import ServiceManagement

// MARK: - Settings

private let endpoint = URL(string: "https://ipv4.am.i.mullvad.net/json")!
private let refreshInterval: TimeInterval = 60   // seconds between routine checks
private let settleDelay: UInt64 = 1_000_000_000  // wait 1s after a network change

// MARK: - Model

struct ExitInfo: Decodable, Sendable {
    let ip: String
    let country: String?
    let city: String?
    let organization: String?
    let mullvadExitIP: Bool
    let mullvadHostname: String?

    enum CodingKeys: String, CodingKey {
        case ip, country, city, organization
        case mullvadExitIP = "mullvad_exit_ip"
        case mullvadHostname = "mullvad_exit_ip_hostname"
    }
}

enum Reading: Sendable {
    case checking
    case known(ExitInfo, Date)
    case failed(String, Date)
}

// MARK: - App

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private let monitor = NWPathMonitor()
    private var settleTask: Task<Void, Never>?
    private var generation = 0
    private var reading: Reading = .checking
    private var lastIP: String?

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .medium
        return f
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        render()

        // Routine re-check.
        timer = Timer.scheduledTimer(timeInterval: refreshInterval, target: self,
                                     selector: #selector(refreshNow), userInfo: nil, repeats: true)
        timer?.tolerance = 5

        // Re-check when the network changes (Wi-Fi switch, VPN up or down).
        monitor.pathUpdateHandler = { _ in
            Task { @MainActor in self.networkChanged() }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))

        // Re-check after sleep.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(refreshNow),
            name: NSWorkspace.didWakeNotification, object: nil)

        check()
    }

    // On a network change, keep showing the last reading and re-check quietly
    // once things settle. The display only changes when the new answer (or a
    // failure) comes back.
    private func networkChanged() {
        generation += 1          // drop any reply still in flight
        settleTask?.cancel()
        settleTask = Task {
            try? await Task.sleep(nanoseconds: settleDelay)
            if Task.isCancelled { return }
            self.check()
        }
    }

    @objc private func refreshNow() {
        check()
    }

    private func check() {
        generation += 1
        let gen = generation

        // New session every time, so a connection opened before a VPN change
        // is never reused to report a stale route.
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        let session = URLSession(configuration: config)

        var request = URLRequest(url: endpoint)
        request.setValue("close", forHTTPHeaderField: "Connection")

        session.dataTask(with: request) { data, response, error in
            let result: Reading
            if let data = data,
               let http = response as? HTTPURLResponse, http.statusCode == 200,
               let info = try? JSONDecoder().decode(ExitInfo.self, from: data) {
                result = .known(info, Date())
            } else {
                result = .failed(error?.localizedDescription ?? "Unexpected reply from Mullvad", Date())
            }
            Task { @MainActor in
                guard gen == self.generation else { return }   // superseded
                self.reading = result
                self.render()
            }
        }.resume()
        session.finishTasksAndInvalidate()
    }

    // MARK: Display

    private func render() {
        let title: String
        let color: NSColor
        switch reading {
        case .checking:
            title = "● checking"
            color = .secondaryLabelColor
        case .known(let info, _):
            lastIP = info.ip
            title = "● " + info.ip
            color = info.mullvadExitIP ? .systemGreen : .systemRed
        case .failed:
            // Couldn't check: show the last known address in grey, unconfirmed.
            title = "● " + (lastIP ?? "no reading")
            color = .secondaryLabelColor
        }
        statusItem.button?.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: color,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
        ])
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        func line(_ text: String) {
            let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        func action(_ text: String, _ selector: Selector, key: String = "") -> NSMenuItem {
            let item = NSMenuItem(title: text, action: selector, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
            return item
        }

        var hasIP = false
        switch reading {
        case .checking:
            line("Checking…")
        case .known(let info, let when):
            hasIP = true
            if info.mullvadExitIP {
                line("Mullvad exit" + (info.mullvadHostname.map { " (\($0))" } ?? ""))
            } else {
                line("NOT a Mullvad exit")
            }
            line("Network: " + (info.organization ?? "unknown"))
            let place = [info.city, info.country].compactMap { $0 }.joined(separator: ", ")
            if !place.isEmpty { line("Location: " + place) }
            line("Checked " + timeFormatter.string(from: when))
        case .failed(let reason, let when):
            line("Couldn't check: " + reason)
            if let ip = lastIP { line("Last known address: " + ip + " (unconfirmed)") }
            line("Tried " + timeFormatter.string(from: when))
        }

        menu.addItem(.separator())
        _ = action("Refresh Now", #selector(refreshNow), key: "r")
        if hasIP { _ = action("Copy IP", #selector(copyIP), key: "c") }

        let login = action("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit ExitIP", action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }

    // MARK: Actions

    @objc private func copyIP() {
        guard case .known(let info, _) = reading else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(info.ip, forType: .string)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Couldn't change the login item"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        render()
    }
}

// MARK: - Entry point

@main
@MainActor
enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
        app.run()
    }
}
