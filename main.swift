import SwiftUI
import AppKit
import Network
import UniformTypeIdentifiers

// One open panel at a time: a second click on Install/Import while a panel is
// already up brings that panel forward instead of stacking another one.
private var activeOpenPanel: NSOpenPanel?
func presentOpenPanel(_ configure: (NSOpenPanel) -> Void, onOK: @escaping (NSOpenPanel) -> Void) {
    if let open = activeOpenPanel { open.makeKeyAndOrderFront(nil); return }
    let panel = NSOpenPanel()
    configure(panel)
    activeOpenPanel = panel
    panel.begin { resp in
        activeOpenPanel = nil
        if resp == .OK { onOK(panel) }
    }
}

// MARK: - Paths inside the bundle

enum Paths {
    static let contents  = Bundle.main.bundlePath + "/Contents"
    static let resources = contents + "/Resources"
    static let macOS     = contents + "/MacOS"
    static let gamesDir  = resources + "/games"
    static var activeGame: String {
        let text = (try? String(contentsOfFile: Paths.conf, encoding: .utf8)) ?? ""
        for line in text.split(separator: "\n") where line.hasPrefix("GAME=") {
            return String(line.dropFirst(5))
        }
        return ""
    }
    static var game: String {
        let n = activeGame
        let path = gamesDir + "/" + n
        return (!n.isEmpty && FileManager.default.fileExists(atPath: path)) ? path : resources + "/game"
    }
    static var addons: String { game + "/Interface/AddOns" }
    static var runPattern: String {
        // The installer records the entrypoint it found (GAME_EXE=); a repack may
        // name it anything, including something like WoWSirus.exe that the fixed
        // patterns below look like they cover and do not. Always append it — a
        // duplicate alternative costs nothing, a missed one loses the game.
        // WoW_tweaked.exe is always allowed too: vanilla-tweaks creates it after
        // the install, so it is never the recorded name.
        var names = ["[Ww]o[Ww]\\.exe", "[Ww]o[Ww]_[Tt]weaked\\.exe", "run\\.exe"]
        let recorded = confValue("GAME_EXE")
        if !recorded.isEmpty {
            names.append(NSRegularExpression.escapedPattern(for: recorded))
        }
        // The whole game path, not just its folder name: every copy of the app
        // has a games/main, and Stop (pkill -9) or a deferred quit must only ever
        // count this copy's game. rosettax87 shows the path with slashes, Wine's
        // Wow.exe as Z:\… backslashes, so each separator matches either.
        let sep = "[/\\\\]"
        let path = game.split(separator: "/").map { NSRegularExpression.escapedPattern(for: String($0)) }
        return sep + path.joined(separator: sep) + sep + "(" + names.joined(separator: "|") + ")"
    }
    // Paths is used before any Store exists, so it reads the conf itself.
    static func confValue(_ key: String) -> String {
        guard let text = try? String(contentsOfFile: conf, encoding: .utf8) else { return "" }
        for line in text.split(separator: "\n") where line.hasPrefix(key + "=") {
            return String(line.dropFirst(key.count + 1))
        }
        return ""
    }
    static let profileTool = resources + "/bin/wow-client-profile"
    static let installTool = resources + "/bin/wow-install-client"
    static let languageTool = resources + "/bin/wow-language"
    static let verifyTool  = resources + "/bin/wow-verify-game"
    static let settings  = resources + "/bin/wow-settings"
    static let launcher  = resources + "/bin/wow-launch"
    static let rosettaTool = resources + "/bin/wow-check-rosetta"
    static let conf      = resources + "/launcher.conf"
}

// MARK: - Helpers

@discardableResult
func shell(_ path: String, _ args: [String] = []) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return "ERROR: \(error.localizedDescription)" }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(data: data, encoding: .utf8) ?? ""
}

func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }
func LF(_ key: String, _ args: CVarArg...) -> String { String(format: NSLocalizedString(key, comment: ""), arguments: args) }

func stripWoWCodes(_ s: String) -> String {
    var t = s
    for pat in ["\\|c[0-9a-fA-F]{8}", "\\|r", "\\|T[^|]*\\|t"] {
        t = t.replacingOccurrences(of: pat, with: "", options: .regularExpression)
    }
    return t.trimmingCharacters(in: .whitespaces)
}

// MARK: - Models

struct AddOn: Identifiable, Hashable {
    let folder: String
    let title: String
    let version: String
    var id: String { folder }
}

struct DisplayOption: Identifiable, Hashable {
    let id: Int
    let name: String
    let ptsW: Int, ptsH: Int
    let pxW: Int, pxH: Int
    let axX: Int, axY: Int
    let isMain: Bool
    var isRetina: Bool { pxW != ptsW }
    var label: String { "\(name)\(isMain ? " (main)" : "") — \(pxW) × \(pxH)" }
}

// MARK: - Store

final class Store: ObservableObject {
    @Published var mode = "maximized"
    @Published var renderer = "dxvk"
    @Published var spatialAudio = true     // SPATIAL_AUDIO=0 → WOWSILICON_SPATIAL_AUDIO_MODE=off (else fixed)
    @Published var normalizeAudio = true   // NORMALIZE_AUDIO=0 → WOWSILICON_NORMALIZE_AUDIO=0 (else 1)
    @Published var closeOnPlay = false     // CLOSE_ON_PLAY=1 → quit after handing focus to the game
    @Published var patches = "all"        // PATCHES=all|no-silicon|winerosetta|none
    @Published var resolution = "…"
    @Published var retina = false
    @Published var autoRes = true
    @Published var addons: [AddOn] = []
    @Published var displays: [DisplayOption] = []
    @Published var selectedDisplay = 0
    @Published var games: [String] = []
    @Published var activeGame = ""
    @Published var gameVersion = ""
    // What wow-client-profile says about the installed client: what it is, and
    // which parts of the patch kit can physically apply to it.
    @Published var profile: [String: String] = [:]
    @Published var gameRunning = false
    // The runtime is x86_64: without Rosetta 2 nothing can start (issue after
    // the macOS 27 upgrade), so the Play pane says so instead of doing nothing.
    @Published var rosettaMissing = false
    @Published var loadingStatus = true
    @Published var busy = false
    @Published var note = ""
    // What an install is doing right now: the copy's share done (nil while a
    // step with no measurable progress runs), and one line saying what it is.
    @Published var installProgress: Double? = nil
    @Published var installStatus = ""
    private var installSourceApp: String?   // set while installing from a previous app

    init() {
        autoRes = !((try? String(contentsOfFile: Paths.conf, encoding: .utf8))?.contains("AUTO_RES=0") ?? false)
        let r = confGet("RENDERER")
        if !r.isEmpty { renderer = r }
        // on unless launcher.conf says 0 — absent = on, the AUTO_RES idiom wow-launch mirrors
        let sp = confGet("SPATIAL_AUDIO"), nm = confGet("NORMALIZE_AUDIO")
        spatialAudio = sp.isEmpty || sp == "1"
        normalizeAudio = nm.isEmpty || nm == "1"
        closeOnPlay = confGet("CLOSE_ON_PLAY") == "1"   // absent = stay open
        let lvl = confGet("PATCHES")
        if ["all", "no-silicon", "winerosetta", "none"].contains(lvl) { patches = lvl }
        else if confGet("SILICON") == "0" { patches = "no-silicon" }   // pre-2.4 toggle
        refreshDisplays()
        refreshGames()
        refreshRealms()
        refreshAddons()
        refreshStatus()
        checkRunning()
        checkRosetta()
    }

