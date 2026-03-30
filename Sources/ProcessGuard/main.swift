import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
statusItem.button?.title = "PG"
if let img = NSImage(systemSymbolName: "gauge.medium", accessibilityDescription: "ProcessGuard") {
    img.isTemplate = true
    statusItem.button?.image = img
    statusItem.button?.imagePosition = .imageLeading
}

// MARK: - Shell execution via posix_spawn (avoids Foundation.Process run loop issues)

func shell(_ command: String) -> String {
    var readFD: Int32 = 0, writeFD: Int32 = 0
    var fds = [Int32](repeating: 0, count: 2)
    guard Darwin.pipe(&fds) == 0 else { return "" }
    readFD = fds[0]; writeFD = fds[1]

    var fileActions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&fileActions)
    posix_spawn_file_actions_adddup2(&fileActions, writeFD, STDOUT_FILENO)
    posix_spawn_file_actions_addclose(&fileActions, readFD)
    posix_spawn_file_actions_addclose(&fileActions, writeFD)

    let args: [String] = ["/bin/sh", "-c", command]
    let cArgs = args.map { strdup($0) } + [nil]
    defer { cArgs.forEach { if let p = $0 { free(p) } } }

    var childPid: pid_t = 0
    let result = posix_spawn(&childPid, "/bin/sh", &fileActions, nil, cArgs, nil)
    posix_spawn_file_actions_destroy(&fileActions)
    close(writeFD)

    guard result == 0 else { close(readFD); return "" }

    var output = Data()
    var buf = [UInt8](repeating: 0, count: 4096)
    while true {
        let n = read(readFD, &buf, buf.count)
        if n <= 0 { break }
        output.append(contentsOf: buf[0..<n])
    }
    close(readFD)
    waitpid(childPid, nil, 0)

    return String(data: output, encoding: .utf8) ?? ""
}

// MARK: - Data types

struct ProcInfo {
    let pid: Int32
    let cpu: Double
    let mem: Double
    let name: String
    let elapsed: String

    var displayName: String {
        let base = URL(fileURLWithPath: name).lastPathComponent
        if base.hasSuffix(" (Renderer)") { return base.replacingOccurrences(of: " (Renderer)", with: "") }
        return base
    }
}

struct EnergyInfo {
    let pid: Int32
    let power: Double
    let name: String
}

// MARK: - Guard

class Guard: NSObject {
    var cpuProcs: [ProcInfo] = []
    var energyProcs: [EnergyInfo] = []

