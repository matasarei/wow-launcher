import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Paths inside the bundle

enum Paths {
    static let contents  = Bundle.main.bundlePath + "/Contents"
    static let resources = contents + "/Resources"
    static let macOS     = contents + "/MacOS"
    static let game      = resources + "/game"
    static let addons    = game + "/Interface/AddOns"
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
    let isMain: Bool
    var isRetina: Bool { pxW != ptsW }
    var label: String { "\(name)\(isMain ? " (main)" : "") — \(pxW) × \(pxH)" }
}

// MARK: - Store

final class Store: ObservableObject {
    @Published var mode = "maximized"
    @Published var resolution = "…"
    @Published var retina = false
    @Published var autoRes = true
    @Published var addons: [AddOn] = []
    @Published var displays: [DisplayOption] = []
    @Published var selectedDisplay = 0
    @Published var gameRunning = false
    @Published var loadingStatus = true
    @Published var busy = false
    @Published var note = ""

    init() {
        autoRes = !((try? String(contentsOfFile: Paths.conf, encoding: .utf8))?.contains("AUTO_RES=0") ?? false)
        refreshDisplays()
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
        DispatchQueue.global().async {
            let out = shell("/usr/bin/pgrep", ["-f", "Wow.exe"])
            let running = !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !out.hasPrefix("ERROR")
            DispatchQueue.main.async { self.gameRunning = running }
        }
    }

    // MARK: actions

    func play() {
        busy = true
        DispatchQueue.global().async {
            _ = shell(Paths.launcher)
            DispatchQueue.main.async {
                self.gameRunning = true
                self.busy = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { NSApp.terminate(nil) }
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
        retina = on
        busy = true
        let auto = autoRes
        let disp = displays.first(where: { $0.id == selectedDisplay })
        DispatchQueue.global().async {
            _ = shell(Paths.settings, ["retina", on ? "on" : "off"])
            if auto {
                _ = shell(Paths.settings, ["auto"])
            } else if let d = disp {
                let target = on ? "\(d.pxW)x\(d.pxH)" : "\(d.ptsW)x\(d.ptsH)"
                _ = shell(Paths.settings, ["resolution", target])
            }
            DispatchQueue.main.async { self.busy = false; self.refreshStatus() }
        }
    }

    func setAuto(_ v: Bool) {
        autoRes = v
        try? "AUTO_RES=\(v ? 1 : 0)\n".write(toFile: Paths.conf, atomically: true, encoding: .utf8)
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
        DispatchQueue.global().async {
            _ = shell(Paths.settings, ["resolution", target])
            DispatchQueue.main.async {
                self.busy = false
                self.note = d.isMain ? "" :
                    "Sized for \(d.name). Drag the game window there once — macOS remembers the position."
                self.refreshStatus()
            }
        }
    }

    func refreshDisplays() {
        var opts: [DisplayOption] = []
        for (i, s) in NSScreen.screens.enumerated() {
            let pts = s.frame.size
            let scale = s.backingScaleFactor
            opts.append(DisplayOption(
                id: i,
                name: s.localizedName,
                ptsW: Int(pts.width), ptsH: Int(pts.height),
                pxW: Int(pts.width * scale), pxH: Int(pts.height * scale),
                isMain: s == NSScreen.main || i == 0 && NSScreen.main == nil
            ))
        }
        displays = opts
        if let main = opts.first(where: { $0.isMain }) { selectedDisplay = main.id }
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
                    let raw = (try? String(contentsOfFile: folderPath + "/" + toc, encoding: .utf8))
                        ?? (try? String(contentsOfFile: folderPath + "/" + toc, encoding: .isoLatin1)) ?? ""
                    for line in raw.split(separator: "\n").prefix(40) {
                        let l = line.trimmingCharacters(in: .whitespaces)
                        if l.hasPrefix("## Title:") {
                            let t = stripWoWCodes(String(l.dropFirst(9)))
                            if !t.isEmpty { title = t }
                        } else if l.hasPrefix("## Version:") {
                            version = String(l.dropFirst(11)).trimmingCharacters(in: .whitespaces)
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
    case play = "Play", addons = "AddOns", display = "Display"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .play: return "play.circle"
        case .addons: return "puzzlepiece.extension"
        case .display: return "display"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: Store
    @State private var pane: Pane? = .play

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { p in
                Label(p.rawValue, systemImage: p.icon).tag(p)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch pane ?? .play {
            case .play: PlayView()
            case .addons: AddOnsView()
            case .display: DisplayView()
            }
        }
        .frame(minWidth: 680, minHeight: 440)
    }
}

struct PlayView: View {
    @EnvironmentObject var store: Store

    var statusLine: String {
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
                Button(action: { store.detectNow() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(store.busy || store.loadingStatus)
                .help("Detect the main screen and apply its resolution")
            }
            if store.gameRunning {
                Label("The game is running", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
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

    var body: some View {
        Form {
            Section("Window") {
                Picker("Mode", selection: modeBinding) {
                    Text("Maximized window").tag("maximized")
                    Text("Windowed").tag("windowed")
                    Text("Fullscreen").tag("fullscreen")
                }
                .pickerStyle(.menu)
            }
            Section("Resolution") {
                Toggle("Match the main display automatically at launch", isOn: autoBinding)
                Picker("Size for display", selection: displayBinding) {
                    ForEach(store.displays) { d in
                        Text(d.label).tag(d.id)
                    }
                }
                .pickerStyle(.menu)
                .disabled(store.autoRes)
                Button(action: { store.detectNow() }) {
                    Label("Detect Main Screen Resolution", systemImage: "wand.and.stars")
                }
                .disabled(store.busy)
                .help("Detect the main screen and apply its resolution now")
                Toggle("Retina (render at native pixels)", isOn: retinaBinding)
                LabeledContent("Game resolution", value: store.loadingStatus ? "…" : store.resolution)
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