    func checkRosetta() {
        DispatchQueue.global().async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: Paths.rosettaTool)
            let missing = (try? { try p.run(); p.waitUntilExit(); return p.terminationStatus != 0 }()) ?? false
            DispatchQueue.main.async { self.rosettaMissing = missing }
        }
    }

    // MARK: status

    func refreshStatus() {
        loadingStatus = true
        DispatchQueue.global().async {
            let out = shell(Paths.settings, ["show"])
            var mode = "maximized", res = "?", ret = false
            for line in out.split(separator: "\n") {
                let l = line.trimmingCharacters(in: .whitespaces)
                if l.hasPrefix("mode:") {
                    if l.contains("maximized") { mode = "maximized" }
                    else if l.contains("fullscreen") { mode = "fullscreen" }
                    else { mode = "windowed" }
                } else if l.hasPrefix("resolution:") {
                    res = l.replacingOccurrences(of: "resolution:", with: "").trimmingCharacters(in: .whitespaces)
                } else if l.hasPrefix("retina:") {
                    ret = l.contains("on")
                }
            }
            DispatchQueue.main.async {
                self.mode = mode
                self.resolution = res
                self.retina = ret
                self.loadingStatus = false
            }
        }
    }

    func checkRunning() {
        let pattern = Paths.runPattern
        DispatchQueue.global().async {
            let out = shell("/usr/bin/pgrep", ["-f", pattern])
            let running = !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !out.hasPrefix("ERROR")
            DispatchQueue.main.async { self.gameRunning = running }
        }
    }

    // MARK: actions

    func play() {
        busy = true
        note = ""
        resolveDisplayRect()
        DispatchQueue.global().async {
            // Re-probed on every Play, so installing Rosetta clears this without
            // restarting the launcher. wow-launch checks too — for terminal use.
            let out = shell(Paths.launcher)
            guard !out.contains("ROSETTA:") else {
                DispatchQueue.main.async {
                    self.rosettaMissing = true
                    self.busy = false
                    self.note = L("The game cannot start: Rosetta 2 is not installed. Open Terminal and run: sudo softwareupdate --install-rosetta --agree-to-license")
                }
                return
            }
            DispatchQueue.main.async {
                self.rosettaMissing = false   // it started, so Rosetta is back
                self.gameRunning = true
                self.busy = false
                self.focusGame()
            }
        }
    }

    // Cooperative activation (macOS 14+) only lets the frontmost app pass
    // focus on — the game can never take it by itself. So stay alive until
    // the game window exists and hand activation over. The launcher then stays
    // behind the game; closing it (CLOSE_ON_PLAY, or by hand) is deferred by
    // deferQuitWhileGameRuns.
    private func focusGame() {
        let pattern = Paths.runPattern
        let deadline = Date().addingTimeInterval(30)
        func tick() {
            DispatchQueue.global().async {
                let out = shell("/usr/bin/pgrep", ["-f", pattern])
                let pids = Set(out.split(whereSeparator: \.isNewline)
                    .compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) })
                let winPID = Store.visibleWindowOwner(among: pids)
                DispatchQueue.main.async {
                    if let pid = winPID, let app = NSRunningApplication(processIdentifier: pid) {
                        self.gameApp = app
                        NSApp.yieldActivation(to: app)
                        app.activate(options: [])
                        if self.closeOnPlay {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
                        }
                    } else if Date() >= deadline || !NSApp.isActive {
                        if self.closeOnPlay { NSApp.terminate(nil) }
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { tick() }
                    }
                }
            }
        }
        tick()
    }

    // MARK: a safe close while the game runs

    private var gameApp: NSRunningApplication?   // the game window's owner, found by focusGame
    private var gameExitObserver: NSObjectProtocol?
    private var hiddenForGame = false
    private var quitAfterGame = false            // the game has gone: let the quit through

    // The game is Wine started as the launcher's child and has no identity of
    // its own, so its local-network access is the launcher's grant — on macOS 27
    // really quitting cuts a LAN session a few seconds later (#7). So a quit
    // while the game runs only takes the launcher off the screen (no window, no
    // Dock icon, no Cmd-Tab) and completes when the game exits. Returns true
    // when the quit was deferred.
    func deferQuitWhileGameRuns() -> Bool {
        if quitAfterGame { return false }
        if hiddenForGame { return true }
        let out = shell("/usr/bin/pgrep", ["-f", Paths.runPattern])
        guard !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !out.hasPrefix("ERROR") else { return false }
        hideUntilGameExits()
        return true
    }

    private func hideUntilGameExits() {
        hiddenForGame = true
        if let pid = gameApp?.processIdentifier, gameApp?.isTerminated == false {
            gameExitObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
            ) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.processIdentifier == pid else { return }
                self?.gameExited()
            }
        }
        NSApp.setActivationPolicy(.accessory)
        NSApp.hide(nil)
        pollWhileHidden()
    }

    // The notification is the fast path; this catches a game process macOS
    // never registered as an app, which would otherwise leave us hidden forever.
    private func pollWhileHidden() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.hiddenForGame else { return }
            let pattern = Paths.runPattern
            DispatchQueue.global().async {
                let out = shell("/usr/bin/pgrep", ["-f", pattern])
                // A pgrep that could not run says nothing — keep waiting rather
                // than quit and cut the session this exists to protect.
                let gone = out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                DispatchQueue.main.async { gone ? self.gameExited() : self.pollWhileHidden() }
            }
        }
    }

    private func gameExited() {
        guard hiddenForGame else { return }
        quitAfterGame = true
        NSApp.terminate(nil)
    }

    // Opened again while it waits: the user wants it back, so it stays — as a
    // normal window with Stop, and without quitting when the game exits.
    func showAgain() {
        guard hiddenForGame else { return }
        hiddenForGame = false
        if let o = gameExitObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        gameExitObserver = nil
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        NSApp.activate()
    }

    // Window-list metadata needs no Accessibility/Screen Recording permission.
    private static func visibleWindowOwner(among pids: Set<pid_t>) -> pid_t? {
        guard !pids.isEmpty,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return nil }
        for w in list {
            guard let pid = (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  pids.contains(pid),
                  (w[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 else { continue }
            return pid
        }
        return nil
    }

    func forceStop() {
        busy = true
        let pattern = Paths.runPattern
        DispatchQueue.global().async {
            _ = shell("/usr/bin/pkill", ["-9", "-f", pattern])
            Thread.sleep(forTimeInterval: 0.8)
            DispatchQueue.main.async {
                self.busy = false
                self.checkRunning()
            }
        }
    }

    func setMode(_ m: String) {
        mode = m
        busy = true
        DispatchQueue.global().async {
            _ = shell(Paths.settings, [m])
            DispatchQueue.main.async { self.busy = false; self.refreshStatus() }
        }
    }

    func setRetina(_ on: Bool) {
        let pts = windowPoints  // window size before the flag flips
        retina = on
        busy = true
        let auto = autoRes
        let windowed = mode == "windowed"
        let disp = displays.first(where: { $0.id == selectedDisplay })
        DispatchQueue.global().async {
            _ = shell(Paths.settings, ["retina", on ? "on" : "off"])
            if auto {
                _ = shell(Paths.settings, ["auto"])
            } else if windowed {
                // keep the same window size; retina just doubles the render pixels
                if let t = Store.scaled(pts, by: on ? 2 : 1) {
                    _ = shell(Paths.settings, ["resolution", t])
                }
            } else if let d = disp {
                let target = on ? "\(d.pxW)x\(d.pxH)" : "\(d.ptsW)x\(d.ptsH)"
                _ = shell(Paths.settings, ["resolution", target])
            }
            DispatchQueue.main.async { self.busy = false; self.refreshStatus() }
        }
    }

    // MARK: windowed size

    // Common 4:3 / 16:10 / 16:9 sizes of the WotLK era, in window points.
    static let windowSizes = ["800x600", "1024x768", "1152x864", "1280x720",
                              "1280x800", "1280x1024", "1440x900", "1600x900",
                              "1680x1050", "1920x1080", "1920x1200"]

    static func scaled(_ res: String, by factor: Int) -> String? {
        let p = res.lowercased().split(separator: "x").compactMap { Int($0) }
        guard p.count == 2 else { return nil }
        return "\(p[0] * factor)x\(p[1] * factor)"
    }

    // Window size in points: gxResolution is pixels, halved when retina is on.
    var windowPoints: String {
        let p = resolution.lowercased().split(separator: "x").compactMap { Int($0) }
        guard p.count == 2 else { return resolution }
        return retina ? "\(p[0] / 2)x\(p[1] / 2)" : resolution
    }

    func setWindowSize(_ pts: String) {
        guard let target = Store.scaled(pts, by: retina ? 2 : 1) else { return }
        // a fixed size only survives the launch if auto-match doesn't overwrite it
        if autoRes { setAuto(false) }
        busy = true
        DispatchQueue.global().async {
            _ = shell(Paths.settings, ["windowed", target])
            DispatchQueue.main.async { self.busy = false; self.refreshStatus() }
        }
    }

    func setRenderer(_ r: String) {
        renderer = r
        confSet("RENDERER", r)
        note = LF("Renderer set to %@ — takes effect at the next game start.", r == "mtld3d" ? "MTLd3D" : "DXVK")
    }

    // Both are read by wow-launch and exported into the runtime's environment;
    // the winecoreaudio driver picks them up when the game's audio stream opens.
    func setSpatialAudio(_ on: Bool) {
        spatialAudio = on
        confSet("SPATIAL_AUDIO", on ? "1" : "0")
        note = on ? L("Spatial audio turned on — takes effect at the next game start.")
                  : L("Spatial audio turned off — takes effect at the next game start.")
    }

    func setNormalizeAudio(_ on: Bool) {
        normalizeAudio = on
        confSet("NORMALIZE_AUDIO", on ? "1" : "0")
        note = on ? L("Volume normalization turned on — takes effect at the next game start.")
                  : L("Volume normalization turned off — takes effect at the next game start.")
    }

    // Read when Play hands focus to the game, so it applies from the next Play — no note needed.
    func setCloseOnPlay(_ on: Bool) {
        closeOnPlay = on
        confSet("CLOSE_ON_PLAY", on ? "1" : "0")
    }

    // Applied by the repair path: verify's expected state follows PATCHES=, so
    // --fix adds or removes the mod loader, libSiliconPatch and the icon patch.
    func setPatches(_ v: String) {
        patches = v
        confSet("PATCHES", v)
        if games.isEmpty { return }
        verifyGame(fix: true)
        loadProfile()
    }

    // Why the list is shorter than the usual four, in this client's own terms.
    var patchLimitNote: String {
        guard !games.isEmpty, patchLevels.count < 4 else { return "" }
        if profile["ARCH"] == "x64" {
            return L("This client is 64-bit — everything the launcher adds is 32-bit only, so none of it can load into the game.")
        }
        if profile["CAP_LOADER"] != "1" {
            return L("This client has no Divx decoder for the mod loader to hook, so no extra DLL can be added to it.")
        }
        return L("libSiliconPatch exists only for 3.3.5a (12340) and 1.12 clients; the other levels apply as usual.")
    }

    var patchesDescription: String {
        switch patches {
        case "no-silicon":
            return L("Everything except libSiliconPatch. Try this if the game crashes, or if your server treats the speed hooks as tampering.")
        case "winerosetta":
            return L("Keeps just winerosetta — a small shim that fills in CPU instructions Apple Silicon does not run natively. That is what servers with anti-cheat (Warden) need. Nothing else in the game folder is changed.")
        case "none":
            return L("Runs the client exactly as it shipped. Fine on servers without anti-cheat — but if the server runs Warden, the game can crash once it starts checking.")
        default:
            return L("Everything on, including libSiliconPatch — speed hooks inside the game code that can raise the frame rate.")
        }
    }

    func setAuto(_ v: Bool) {
        autoRes = v
        confSet("AUTO_RES", v ? "1" : "0")
        if v {
            busy = true
            DispatchQueue.global().async {
                _ = shell(Paths.settings, ["auto"])
                DispatchQueue.main.async { self.busy = false; self.refreshStatus() }
            }
        }
    }

    // The one place a Retina choice made by hand is dropped again: detecting the
    // screen means "set what fits it best", including Retina.
    func detectNow() {
        busy = true
        DispatchQueue.global().async {
            let out = shell(Paths.settings, ["auto", "reset"])
            DispatchQueue.main.async {
                self.busy = false
                self.note = out.trimmingCharacters(in: .whitespacesAndNewlines)
                self.refreshDisplays()
                self.refreshStatus()
            }
        }
    }

    func applyDisplay(_ id: Int) {
        selectedDisplay = id
        guard let d = displays.first(where: { $0.id == id }) else { return }
        let target = retina ? "\(d.pxW)x\(d.pxH)" : "\(d.ptsW)x\(d.ptsH)"
        busy = true
        if !d.isMain && autoRes { setAuto(false) }
        confSet("GAME_DISPLAY", d.isMain ? "" : d.name)
        confSet("DISPLAY_RECT", d.isMain ? "" : "\(d.axX),\(d.axY),\(d.ptsW),\(d.ptsH)")
        DispatchQueue.global().async {
            _ = shell(Paths.settings, ["resolution", target])
            DispatchQueue.main.async {
                self.busy = false
                self.note = d.isMain ? "" :
                    LF("The game window will be moved to %@ shortly after launch.", d.name)
                self.refreshStatus()
            }
        }
    }

    private func resolveDisplayRect() {
        let name = confGet("GAME_DISPLAY")
        guard !name.isEmpty else { confSet("DISPLAY_RECT", ""); return }
        refreshDisplays()
        if let d = displays.first(where: { $0.name == name && !$0.isMain }) {
            confSet("DISPLAY_RECT", "\(d.axX),\(d.axY),\(d.ptsW),\(d.ptsH)")
        } else {
            confSet("DISPLAY_RECT", "")
        }
    }

    func refreshDisplays() {
        var opts: [DisplayOption] = []
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        for (i, s) in NSScreen.screens.enumerated() {
            let pts = s.frame.size
            let scale = s.backingScaleFactor
            opts.append(DisplayOption(
                id: i,
                name: s.localizedName,
                ptsW: Int(pts.width), ptsH: Int(pts.height),
                pxW: Int(pts.width * scale), pxH: Int(pts.height * scale),
                axX: Int(s.frame.minX), axY: Int(primaryMaxY - s.frame.maxY),
                isMain: s == NSScreen.main || i == 0 && NSScreen.main == nil
            ))
        }
        displays = opts
        let wanted = confGet("GAME_DISPLAY")
        if !wanted.isEmpty, let d = opts.first(where: { $0.name == wanted && !$0.isMain }) {
            selectedDisplay = d.id
        } else if let main = opts.first(where: { $0.isMain }) {
            selectedDisplay = main.id
        }
    }

    func confGet(_ key: String) -> String {
        let text = (try? String(contentsOfFile: Paths.conf, encoding: .utf8)) ?? ""
        for line in text.split(separator: "\n") where line.hasPrefix(key + "=") {
            return String(line.dropFirst(key.count + 1))
        }
        return ""
    }

    func confSet(_ key: String, _ value: String) {
        var lines = ((try? String(contentsOfFile: Paths.conf, encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)
        lines.removeAll { $0.hasPrefix(key + "=") }
        lines.append("\(key)=\(value)")
        try? (lines.joined(separator: "\n") + "\n").write(toFile: Paths.conf, atomically: true, encoding: .utf8)
    }

    // MARK: games

    func refreshGames() {
        let fm = FileManager.default
        let dirs = ((try? fm.contentsOfDirectory(atPath: Paths.gamesDir)) ?? [])
            .filter { !$0.hasPrefix(".") }
            .filter { name in   // any client, so any .exe in the folder root counts
                ((try? fm.contentsOfDirectory(atPath: Paths.gamesDir + "/" + name)) ?? [])
                    .contains { $0.lowercased().hasSuffix(".exe") }
            }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        games = dirs
        activeGame = Paths.activeGame
        if activeGame.isEmpty || !dirs.contains(activeGame), let first = dirs.first {
            confSet("GAME", first)
            activeGame = first
        }
        loadProfile()
    }

    static func readProfile(_ dir: String?) -> [String: String] {
        let out = shell(Paths.profileTool, dir.map { [$0] } ?? [])
        var d: [String: String] = [:]
        for line in out.split(separator: "\n") {
            guard let eq = line.firstIndex(of: "=") else { continue }
            d[String(line[line.startIndex..<eq])] = String(line[line.index(after: eq)...])
        }
        return d
    }

    // Reading the client's version resource takes about a second, so never on
    // the main thread — the window would stall on every refresh.
    func loadProfile() {
        guard !games.isEmpty else {
            profile = [:]; gameVersion = ""; refreshLanguages(); return
        }
        DispatchQueue.global().async {
            let p = Store.readProfile(nil)
            DispatchQueue.main.async {
                self.profile = p
                let v = p["VERSION"] ?? ""
                self.gameVersion = (v == "unknown") ? "" : v
                // show the level that is actually in force, not one this client
                // cannot take — the request itself stays recorded in PATCHES=
                if let eff = p["PATCHES"], !eff.isEmpty { self.patches = eff }
                self.refreshLanguages()
            }
        }
    }

    // The levels this client can actually take, highest first. Empty profile
    // (no game installed yet) shows the full set — the picker is disabled then.
    var patchLevels: [String] {
        let offered = (profile["LEVELS"] ?? "").split(separator: " ").map(String.init)
        return offered.isEmpty ? ["all", "no-silicon", "winerosetta", "none"] : offered
    }

    func patchLevelLabel(_ level: String) -> String {
        switch level {
        case "no-silicon":  return L("All except libSiliconPatch")
        case "winerosetta": return L("Only winerosetta")
        case "none":        return L("No patches — original client")
        default:            return L("All patches (recommended)")
        }
    }

    // MARK: language packs

    @Published var languages: [String] = []
    @Published var activeLanguage = ""

    // Language packs swap Wow.exe with the pack's locale-matched build, so they
    // only apply to Blizzard 3.3.5a/2.4.3 clients — a custom entrypoint has none.
    var supportsLanguagePacks: Bool {
        !games.isEmpty && profile["CAP_LANGPACK"] == "1"
    }

    func refreshLanguages() {
        guard supportsLanguagePacks else { languages = []; activeLanguage = ""; return }
        DispatchQueue.global().async {
            let out = shell(Paths.languageTool, ["list"])
            var all: [String] = []
            var active = ""
            for line in out.split(separator: "\n") {
                let l = String(line)
                if l.hasPrefix("* ") { active = String(l.dropFirst(2)); all.append(active) }
                else { all.append(l.trimmingCharacters(in: .whitespaces)) }
            }
            DispatchQueue.main.async {
                self.languages = all.filter { !$0.isEmpty }
                self.activeLanguage = active
            }
        }
    }

    func setLanguage(_ loc: String) {
        guard loc != activeLanguage else { return }
        activeLanguage = loc
        busy = true
        DispatchQueue.global().async {
            let out = shell(Paths.languageTool, ["switch", loc])
            DispatchQueue.main.async {
                self.busy = false
                self.note = out.split(separator: "\n").suffix(1).joined()
                self.refreshLanguages()
                self.refreshRealms()
                self.refreshStatus()
                self.loadProfile()   // the switch swapped Wow.exe — CAP_ICON follows it
            }
        }
    }

    func importLanguagePackFromPanel() {
        presentOpenPanel({ panel in
            panel.title = L("Import Language Pack")
            panel.message = LF("Choose a %@ client folder in another language — only its language pack is imported", self.gameVersion)
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
        }) { panel in
            guard let url = panel.url else { return }
            self.busy = true
            self.note = LF("Importing language pack from %@…", url.lastPathComponent)
            DispatchQueue.global().async {
                let out = shell(Paths.languageTool, ["import", url.path])
                DispatchQueue.main.async {
                    self.busy = false
                    self.note = out.split(separator: "\n").suffix(1).joined()
                    self.refreshLanguages()
                }
            }
        }
    }

    struct VerifyItem: Identifiable {
        enum Status { case ok, fail, warn }
        let id = UUID()
        let name: String
        let status: Status
    }

    @Published var verifySheet = false
    @Published var verifyItems: [VerifyItem] = []
    @Published var verifyProgress: Double = 0
    @Published var verifyCurrent = ""
    @Published var verifyResult = ""
    @Published var verifyRunning = false
    @Published var verifyCanFix = false
    @Published var verifyNeedsReinstall = false
    private var verifyProc: Process?

    func verifyGame(fix: Bool = false) {
        verifyItems = []
        verifyProgress = 0
        verifyCurrent = ""
        verifyResult = ""
        verifyCanFix = false
        verifyNeedsReinstall = false
        // The script re-probes and prints ROSETTA if it is still missing, so a
        // flag left over from before Rosetta was installed must not survive.
        rosettaMissing = false
        verifyRunning = true
        verifySheet = true
        let p = Process()
        p.executableURL = URL(fileURLWithPath: Paths.verifyTool)
        p.arguments = fix ? ["--fix"] : []
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        var buf = ""
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty else { return }
            buf += String(data: d, encoding: .utf8) ?? ""
            while let r = buf.range(of: "\n") {
                let line = String(buf[..<r.lowerBound])
                buf.removeSubrange(..<r.upperBound)
                DispatchQueue.main.async { self?.handleVerifyLine(line) }
            }
        }
        p.terminationHandler = { [weak self] _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                self?.verifyRunning = false
                if self?.verifyResult.isEmpty == true {
                    self?.verifyResult = L("Verification stopped.")
                }
            }
        }
        verifyProc = p
        do { try p.run() } catch {
            verifyRunning = false
            verifyResult = LF("Could not start verification: %@", error.localizedDescription)
        }
    }

    func cancelVerify() {
        verifyProc?.terminate()
    }

    private func handleVerifyLine(_ line: String) {
        if line.hasPrefix("ok: ") {
            verifyItems.append(VerifyItem(name: String(line.dropFirst(4)), status: .ok))
        } else if line.hasPrefix("FAIL: ") {
            verifyItems.append(VerifyItem(name: String(line.dropFirst(6)), status: .fail))
        } else if line.hasPrefix("WARN: ") {
            verifyItems.append(VerifyItem(name: String(line.dropFirst(6)), status: .warn))
        } else if line.hasPrefix("PROGRESS ") {
            let parts = line.split(separator: " ", maxSplits: 3).map(String.init)
            if parts.count >= 4, let i = Double(parts[1]), let t = Double(parts[2]), t > 0 {
                verifyProgress = max(verifyProgress, (i - 1) / t)
                verifyCurrent = parts[3]
            }
        } else if line == "CANFIX" {
            verifyCanFix = true
        } else if line == "REINSTALL" {
            verifyNeedsReinstall = true
        } else if line == "ROSETTA" {
            rosettaMissing = true
        } else if line.hasPrefix("RESULT: ") {
            verifyResult = String(line.dropFirst(8))
            verifyProgress = 1
            verifyCurrent = ""
        }
    }

    func installGameFromPanel() {
        presentOpenPanel({ panel in
            panel.title = L("Install Game Client")
            panel.message = L("Choose a WoW client folder — it needs a game executable and a Data folder")
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
        }) { panel in
            guard let url = panel.url else { return }
            self.installGame(from: url)
        }
    }

    // An older copy of this app as the source: its game is already patched, so
    // wow-install-client copies and verifies it instead. The check here is only
    // for a proper dialog — the script checks again and is the one that decides.
    func installFromAppPanel() {
        presentOpenPanel({ panel in
            panel.title = L("Install from Previous App")
            panel.message = L("Choose an older WoW Launcher app (2.1 or later) — its game is copied and verified, the app itself is left as it is")
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowedContentTypes = [.applicationBundle]
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
        }) { panel in
            guard let url = panel.url else { return }
            if let why = Store.previousAppProblem(url) {
                let a = NSAlert()
                a.alertStyle = .warning
                a.messageText = L("This app cannot be installed from")
                a.informativeText = why
                a.runModal()
                return
            }
            self.startInstall(from: url)
        }
    }

    static func previousAppProblem(_ url: URL) -> String? {
        let name = url.deletingPathExtension().lastPathComponent
        if url.resolvingSymlinksInPath() == Bundle.main.bundleURL.resolvingSymlinksInPath() {
            return L("That is this launcher itself — choose the previous copy.")
        }
        let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any] ?? [:]
        let id = info["CFBundleIdentifier"] as? String ?? ""
        let version = info["CFBundleShortVersionString"] as? String ?? ""
        // 1.0 and 2.0 carried local.wow335.singleapp; 2.1 is the first with this one
        let n = version.split(separator: ".").map { Int($0) ?? 0 }
        let tooOld = id == "local.wow335.singleapp"
            || (n.first ?? 0, n.count > 1 ? n[1] : 0) < (2, 1)
        if id != "io.github.matasarei.wow-launcher" && id != "local.wow335.singleapp" {
            return LF("%@ is not a WoW Launcher app.", name)
        }
        if tooOld {
            return LF("%@ %@ is too old to install from — WoW Launcher 2.1 or later is needed.", name, version)
        }
        return nil
    }

    func installGame(from url: URL) {
        busy = true
        note = L("Checking the client…")
        DispatchQueue.global().async {
            let p = Store.readProfile(url.path)
            DispatchQueue.main.async {
                self.busy = false
                guard self.confirmNothingApplies(p) else { self.note = ""; return }
                self.startInstall(from: url)
            }
        }
    }

    // Copying a client takes minutes and as much disk as the folder holds, so a
    // client the launcher can do nothing for is confirmed before, not after.
    private func confirmNothingApplies(_ p: [String: String]) -> Bool {
        guard (p["LEVELS"] ?? "") == "none" else { return true }
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = L("None of the launcher's patches apply to this client")
        if p["ARCH"] == "x64" {
            a.informativeText = L("It is a 64-bit client, and everything the launcher adds — the DXVK renderer, the mod loader, the speed hooks — is 32-bit only. The client will be copied in and started exactly as it shipped, which may well not work at all.")
        } else {
            a.informativeText = L("The client will be copied in and started exactly as it shipped. Copying takes a while and uses as much disk space as the client folder.")
        }
        a.addButton(withTitle: L("Install Anyway"))
        a.addButton(withTitle: L("Cancel"))
        return a.runModal() == .alertFirstButtonReturn
    }

    private func startInstall(from url: URL) {
        installSourceApp = url.pathExtension.lowercased() == "app" ? url.deletingPathExtension().lastPathComponent : nil
        busy = true
        note = LF("Installing from %@…", url.lastPathComponent)
        // Streamed rather than run through shell(): copying from a slow drive
        // takes minutes, and wow-copy's COPY lines are what the bar is drawn from.
        var lines: [String] = []
        let p = Process()
        p.executableURL = URL(fileURLWithPath: Paths.installTool)
        p.arguments = [url.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        var buf = ""
        // Finished at end of output, not at process exit: a terminationHandler
        // can run while the last lines — "game installed" among them — still
        // sit unread in the pipe (the same wait shell() did with readDataToEndOfFile).
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty else {
                h.readabilityHandler = nil
                p.waitUntilExit()
                // queued behind the last line handlers, so `lines` is complete here
                DispatchQueue.main.async { self?.finishInstall(lines) }
                return
            }
            buf += String(data: d, encoding: .utf8) ?? ""
            while let r = buf.range(of: "\n") {
                let line = String(buf[..<r.lowerBound])
                buf.removeSubrange(..<r.upperBound)
                DispatchQueue.main.async {
                    guard let self = self, !line.isEmpty else { return }
                    if self.handleCopyLine(line) { return }
                    lines.append(line)
                    self.installProgress = nil   // patching has no bar, only a spinner
                    self.installStatus = line
                }
            }
        }
        do { try p.run() } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            busy = false
            note = "ERROR: \(error.localizedDescription)"
        }
    }

    private func finishInstall(_ lines: [String]) {
        busy = false
        installProgress = nil
        installStatus = ""
        note = lines.suffix(2).joined(separator: " — ")
        refreshGames()
        refreshStatus()
        refreshRealms()
        refreshAddons()
        if lines.contains(where: { $0.contains("game installed") }) {
            if let old = installSourceApp {
                note = LF("Installed from %@, which was left as it is — it can be deleted once the game runs.", old)
            }
            verifyGame()   // confirm the fresh install right away
        }
    }

    // "COPY <done KB> <total KB> <file>" from wow-copy → the bar and its line.
    private func handleCopyLine(_ line: String) -> Bool {
        guard line.hasPrefix("COPY ") else { return false }
        let parts = line.split(separator: " ", maxSplits: 3).map(String.init)
        guard parts.count >= 3, let done = Double(parts[1]), let total = Double(parts[2]), total > 0 else { return true }
        installProgress = min(done / total, 1)
        let size = { (kb: Double) in ByteCountFormatter.string(fromByteCount: Int64(kb * 1024), countStyle: .file) }
        let file = parts.count > 3 ? parts[3] : ""
        installStatus = file.isEmpty ? LF("Copied %@ of %@", size(done), size(total))
                                     : LF("Copying %@ — %@ of %@", file, size(done), size(total))
        return true
    }

    // MARK: realmlist

    struct Realm: Identifiable, Hashable {
        let addr: String
        let active: Bool
        var id: String { addr }
    }

    @Published var realms: [Realm] = []
    private var realmFiles: [String] = []

    private func realmAddr(_ line: String) -> String? {
        var l = line.trimmingCharacters(in: .whitespaces)
        while l.hasPrefix("#") { l = String(l.dropFirst()).trimmingCharacters(in: .whitespaces) }
        guard l.lowercased().hasPrefix("set realmlist") else { return nil }
        let addr = l.dropFirst("set realmlist".count).trimmingCharacters(in: .whitespaces)
        return addr.isEmpty ? nil : addr
    }

    private func readTextFile(_ path: String) -> String? {
        for enc in [String.Encoding.utf8, .windowsCP1251, .isoLatin1] {
            if let text = try? String(contentsOfFile: path, encoding: enc) {
                // CRLF must become LF: "\r\n" is a single Character in Swift,
                // so split(separator: "\n") never splits Windows-ending files.
                return text.replacingOccurrences(of: "\r\n", with: "\n")
                           .replacingOccurrences(of: "\r", with: "\n")
            }
        }
        return nil
    }

    private func isCommented(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("#")
    }

    func refreshRealms() {
        let fm = FileManager.default
        var files: [String] = []
        let dataDir = Paths.game + "/Data"
        for loc in (try? fm.contentsOfDirectory(atPath: dataDir)) ?? [] {
            let p = dataDir + "/" + loc + "/realmlist.wtf"
            if fm.fileExists(atPath: p) { files.append(p) }
        }
        let root = Paths.game + "/realmlist.wtf"
        if fm.fileExists(atPath: root) { files.append(root) }
        realmFiles = files
        var list: [Realm] = []
        if let first = files.first,
           let raw = readTextFile(first) {
            for line in raw.split(separator: "\n") {
                let l = String(line)
                guard let addr = realmAddr(l) else { continue }
                if !list.contains(where: { $0.addr == addr }) {
                    list.append(Realm(addr: addr, active: !isCommented(l)))
                }
            }
        }
        if !list.contains(where: { $0.active }), !list.isEmpty {
            list[0] = Realm(addr: list[0].addr, active: true)
        }
        // Install and language switch re-read realmlist.wtf without writeRealms;
        // a test result about a server that is no longer active must go too.
        let wasActive = realms.first(where: { $0.active })?.addr
        realms = list
        if realms.first(where: { $0.active })?.addr != wasActive { cancelRealmTest() }
    }

    private func writeRealms(_ list: [Realm]) {
        cancelRealmTest()   // a result is about the server that was active
        let block = list.map { $0.active ? "set realmlist \($0.addr)" : "# set realmlist \($0.addr)" }
        for path in realmFiles {
            let raw = readTextFile(path) ?? ""
            var out: [String] = []
            var inserted = false
            for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
                if realmAddr(String(line)) != nil {
                    if !inserted { out.append(contentsOf: block); inserted = true }
                } else {
                    out.append(String(line))
                }
            }
            if !inserted { out.append(contentsOf: block) }
            while out.last?.isEmpty == true { out.removeLast() }
            try? (out.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
        }
        refreshRealms()
    }

    func selectRealm(_ addr: String) {
        writeRealms(realms.map { Realm(addr: $0.addr, active: $0.addr == addr) })
    }

    func addRealm(_ addr: String) {
        let a = addr.trimmingCharacters(in: .whitespaces)
        guard !a.isEmpty, !a.contains(" ") else { note = L("Invalid server address."); return }
        guard !realms.contains(where: { $0.addr == a }) else { selectRealm(a); return }
        writeRealms(realms.map { Realm(addr: $0.addr, active: false) } + [Realm(addr: a, active: true)])
        note = LF("Server %@ added and selected — takes effect at next game start.", a)
    }

    func removeRealm(_ addr: String) {
        var rest = realms.filter { $0.addr != addr }
        guard !rest.isEmpty else {
            note = L("At least one server is required — add another before removing this one.")
            return
        }
        if !rest.contains(where: { $0.active }) {
            rest[0] = Realm(addr: rest[0].addr, active: true)
        }
        writeRealms(rest)
    }

    // MARK: connection test

    @Published var realmTestRunning = false
    @Published var realmTestResult = ""
    @Published var realmTestPassed: Bool?   // nil while waiting — neither green nor red
    private var realmTest: NWConnection?

    // One TCP connect to the active realm, made by the launcher itself. The game
    // is Wine started as the launcher's child, so macOS credits its connections
    // to the launcher: for a LAN realm this is the same Local Network grant the
    // game uses, asked for here, in front, instead of behind the game window.
    // While the prompt is up the path may already read localNetworkDenied, so
    // that alone is not a verdict — only still denied when the wait runs out is.
    func testRealmConnection() {
        guard !realmTestRunning, let addr = realms.first(where: { $0.active })?.addr else { return }
        var host = addr, port: UInt16 = 3724
        // host:port — only with a single colon; a bare IPv6 address has several
        if addr.filter({ $0 == ":" }).count == 1, let colon = addr.firstIndex(of: ":"),
           let p = UInt16(addr[addr.index(after: colon)...]) {
            host = String(addr[..<colon])
            port = p
        }
        guard !host.isEmpty, let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let queue = DispatchQueue(label: "realm-connection-test")
        var denied = false
        var lastError: NWError?
        realmTest = conn
        realmTestRunning = true
        realmTestResult = ""
        realmTestPassed = nil

        func finish(_ message: String, passed: Bool = false) {
            DispatchQueue.main.async {
                guard self.realmTest === conn else { return }   // superseded or cancelled
                conn.cancel()
                self.realmTest = nil
                self.realmTestRunning = false
                self.realmTestResult = message
                self.realmTestPassed = passed
            }
        }
        let blocked = L("macOS is blocking local network access for WoW. Allow it in System Settings → Privacy & Security → Local Network, then quit and reopen both the launcher and the game.")

        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                finish(LF("Connected to %@ — this server is reachable.", addr), passed: true)
            case .waiting(let err), .failed(let err):
                if case .posix(let code) = err, code == .ECONNREFUSED {
                    finish(LF("%@ answered, but nothing is listening on port %@ — is the server running?", host, String(port)))
                    return
                }
                if case .dns = err {   // unknown host name — no point waiting it out
                    finish(LF("Could not connect to %@: %@", addr, err.localizedDescription))
                    return
                }
                lastError = err
                // Blocked local-network access does not always reach the path as
                // localNetworkDenied: macOS also reports it as ENETDOWN ("Network
                // is down", what a fresh copy of the app gets on macOS 27) or as
                // EHOSTUNREACH. Treating those as a plain error would print the
                // confusing message this button exists to replace.
                denied = conn.currentPath?.unsatisfiedReason == .localNetworkDenied
                if case .posix(let code) = err, code == .ENETDOWN || code == .EHOSTUNREACH {
                    denied = true
                }
                if denied {
                    DispatchQueue.main.async {
                        if self.realmTest === conn {
                            self.realmTestResult = L("Waiting for macOS to allow local network access…")
                        }
                    }
                } else if case .failed = state {
                    finish(LF("Could not connect to %@: %@", addr, err.localizedDescription))
                }
            default:
                break
            }
        }
        conn.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 30) {
            if denied {
                finish(blocked)
            } else if let err = lastError {
                finish(LF("Could not connect to %@: %@", addr, err.localizedDescription))
            } else {
                finish(LF("No answer from %@ within 30 seconds.", addr))
            }
        }
    }

    private func cancelRealmTest() {
        realmTest?.cancel()
        realmTest = nil
        realmTestRunning = false
        realmTestResult = ""
        realmTestPassed = nil
    }

    // MARK: addons

    func refreshAddons() {
        DispatchQueue.global().async {
            let fm = FileManager.default
            var list: [AddOn] = []
            let dirs = (try? fm.contentsOfDirectory(atPath: Paths.addons)) ?? []
            for dir in dirs where !dir.hasPrefix(".") && !dir.hasPrefix("Blizzard_") {
                let folderPath = Paths.addons + "/" + dir
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: folderPath, isDirectory: &isDir), isDir.boolValue else { continue }
                var title = dir, version = ""
                let files = (try? fm.contentsOfDirectory(atPath: folderPath)) ?? []
                let tocs = files.filter { $0.lowercased().hasSuffix(".toc") }
                let toc = tocs.first(where: { $0.lowercased() == dir.lowercased() + ".toc" }) ?? tocs.first
                if let toc = toc {
                    let raw = self.readTextFile(folderPath + "/" + toc) ?? ""
                    for line in raw.split(separator: "\n").prefix(40) {
                        let l = line.trimmingCharacters(in: .whitespaces)
                        if l.hasPrefix("## Title:") {
                            let t = stripWoWCodes(String(l.dropFirst(9)))
                            if !t.isEmpty { title = t }
                        } else if l.hasPrefix("## Version:") {
                            version = String(l.dropFirst(11)).trimmingCharacters(in: .whitespaces)
                            // the UI prepends "v" — drop the toc's own prefix (v1.0.3)
                            if version.lowercased().hasPrefix("v"), version.count > 1,
                               version[version.index(after: version.startIndex)].isNumber {
                                version = String(version.dropFirst())
                            }
                        }
                    }
                }
                list.append(AddOn(folder: dir, title: title, version: version))
            }
            list.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            DispatchQueue.main.async { self.addons = list }
        }
    }

    private func addonRoots(_ url: URL, depth: Int = 0) -> [URL] {
        let fm = FileManager.default
        let name = url.lastPathComponent
        if name.hasPrefix(".") || name == "__MACOSX" { return [] }
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return [] }
        let items = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        if items.contains(where: { $0.pathExtension.lowercased() == "toc" }) { return [url] }
        guard depth < 3 else { return [] }
        return items.flatMap { addonRoots($0, depth: depth + 1) }
    }

    func installFromPanel() {
        presentOpenPanel({ panel in
            panel.title = L("Install AddOns")
            panel.message = L("Choose AddOn ZIP archives or folders")
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = true
            panel.allowedContentTypes = [.zip, .folder]
        }) { panel in
            guard !panel.urls.isEmpty else { return }
            self.install(urls: panel.urls)
        }
    }

    func install(urls: [URL]) {
        busy = true
        DispatchQueue.global().async {
            let fm = FileManager.default
            try? fm.createDirectory(atPath: Paths.addons, withIntermediateDirectories: true)
            var installed: [String] = []
            var tempDirs: [URL] = []
            for url in urls {
                var roots: [URL] = []
                if url.pathExtension.lowercased() == "zip" {
                    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
                    tempDirs.append(tmp)
                    _ = shell("/usr/bin/ditto", ["-xk", url.path, tmp.path])
                    roots = self.addonRoots(tmp)
                } else {
                    roots = self.addonRoots(url)
                }
                for root in roots {
                    let dest = URL(fileURLWithPath: Paths.addons).appendingPathComponent(root.lastPathComponent)
                    try? fm.removeItem(at: dest)
                    do {
                        try fm.copyItem(at: root, to: dest)
                        installed.append(root.lastPathComponent)
                    } catch {
                        DispatchQueue.main.async { self.note = LF("Failed to install %@: %@", root.lastPathComponent, error.localizedDescription) }
                    }
                }
            }
            for t in tempDirs { try? fm.removeItem(at: t) }
            DispatchQueue.main.async {
                self.busy = false
                self.note = installed.isEmpty
                    ? "No AddOn found — the selection contains no .toc file."
                    : "Installed: \(installed.joined(separator: ", "))"
                self.refreshAddons()
            }
        }
    }

    func remove(folder: String) {
        let url = URL(fileURLWithPath: Paths.addons + "/" + folder)
        NSWorkspace.shared.recycle([url]) { _, _ in
            DispatchQueue.main.async { self.refreshAddons() }
        }
    }

    func reveal(folder: String?) {
        let path = folder.map { Paths.addons + "/" + $0 } ?? Paths.addons
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

// MARK: - Views

/// View-local state — use this, never `@State`. The macOS 27 SDK turned
/// `@State` into a macro whose plugin ships only with Xcode, so with the bare
/// Command Line Tools (all this project needs) every `@State` fails to expand.
/// Wrapping a plain `State` stored property keeps SwiftUI's storage and
/// compiles against SDK 27 and earlier. `make test` rejects `@State` in main.swift.
@propertyWrapper struct ViewState<Value>: DynamicProperty {
    private let storage: State<Value>
    init(wrappedValue: Value) { storage = State(initialValue: wrappedValue) }
    var wrappedValue: Value {
        get { storage.wrappedValue }
        nonmutating set { storage.wrappedValue = newValue }
    }
    var projectedValue: Binding<Value> { storage.projectedValue }
}

enum Pane: String, CaseIterable, Identifiable {
    case play = "Play", game = "Game", addons = "AddOns", display = "Display", audio = "Audio", about = "About"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .play: return "play.circle"
        case .game: return "gamecontroller"
        case .addons: return "puzzlepiece.extension"
        case .display: return "display"
        case .audio: return "speaker.wave.2"
        case .about: return "info.circle"
        }
    }
}

