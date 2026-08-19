import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
        let folder = activeGame.isEmpty ? "game" : activeGame
        return NSRegularExpression.escapedPattern(for: folder) + "[/\\\\]Wow\\.exe"
    }
    static let installTool = resources + "/bin/wow-install-client"
    static let verifyTool  = resources + "/bin/wow-verify-game"
    static let settings  = resources + "/bin/wow-settings"
    static let launcher  = resources + "/bin/wow-launch"
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
    @Published var resolution = "…"
    @Published var retina = false
    @Published var autoRes = true
    @Published var addons: [AddOn] = []
    @Published var displays: [DisplayOption] = []
    @Published var selectedDisplay = 0
    @Published var games: [String] = []
    @Published var activeGame = ""
    @Published var gameRunning = false
    @Published var loadingStatus = true
    @Published var busy = false
    @Published var note = ""

    init() {
        autoRes = !((try? String(contentsOfFile: Paths.conf, encoding: .utf8))?.contains("AUTO_RES=0") ?? false)
        let r = confGet("RENDERER")
        if !r.isEmpty { renderer = r }
        refreshDisplays()
        refreshGames()
        refreshRealms()
        refreshAddons()
        refreshStatus()
        checkRunning()
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
        resolveDisplayRect()
        DispatchQueue.global().async {
            _ = shell(Paths.launcher)
            DispatchQueue.main.async {
                self.gameRunning = true
                self.busy = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { NSApp.terminate(nil) }
            }
        }
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
        note = "Renderer set to \(r == "mtld3d" ? "MTLd3D" : "DXVK") — takes effect at the next game start."
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

    func detectNow() {
        busy = true
        DispatchQueue.global().async {
            let out = shell(Paths.settings, ["auto"])
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
                    "The game window will be moved to \(d.name) shortly after launch."
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
            .filter { fm.fileExists(atPath: Paths.gamesDir + "/" + $0 + "/Wow.exe") }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        games = dirs
        activeGame = Paths.activeGame
        if activeGame.isEmpty || !dirs.contains(activeGame), let first = dirs.first {
            confSet("GAME", first)
            activeGame = first
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
                    self?.verifyResult = "Verification stopped."
                }
            }
        }
        verifyProc = p
        do { try p.run() } catch {
            verifyRunning = false
            verifyResult = "Could not start verification: \(error.localizedDescription)"
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
        } else if line.hasPrefix("RESULT: ") {
            verifyResult = String(line.dropFirst(8))
            verifyProgress = 1
            verifyCurrent = ""
        }
    }

    func installGameFromPanel() {
        let panel = NSOpenPanel()
        panel.title = "Install Game Client"
        panel.message = "Choose a WoW 3.3.5a client folder (contains Wow.exe and Data)"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            self.installGame(from: url)
        }
    }

    func installGame(from url: URL) {
        busy = true
        note = "Installing \(url.lastPathComponent)… copying the client can take a few minutes."
        DispatchQueue.global().async {
            let out = shell(Paths.installTool, [url.path])
            DispatchQueue.main.async {
                self.busy = false
                self.note = out.split(separator: "\n").suffix(2).joined(separator: " — ")
                self.refreshGames()
                self.refreshStatus()
                self.refreshRealms()
                self.refreshAddons()
            }
        }
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
        realms = list
    }

    private func writeRealms(_ list: [Realm]) {
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
        guard !a.isEmpty, !a.contains(" ") else { note = "Invalid server address."; return }
        guard !realms.contains(where: { $0.addr == a }) else { selectRealm(a); return }
        writeRealms(realms.map { Realm(addr: $0.addr, active: false) } + [Realm(addr: a, active: true)])
        note = "Server \(a) added and selected — takes effect at next game start."
    }

    func removeRealm(_ addr: String) {
        var rest = realms.filter { $0.addr != addr }
        guard !rest.isEmpty else {
            note = "At least one server is required — add another before removing this one."
            return
        }
        if !rest.contains(where: { $0.active }) {
            rest[0] = Realm(addr: rest[0].addr, active: true)
        }
        writeRealms(rest)
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
        let panel = NSOpenPanel()
        panel.title = "Install AddOns"
        panel.message = "Choose AddOn ZIP archives or folders"
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.zip, .folder]
        panel.begin { resp in
            guard resp == .OK, !panel.urls.isEmpty else { return }
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
                        DispatchQueue.main.async { self.note = "Failed to install \(root.lastPathComponent): \(error.localizedDescription)" }
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

enum Pane: String, CaseIterable, Identifiable {
    case play = "Play", game = "Game", addons = "AddOns", display = "Display", about = "About"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .play: return "play.circle"
        case .game: return "gamecontroller"
        case .addons: return "puzzlepiece.extension"
        case .display: return "display"
        case .about: return "info.circle"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: Store
    @State private var pane: Pane? = .play

    private func needsGame(_ p: Pane) -> Bool {
        store.games.isEmpty && (p == .addons || p == .display)
    }

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { p in
                Label(p.rawValue, systemImage: p.icon)
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
            case .about: AboutView()
            }
        }
        .frame(minWidth: 680, minHeight: 440)
        .onChange(of: store.games.isEmpty) { _, empty in
            if empty, pane == .addons || pane == .display { pane = .play }
        }
    }
}