    func scanCPU() -> [ProcInfo] {
        let out = shell("/bin/ps -eo pid,pcpu,pmem,etime,comm -r")
        var r: [ProcInfo] = []
        for line in out.components(separatedBy: "\n").dropFirst() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            let p = t.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard p.count >= 5, let pid = Int32(p[0]), let cpu = Double(p[1]), let mem = Double(p[2]) else { continue }
            if pid == 0 || String(p[4]).contains("ProcessGuard") { continue }
            r.append(ProcInfo(pid: pid, cpu: cpu, mem: mem, name: String(p[4]), elapsed: String(p[3])))
            if r.count >= 10 { break }
        }
        return r
    }

    func scanEnergy() -> [EnergyInfo] {
        // top -l 2 gives a real second sample with actual power data
        let out = shell("/usr/bin/top -l 2 -stats pid,power,command -n 10 2>/dev/null | tail -12")
        var r: [EnergyInfo] = []
        for line in out.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("PID") { continue }
            let p = t.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard p.count >= 3, let pid = Int32(p[0]), let power = Double(p[1]) else { continue }
            if pid == 0 || power < 0.1 { continue }
            let name = URL(fileURLWithPath: String(p[2])).lastPathComponent
            r.append(EnergyInfo(pid: pid, power: power, name: name))
            if r.count >= 5 { break }
        }
        return r
    }

    @objc func refresh() {
        cpuProcs = scanCPU()
        energyProcs = scanEnergy()
        buildMenu()
    }

    func buildMenu() {
        let menu = NSMenu()

        let h = NSMenuItem(title: "Top Processes by CPU", action: nil, keyEquivalent: "")
        h.isEnabled = false
        menu.addItem(h)

        let ts = NSMenuItem(title: "Last scan: \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short))", action: nil, keyEquivalent: "")
        ts.isEnabled = false
        menu.addItem(ts)
        menu.addItem(NSMenuItem.separator())

        for (i, p) in cpuProcs.enumerated() {
            let c = p.cpu > 50 ? "\u{1F534}" : (p.cpu > 20 ? "\u{1F7E1}" : "\u{1F7E2}")
            let item = NSMenuItem(title: "\(c) \(String(format:"%5.1f",p.cpu))%  \(p.displayName)  (\(p.pid))", action: nil, keyEquivalent: "")

            let sub = NSMenu()
            let info = NSMenuItem(title: "CPU: \(String(format:"%.1f",p.cpu))%  |  MEM: \(String(format:"%.1f",p.mem))%  |  Up: \(p.elapsed)", action: nil, keyEquivalent: "")
            info.isEnabled = false
            sub.addItem(info)
            sub.addItem(NSMenuItem.separator())

            let k = NSMenuItem(title: "Kill Process", action: #selector(doKill(_:)), keyEquivalent: "")
            k.target = self; k.tag = i; sub.addItem(k)

            let inv = NSMenuItem(title: "Investigate with Claude", action: #selector(doInvestigate(_:)), keyEquivalent: "")
            inv.target = self; inv.tag = i; sub.addItem(inv)

            item.submenu = sub
            menu.addItem(item)
        }

        // Energy drainers section
        if !energyProcs.isEmpty {
            menu.addItem(NSMenuItem.separator())
            let eh = NSMenuItem(title: "Top Energy Drainers", action: nil, keyEquivalent: "")
            eh.isEnabled = false
            menu.addItem(eh)
            menu.addItem(NSMenuItem.separator())

            for ep in energyProcs {
                let c = ep.power > 20 ? "\u{1F50B}" : (ep.power > 5 ? "\u{1FAA7}" : "\u{1F7E9}")
                let item = NSMenuItem(title: "\(c) \(String(format:"%5.1f",ep.power))  \(ep.name)  (\(ep.pid))", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())
        let ref = NSMenuItem(title: "Refresh Now", action: #selector(refresh), keyEquivalent: "r")
        ref.target = self; menu.addItem(ref)
        menu.addItem(NSMenuItem(title: "Quit ProcessGuard", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.title = cpuProcs.contains(where: { $0.cpu > 50 }) ? "\u{26A0} PG" : "PG"
    }

    @objc func doKill(_ sender: NSMenuItem) {
        guard sender.tag < cpuProcs.count else { return }
        let p = cpuProcs[sender.tag]

        let alert = NSAlert()
        alert.messageText = "Kill \(p.displayName)?"
        alert.informativeText = """
            PID: \(p.pid)
            CPU: \(String(format:"%.1f",p.cpu))%
            Memory: \(String(format:"%.1f",p.mem))%
            Uptime: \(p.elapsed)

            Are you sure you want to terminate this process?
            """
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Kill")

        // Cancel is the default (first) button — user must explicitly click Kill
        if alert.runModal() == .alertSecondButtonReturn {
            kill(p.pid, SIGTERM)
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { kill(p.pid, SIGKILL) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.refresh() }
        }
    }

    @objc func doInvestigate(_ sender: NSMenuItem) {
        guard sender.tag < cpuProcs.count else { return }
        let p = cpuProcs[sender.tag]
        let prompt = "Investigate process \(p.displayName) (PID \(p.pid)) using \(String(format:"%.1f",p.cpu))% CPU and \(String(format:"%.1f",p.mem))% memory, running for \(p.elapsed). Determine if it is safe to kill and why it is using so much CPU."
        let safe = prompt.replacingOccurrences(of: "\"", with: "\\\"")
        let scr = "tell application \"Terminal\"\nactivate\ndo script \"claude \\\"" + safe + "\\\"\"\nend tell"
        let t = Process()
        t.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        t.arguments = ["-e", scr]
        t.standardOutput = Pipe(); t.standardError = Pipe()
        try? t.run()
    }
}

let guard_ = Guard()
guard_.refresh()

Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { _ in guard_.refresh() }

app.run()