// A running install: the copy's bar (a spinner for steps with no measurable
// progress) and the line saying what it is doing — on both panes that install.
struct InstallProgressView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(spacing: 4) {
            if let v = store.installProgress {
                ProgressView(value: v).frame(width: 260)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(verbatim: store.installStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 380)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: Store
    @ViewState private var pane: Pane? = .play

    private func needsGame(_ p: Pane) -> Bool {
        store.games.isEmpty && (p == .addons || p == .display || p == .audio)
    }

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { p in
                Label(LocalizedStringKey(p.rawValue), systemImage: p.icon)
                    .tag(p)
                    .selectionDisabled(needsGame(p))
                    .foregroundStyle(needsGame(p) ? Color.secondary.opacity(0.5) : Color.primary)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch pane ?? .play {
            case .play: PlayView()
            case .game: GameView()
            case .addons: AddOnsView()
            case .display: DisplayView()
            case .audio: AudioView()
            case .about: AboutView()
            }
        }
        .frame(minWidth: 680, minHeight: 440)
        .sheet(isPresented: $store.verifySheet) {
            VerifySheet().environmentObject(store)
        }
        .onChange(of: store.games.isEmpty) { _, empty in
            if empty, pane == .addons || pane == .display || pane == .audio { pane = .play }
        }
    }
}