struct PlayView: View {
    @EnvironmentObject var store: Store
    @State private var confirmStop = false

    var statusLine: String {
        if store.games.isEmpty { return "No game installed" }
        if store.loadingStatus { return "Loading settings…" }
        let m: String
        switch store.mode {
        case "fullscreen": m = "Fullscreen"
        case "windowed": m = "Windowed"
        default: m = "Maximized window"
        }
        return "\(m) · \(store.resolution) · Retina \(store.retina ? "on" : "off")"
    }

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 110, height: 110)
            Text("World of Warcraft 3.3.5a")
                .font(.title2).bold()
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
                if store.busy {
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
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { store.checkRunning() }
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            store.checkRunning()
        }
    }
}

struct GameView: View {
    @EnvironmentObject var store: Store
    @State private var newRealm = ""

    var body: some View {
        Form {
            Section("Installed Game") {
                HStack {
                    Label(store.games.isEmpty ? "No game installed" : "Game installed",
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
                    if store.busy { ProgressView().controlSize(.small) }
                }
                Text("Choose a WoW 3.3.5a client folder — it is copied into the app and patched for Apple Silicon automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .sheet(isPresented: $store.verifySheet) {
            VerifySheet().environmentObject(store)
        }
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
    @State private var selection: String?

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
                    Text("The game always opens on the main display; it is then moved to \(d.name) automatically. This needs a one-time Accessibility permission for WoW335 (System Settings → Privacy & Security → Accessibility).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(action: { store.detectNow() }) {
                    Label("Detect Main Screen Resolution", systemImage: "wand.and.stars")
                }
                .disabled(store.busy)
                .help("Detect the main screen and apply its resolution now")
                Toggle("Retina (render at native pixels)", isOn: retinaBinding)
                LabeledContent("Game resolution", value: store.loadingStatus ? "…" : store.resolution)
            }
            Section("Renderer") {
                Picker("Graphics backend", selection: rendererBinding) {
                    Text("DXVK (default)").tag("dxvk")
                    Text("MTLd3D (HDR, experimental)").tag("mtld3d")
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
        .toolbar {
            ToolbarItem {
                if store.busy { ProgressView().controlSize(.small) }
            }
        }
        .onAppear {
            store.refreshDisplays()
            store.refreshStatus()
        }
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
            Text("WoW335 Launcher")
                .font(.title2).bold()
            Text("Version \(version)")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("World of Warcraft 3.3.5a on Apple Silicon — self-contained and fast.")
                .font(.callout)
                .multilineTextAlignment(.center)
            HStack(spacing: 18) {
                Link("GitHub", destination: URL(string: "https://github.com/matasarei/wow335-launcher")!)
                Link("How it was built", destination: URL(string: "https://hcnotes.cc/article/articles-my-own-private-azeroth")!)
                Link("Third-party components", destination: URL(string: "https://github.com/matasarei/wow335-launcher/blob/main/docs/THIRD-PARTY.md")!)
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

@main
struct WoW335App: App {
    @StateObject private var store = Store()

    var body: some Scene {
        Window("World of Warcraft 3.3.5a", id: "main") {
            ContentView().environmentObject(store)
        }
        .defaultSize(width: 780, height: 500)
    }
}