struct PlayView: View {
    @EnvironmentObject var store: Store
    @ViewState private var confirmStop = false

    var closeOnPlayBinding: Binding<Bool> {
        Binding(get: { store.closeOnPlay }, set: { store.setCloseOnPlay($0) })
    }

    var statusLine: String {
        if store.games.isEmpty { return L("No game installed") }
        if store.loadingStatus { return L("Loading settings…") }
        let m: String
        switch store.mode {
        case "fullscreen": m = L("Fullscreen")
        case "windowed": m = L("Windowed")
        default: m = L("Maximized window")
        }
        return "\(m) · \(store.resolution) · \(store.retina ? L("Retina on") : L("Retina off"))"
    }

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 110, height: 110)
            Text(store.gameVersion.isEmpty ? "World of Warcraft" : "World of Warcraft \(store.gameVersion)")
                .font(.title2).bold()
            if store.rosettaMissing {
                VStack(spacing: 4) {
                    Label("Rosetta 2 is not installed — the game cannot start", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(verbatim: "sudo softwareupdate --install-rosetta --agree-to-license")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                Text(statusLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if !store.games.isEmpty {
                    Button(action: { store.detectNow() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(store.busy || store.loadingStatus)
                    .help("Detect the main screen and apply its resolution")
                }
            }
            if store.games.isEmpty {
                Button(action: { store.installGameFromPanel() }) {
                    Label("Install", systemImage: "square.and.arrow.down")
                        .frame(minWidth: 130)
                        .font(.title3)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(store.busy)
                .padding(.top, 8)
                Button("Install from Previous App…") { store.installFromAppPanel() }
                    .buttonStyle(.link)
                    .disabled(store.busy)
                    .help("Take the game from an older copy of this app — already patched, only copied and verified")
                if store.busy && !store.installStatus.isEmpty {
                    InstallProgressView().padding(.top, 4)
                } else if store.busy {
                    ProgressView().controlSize(.small).padding(.top, 4)
                }
                if !store.note.isEmpty {
                    Text(store.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }
            } else if store.gameRunning {
                HStack(spacing: 6) {
                    Label("The game is running", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Button("Stop") { confirmStop = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                    .disabled(store.busy)
                    .help("Force-stop the game")
                    .confirmationDialog("Force-stop World of Warcraft?", isPresented: $confirmStop) {
                        Button("Force Stop", role: .destructive) { store.forceStop() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("The game will be terminated immediately. Unsaved progress since the last world save may be lost.")
                    }
                }
                .padding(.top, 8)
            } else {
                Button(action: { store.play() }) {
                    Label("Play", systemImage: "play.fill")
                        .frame(minWidth: 130)
                        .font(.title3)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(store.busy)
                .padding(.top, 8)
            }
            if !store.games.isEmpty {
                Toggle("Close the launcher when the game starts", isOn: closeOnPlayBinding)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .foregroundStyle(.secondary)
                    .help("Closes the launcher once the game is in front. While the game runs it only leaves the screen, so a server on your local network stays connected; it quits when you exit the game.")
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { store.checkRunning() }
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            store.checkRunning()
        }
        // Rosetta gets installed in Terminal, then the user comes back here:
        // re-probe then, so the warning does not outlive the problem.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.checkRosetta()
        }
    }
}

struct GameView: View {
    @EnvironmentObject var store: Store
    @ViewState private var newRealm = ""

    var body: some View {
        Form {
            Section("Installed Game") {
                HStack {
                    Label(store.games.isEmpty ? L("No game installed")
                            : LF("Game installed: %@", store.gameVersion.isEmpty ? L("unknown version") : store.gameVersion),
                          systemImage: store.games.isEmpty ? "exclamationmark.circle" : "checkmark.circle.fill")
                        .foregroundStyle(store.games.isEmpty ? Color.orange : Color.green)
                    Spacer()
                    Button("Verify") { store.verifyGame() }
                        .disabled(store.busy || store.games.isEmpty)
                        .help("Check game files and Apple Silicon patches for integrity")
                }
                HStack {
                    Button(action: { store.installGameFromPanel() }) {
                        Label("Install New Game…", systemImage: "plus")
                    }
                    .disabled(store.busy)
                    Button("Install from Previous App…") { store.installFromAppPanel() }
                        .disabled(store.busy)
                        .help("Take the game from an older copy of this app — already patched, only copied and verified")
                    if store.busy && store.installStatus.isEmpty { ProgressView().controlSize(.small) }
                }
                if store.busy && !store.installStatus.isEmpty {
                    InstallProgressView()
                }
                Text("Choose any WoW client folder — it is copied into the app and gets the Apple Silicon patches that apply to it. 3.3.5a, 2.4.3 and 1.12 clients get the full treatment.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Patches") {
                if store.patchLevels == ["none"] {
                    Label("Nothing to choose — no launcher patch applies to this client, so it runs exactly as it shipped.",
                          systemImage: "info.circle")
                } else {
                    Picker("Applied to the client", selection: Binding(
                        get: { store.patches },
                        set: { store.setPatches($0) })) {
                        ForEach(store.patchLevels, id: \.self) { level in
                            Text(store.patchLevelLabel(level)).tag(level)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(store.busy || store.verifyRunning)
                    Text(store.patchesDescription + " " + L("Applies at the next game start."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !store.patchLimitNote.isEmpty {
                    Text(store.patchLimitNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if store.supportsLanguagePacks {
                Section("Language") {
                    HStack {
                        Picker("Game language", selection: Binding(
                            get: { store.activeLanguage },
                            set: { store.setLanguage($0) })) {
                            ForEach(store.languages, id: \.self) { l in
                                Text(l).tag(l)
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(store.busy || store.languages.count < 2)
                        Button(action: { store.importLanguagePackFromPanel() }) {
                            Label("Import Language Pack…", systemImage: "globe")
                        }
                        .disabled(store.busy)
                        .help("Import the language pack from a \(store.gameVersion) client in another language")
                    }
                    Text("A pack is the client's language data plus its matching game executable. Switching swaps them, clears the cache and takes effect at the next game start. To add a language, select a full \(store.gameVersion) game client in that language — only its language pack is imported, the rest is not copied.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Server") {
                ForEach(store.realms) { r in
                    HStack(spacing: 8) {
                        Image(systemName: r.active ? "circle.inset.filled" : "circle")
                            .foregroundStyle(r.active ? Color.accentColor : Color.secondary)
                        Text(r.addr)
                        Spacer()
                        if r.active {
                            Text("Active").font(.caption).foregroundStyle(.secondary)
                        }
                        Button(action: { store.removeRealm(r.addr) }) {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Remove this server")
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { store.selectRealm(r.addr) }
                    .contextMenu {
                        Button("Select") { store.selectRealm(r.addr) }
                        Button("Remove", role: .destructive) { store.removeRealm(r.addr) }
                    }
                }
                HStack {
                    TextField("logon.example.com", text: $newRealm)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { store.addRealm(newRealm); newRealm = "" }
                    Button("Add") { store.addRealm(newRealm); newRealm = "" }
                        .disabled(newRealm.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                HStack(spacing: 8) {
                    Button("Test Connection") { store.testRealmConnection() }
                        .disabled(store.realmTestRunning || store.busy || !store.realms.contains(where: { $0.active }))
                        .help("Connects to the selected server once. For a server on your local network, this makes macOS ask for local network access.")
                    if store.realmTestRunning {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                }
                if let passed = store.realmTestPassed {
                    Label(store.realmTestResult,
                          systemImage: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(passed ? Color.green : Color.red)
                } else if !store.realmTestResult.isEmpty {
                    Text(store.realmTestResult)   // "Waiting for macOS…" — not a verdict yet
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("The selected server is written to realmlist.wtf; the others stay as commented lines. Takes effect at the next game start.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(store.games.isEmpty)
            .opacity(store.games.isEmpty ? 0.5 : 1)
            if !store.note.isEmpty {
                Section {
                    Text(store.note).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            store.refreshGames()
            store.refreshRealms()
        }
    }
}

struct VerifySheet: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Game Verification")
                .font(.headline)
            ScrollViewReader { proxy in
                List(store.verifyItems) { item in
                    HStack(spacing: 8) {
                        switch item.status {
                        case .ok:
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        case .fail:
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        case .warn:
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                        Text(item.name).font(.callout)
                    }
                    .id(item.id)
                }
                .onChange(of: store.verifyItems.count) { _, _ in
                    if let last = store.verifyItems.last { proxy.scrollTo(last.id) }
                }
            }
            if store.verifyRunning {
                ProgressView(value: store.verifyProgress)
                Text(store.verifyCurrent.isEmpty ? "Checking…" : "Checking \(store.verifyCurrent)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !store.verifyResult.isEmpty {
                Label(store.verifyResult,
                      systemImage: store.verifyResult.hasPrefix("OK") ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(store.verifyResult.hasPrefix("OK") ? Color.green : Color.red)
                    .font(.callout).bold()
            }
            if store.rosettaMissing {
                Text("Rosetta 2 is not installed, so the settings kept in the wine prefix could not be checked.")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            if !store.verifyRunning && store.verifyNeedsReinstall {
                Text("The game data itself is damaged and cannot be repaired in place — reinstall the game from a client folder.")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                if store.verifyRunning {
                    Button("Cancel") { store.cancelVerify() }
                } else {
                    if store.verifyNeedsReinstall {
                        Button("Reinstall Game…") {
                            store.verifySheet = false
                            store.installGameFromPanel()
                        }
                        .buttonStyle(.borderedProminent)
                    } else if store.verifyCanFix {
                        Button("Fix Issues") { store.verifyGame(fix: true) }
                            .buttonStyle(.borderedProminent)
                    }
                    Button("Close") { store.verifySheet = false }
                        .keyboardShortcut(store.verifyCanFix || store.verifyNeedsReinstall ? .cancelAction : .defaultAction)
                }
            }
        }
        .padding(16)
        .frame(width: 480, height: 460)
    }
}

struct AddOnsView: View {
    @EnvironmentObject var store: Store
    @ViewState private var selection: String?

    var body: some View {
        Group {
            if store.addons.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No AddOns installed").font(.title3).foregroundStyle(.secondary)
                    Text("Click Install and choose a ZIP archive or folder.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(store.addons) { a in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.title)
                            Text(a.folder + (a.version.isEmpty ? "" : "  ·  v\(a.version)"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .tag(a.folder)
                        .contextMenu {
                            Button("Reveal in Finder") { store.reveal(folder: a.folder) }
                            Button("Move to Trash", role: .destructive) { store.remove(folder: a.folder) }
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button(action: { store.installFromPanel() }) {
                    Label("Install", systemImage: "plus")
                }
                .help("Install AddOns from a ZIP archive or folder")
                Button(action: {
                    if let sel = selection { store.remove(folder: sel); selection = nil }
                }) {
                    Label("Remove", systemImage: "minus")
                }
                .disabled(selection == nil)
                .help("Move the selected AddOn to the Trash")
                Button(action: { store.reveal(folder: nil) }) {
                    Label("Show in Finder", systemImage: "folder")
                }
                .help("Open the AddOns folder in Finder")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !store.note.isEmpty {
                Text(store.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.bar)
            }
        }
        .onAppear { store.refreshAddons() }
    }
}

struct DisplayView: View {
    @EnvironmentObject var store: Store

    var modeBinding: Binding<String> {
        Binding(get: { store.mode }, set: { store.setMode($0) })
    }
    var autoBinding: Binding<Bool> {
        Binding(get: { store.autoRes }, set: { store.setAuto($0) })
    }
    var retinaBinding: Binding<Bool> {
        Binding(get: { store.retina }, set: { store.setRetina($0) })
    }
    var displayBinding: Binding<Int> {
        Binding(get: { store.selectedDisplay }, set: { store.applyDisplay($0) })
    }
    var sizeBinding: Binding<String> {
        Binding(get: { store.windowPoints }, set: { store.setWindowSize($0) })
    }
    var rendererBinding: Binding<String> {
        Binding(get: { store.renderer }, set: { store.setRenderer($0) })
    }

    // Standard sizes that fit on the chosen display (window size is in points).
    var fittingSizes: [String] {
        guard let d = store.displays.first(where: { $0.id == store.selectedDisplay })
        else { return Store.windowSizes }
        return Store.windowSizes.filter {
            let p = $0.split(separator: "x").compactMap { Int($0) }
            return p.count == 2 && p[0] <= d.ptsW && p[1] <= d.ptsH
        }
    }

    var body: some View {
        Form {
            Section("Window") {
                Picker("Mode", selection: modeBinding) {
                    Text("Maximized window").tag("maximized")
                    Text("Windowed").tag("windowed")
                    Text("Fullscreen").tag("fullscreen")
                }
                .pickerStyle(.menu)
                if store.mode == "windowed" {
                    Picker("Window size", selection: sizeBinding) {
                        ForEach(fittingSizes, id: \.self) { s in
                            Text(s.replacingOccurrences(of: "x", with: " × ")).tag(s)
                        }
                        if !fittingSizes.contains(store.windowPoints) {
                            Text("Custom (\(store.windowPoints))").tag(store.windowPoints)
                        }
                    }
                    .pickerStyle(.menu)
                    Text("Choosing a size turns off automatic resolution matching. On a Retina display the game renders at 2× the window size.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Resolution") {
                Toggle("Match the main display automatically at launch", isOn: autoBinding)
                Picker("Show game on", selection: displayBinding) {
                    ForEach(store.displays) { d in
                        Text(d.label).tag(d.id)
                    }
                }
                .pickerStyle(.menu)
                if let d = store.displays.first(where: { $0.id == store.selectedDisplay }), !d.isMain {
                    Text("The game always opens on the main display; it is then moved to \(d.name) automatically. This needs a one-time Accessibility permission for WoW Launcher (System Settings → Privacy & Security → Accessibility).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(action: { store.detectNow() }) {
                    Label("Detect Main Screen Resolution", systemImage: "wand.and.stars")
                }
                .disabled(store.busy)
                .help("Detect the main screen and apply its resolution now")
                Toggle("Retina (render at native pixels)", isOn: retinaBinding)
                // the busy spinner sits where its result lands; in the toolbar,
                // macOS 26+ draws every item in a glass capsule, like a button
                LabeledContent("Game resolution") {
                    HStack(spacing: 6) {
                        if store.busy { ProgressView().controlSize(.small) }
                        Text(verbatim: store.loadingStatus ? "…" : store.resolution)
                    }
                }
            }
            Section("Renderer") {
                Picker("Graphics backend", selection: rendererBinding) {
                    Text("DXVK (default)").tag("dxvk")
                    Text("MTLd3D (Metal, HDR)").tag("mtld3d")
                }
                .pickerStyle(.menu)
                Text("Takes effect at the next game start. DXVK translates Direct3D 9 via Vulkan and is the proven default; MTLd3D renders directly through Metal and can output HDR.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !store.note.isEmpty {
                Section {
                    Text(store.note).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            store.refreshDisplays()
            store.refreshStatus()
        }
    }
}

struct AudioView: View {
    @EnvironmentObject var store: Store

    var spatialBinding: Binding<Bool> {
        Binding(get: { store.spatialAudio }, set: { store.setSpatialAudio($0) })
    }
    var normalizeBinding: Binding<Bool> {
        Binding(get: { store.normalizeAudio }, set: { store.setNormalizeAudio($0) })
    }

    var body: some View {
        Form {
            Section("Output") {
                Toggle("Spatial audio (headphones)", isOn: spatialBinding)
                Toggle("Normalize volume", isOn: normalizeBinding)
                Text("Takes effect at the next game start. Spatial audio renders through Apple's spatial mixer for a wider headphone soundscape; Normalize volume brings quiet sounds up and loud sounds down. Sound always follows the macOS output device — AirPods can be connected or removed while the game runs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !store.note.isEmpty {
                Section {
                    Text(store.note).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("WoW Launcher")
                .font(.title2).bold()
            Text("Version \(version)")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Classic-era World of Warcraft on Apple Silicon — self-contained and fast.")
                .font(.callout)
                .multilineTextAlignment(.center)
            HStack(spacing: 18) {
                Link("GitHub", destination: URL(string: "https://github.com/matasarei/wow-launcher")!)
                Link("How it was built", destination: URL(string: "https://hcnotes.cc/article/articles-my-own-private-azeroth")!)
                Link("Third-party components", destination: URL(string: "https://github.com/matasarei/wow-launcher/blob/main/docs/THIRD-PARTY.md")!)
            }
            .font(.callout)
            .padding(.top, 4)
            Spacer()
            VStack(spacing: 4) {
                Text("MIT License · © 2026 Yevhen Matasar")
                Text("Built on WoWSilicon, WineAndAqua Wine, DXVK, MTLd3D, rosettax87 and MoltenVK.")
                Text("Not affiliated with Blizzard Entertainment. World of Warcraft is a trademark of Blizzard Entertainment, Inc.")
                    .multilineTextAlignment(.center)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - App

// Quitting while the game runs is deferred (see Store.deferQuitWhileGameRuns);
// clicking the app meanwhile (Finder, Launchpad, Spotlight) arrives as a
// reopen — the way back to the window and Stop.
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: Store?
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        store?.showAgain()
        return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Logout, restart and shutdown carry a quit reason: never hold those up.
        if NSAppleEventManager.shared().currentAppleEvent?
            .attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason)) != nil { return .terminateNow }
        return store?.deferQuitWhileGameRuns() == true ? .terminateCancel : .terminateNow
    }
}

@main
struct WoWLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = Store()

    var body: some Scene {
        Window("WoW Launcher", id: "main") {
            ContentView().environmentObject(store)
                .onAppear { appDelegate.store = store }
        }
        .defaultSize(width: 780, height: 500)
    }
}
