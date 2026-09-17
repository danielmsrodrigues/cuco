import AppKit
import ServiceManagement
import UserNotifications

// MARK: - Preferências globais

enum Pref {
    static let reminders = "reminders"
    static let idleMinutes = "idleMinutes"
    static let showCountdown = "showCountdown"
    static let playSound = "playSound"
    static let soundName = "soundName"
    static let notifyBreakEnd = "notifyBreakEnd"
    static let openAtLogin = "openAtLogin"
    static let fullScreenBreak = "fullScreenBreak"
    static let warnSeconds = "warnSeconds"

    static func register() {
        UserDefaults.standard.register(defaults: [
            idleMinutes: 5,
            showCountdown: true,
            playSound: true,
            soundName: "Cuco",
            notifyBreakEnd: true,
            openAtLogin: false,
            fullScreenBreak: false,
            warnSeconds: 10,
        ])
    }

    static func int(_ key: String) -> Int { UserDefaults.standard.integer(forKey: key) }
    static func bool(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }
    static func string(_ key: String) -> String { UserDefaults.standard.string(forKey: key) ?? "" }
    static func set(_ value: Any, _ key: String) { UserDefaults.standard.set(value, forKey: key) }

    static let sounds = [
        "Cuco", "Predefinido", "Submarine", "Glass", "Ping", "Tink", "Pop",
        "Purr", "Bottle", "Hero", "Morse", "Sosumi", "Blow", "Funk",
    ]

    static func breakSound() -> UNNotificationSound? {
        guard bool(playSound) else { return nil }
        let name = string(soundName)
        if name.isEmpty || name == "Predefinido" { return .default }
        return UNNotificationSound(named: UNNotificationSoundName("\(name).aiff"))
    }
}

// MARK: - Etiquetas

func durationLabel(_ seconds: Int) -> String {
    if seconds < 60 { return "\(seconds) s" }
    if seconds % 60 == 0 { return "\(seconds / 60) min" }
    return String(format: "%d:%02d min", seconds / 60, seconds % 60)
}

func minutesText(_ minutes: Int) -> String {
    if minutes < 60 { return "\(minutes) min" }
    let hours = minutes / 60, rest = minutes % 60
    if rest == 0 { return hours == 1 ? "1 hora" : "\(hours) horas" }
    return String(format: "%dh%02d", hours, rest)
}

func clockLabel(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded(.up)))
    return String(format: "%d:%02d", total / 60, total % 60)
}

func secondsSinceLastInput() -> TimeInterval {
    guard let anyEvent = CGEventType(rawValue: ~UInt32(0)) else { return 0 }
    return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyEvent)
}

// MARK: - Ecrã de pausa

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Anel de progresso com o tempo que falta no meio.
final class RingView: NSView {
    private let track = CAShapeLayer()
    private let progress = CAShapeLayer()
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        let radius = min(frameRect.width, frameRect.height) / 2 - 4
        let center = CGPoint(x: frameRect.width / 2, y: frameRect.height / 2)
        let path = CGMutablePath()
        path.addArc(
            center: center, radius: radius,
            startAngle: .pi / 2, endAngle: -3 * .pi / 2, clockwise: true
        )

        track.path = path
        track.fillColor = nil
        track.lineWidth = 4
        track.strokeColor = NSColor.white.withAlphaComponent(0.12).cgColor

        progress.path = path
        progress.fillColor = nil
        progress.lineWidth = 4
        progress.lineCap = .round
        progress.strokeColor = NSColor.white.withAlphaComponent(0.85).cgColor
        progress.strokeEnd = 1

        layer?.addSublayer(track)
        layer?.addSublayer(progress)

        label.frame = NSRect(x: 0, y: frameRect.height / 2 - 45, width: frameRect.width, height: 80)
        label.alignment = .center
        label.font = .systemFont(ofSize: 64, weight: .ultraLight)
        label.textColor = .white
        addSubview(label)
    }

    required init?(coder: NSCoder) { nil }

    func update(remaining: TimeInterval, total: TimeInterval) {
        label.stringValue = clockLabel(remaining)
        CATransaction.begin()
        CATransaction.setAnimationDuration(1)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
        progress.strokeEnd = total > 0 ? max(0, min(1, remaining / total)) : 0
        CATransaction.commit()
    }
}

final class BreakOverlay: NSObject {
    private var windows: [OverlayWindow] = []
    private var rings: [RingView] = []
    private var keyMonitor: Any?
    private var total: TimeInterval = 1

    var onSkip: (() -> Void)?
    var onSnooze: (() -> Void)?

    func show(_ reminder: Reminder, total: TimeInterval) {
        hide(animated: false)
        self.total = total

        for screen in NSScreen.screens {
            let window = OverlayWindow(
                contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false
            )
            window.setFrame(screen.frame, display: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.hidesOnDeactivate = false
            window.alphaValue = 0

            let size = screen.frame.size

            // Desfoque do que está por trás, em vez de um preto chapado.
            let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
            blur.material = .fullScreenUI
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.autoresizingMask = [.width, .height]

            let dim = NSView(frame: blur.bounds)
            dim.wantsLayer = true
            dim.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
            dim.autoresizingMask = [.width, .height]
            blur.addSubview(dim)
            window.contentView = blur

            let midY = size.height / 2

            if let symbol = NSImage(
                systemSymbolName: reminder.symbol, accessibilityDescription: nil
            )?.withSymbolConfiguration(.init(pointSize: 34, weight: .ultraLight)) {
                let icon = NSImageView(frame: NSRect(x: 0, y: midY + 212, width: size.width, height: 40))
                icon.image = symbol
                icon.contentTintColor = NSColor.white.withAlphaComponent(0.7)
                icon.imageScaling = .scaleProportionallyDown
                blur.addSubview(icon)
            }

            blur.addSubview(makeLabel(
                reminder.name, size: 34, weight: .light, color: NSColor.white.withAlphaComponent(0.95),
                frame: NSRect(x: 0, y: midY + 158, width: size.width, height: 48)
            ))
            blur.addSubview(makeLabel(
                reminder.message, size: 17, weight: .regular, color: NSColor.white.withAlphaComponent(0.55),
                frame: NSRect(x: 0, y: midY + 126, width: size.width, height: 26)
            ))

            let ring = RingView(frame: NSRect(
                x: (size.width - 220) / 2, y: midY - 130, width: 220, height: 220
            ))
            ring.update(remaining: total, total: total)
            blur.addSubview(ring)
            rings.append(ring)

            let snooze = makeButton("Adiar 5 min", action: #selector(snoozePressed))
            let skip = makeButton("Saltar", action: #selector(skipPressed))
            let gap: CGFloat = 10
            let totalWidth = snooze.frame.width + gap + skip.frame.width
            snooze.setFrameOrigin(NSPoint(x: (size.width - totalWidth) / 2, y: midY - 200))
            skip.setFrameOrigin(NSPoint(x: snooze.frame.maxX + gap, y: midY - 200))
            blur.addSubview(snooze)
            blur.addSubview(skip)

            blur.addSubview(makeLabel(
                "Esc para saltar", size: 12, weight: .regular,
                color: NSColor.white.withAlphaComponent(0.3),
                frame: NSRect(x: 0, y: midY - 240, width: size.width, height: 18)
            ))

            window.orderFrontRegardless()
            windows.append(window)
        }

        // Entrar devagar, não com um estalo.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.8
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            for window in windows { window.animator().alphaValue = 1 }
        }

        windows.first?.makeKey()
        NSApp.activate(ignoringOtherApps: true)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc
                self?.onSkip?()
                return nil
            }
            return event
        }
    }

    func update(remaining: TimeInterval) {
        for ring in rings { ring.update(remaining: remaining, total: total) }
    }

    func hide(animated: Bool = true) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        rings.removeAll()

        let closing = windows
        windows.removeAll()
        guard !closing.isEmpty else { return }

        guard animated else {
            for window in closing { window.orderOut(nil) }
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.5
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            for window in closing { window.animator().alphaValue = 0 }
        } completionHandler: {
            for window in closing { window.orderOut(nil) }
        }
    }

    @objc private func skipPressed() { onSkip?() }
    @objc private func snoozePressed() { onSnooze?() }

    private func makeLabel(
        _ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, frame: NSRect
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = frame
        label.alignment = .center
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        return label
    }

    private func makeButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.isBordered = false
        button.wantsLayer = true
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.85),
        ])
        button.sizeToFit()
        button.setFrameSize(NSSize(width: max(132, button.frame.width + 32), height: 34))
        button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        button.layer?.cornerRadius = 17
        return button
    }
}

// MARK: - App

final class Controller: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private var ticker: Timer?
    private let overlay = BreakOverlay()

    private var reminders: [Reminder] = []
    private var nextDue: [String: Date] = [:]
    private var mutedUntil: Date?
    private var notificationsAllowed = false
    private var ticks = 0

    private var activeBreak: Reminder?
    private var breakEndsAt: Date?
    private var warnedFor: Date?
    private var skipFullScreenOnce = false

    private var headerItems: [NSMenuItem] = []
    private var symbolCache: [String: NSImage] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        Pref.register()
        loadReminders()
        scheduleAll()

        overlay.onSkip = { [weak self] in self?.endBreak(completed: false) }
        overlay.onSnooze = { [weak self] in
            self?.endBreak(completed: false)
            self?.snooze()
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeading
        statusItem.menu = buildMenu()
        refreshStatusItem()

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: "cuco.aviso",
                actions: [
                    UNNotificationAction(identifier: "sem_ecra", title: "Agora não, só o aviso", options: []),
                    UNNotificationAction(identifier: "adiar", title: "Adiar 5 min", options: []),
                ],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: "cuco.acoes",
                actions: [
                    UNNotificationAction(identifier: "adiar", title: "Adiar 5 min", options: []),
                    UNNotificationAction(identifier: "feito", title: "Feito", options: []),
                ],
                intentIdentifiers: [],
                options: []
            ),
        ])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in
            self.checkAuthorization(promptIfDenied: true)
        }

        syncLoginItem()

        // deliverImmediately: sem isto o App Nap engole o disparo numa app de fundo.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(testBreak),
            name: Notification.Name("net.danielrodrigues.cuco.teste"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(ticker!, forMode: .common)
    }

    // MARK: Lembretes

    private func loadReminders() {
        if let stored = UserDefaults.standard.array(forKey: Pref.reminders) as? [[String: Any]] {
            reminders = stored.compactMap(Reminder.init(dictionary:))
            if !reminders.isEmpty { return }
        }
        // Primeira vez (ou vindo de uma versão antiga): aproveitar o que já estava afinado.
        reminders = Reminder.defaults
        let store = UserDefaults.standard
        if store.object(forKey: "eyeMinutes") != nil {
            reminders[0].intervalMinutes = store.integer(forKey: "eyeMinutes")
            reminders[0].durationSeconds = store.integer(forKey: "eyeSeconds")
            reminders[0].enabled = store.object(forKey: "eyeEnabled") as? Bool ?? true
            reminders[1].intervalMinutes = store.integer(forKey: "moveMinutes")
            reminders[1].durationSeconds = store.integer(forKey: "moveBreakMinutes") * 60
            reminders[1].enabled = store.object(forKey: "moveEnabled") as? Bool ?? true
        }
        saveReminders()
    }

    private func saveReminders() {
        Pref.set(reminders.map(\.dictionary), Pref.reminders)
    }

    private func reminder(_ id: String) -> Reminder? {
        reminders.first { $0.id == id }
    }

    private func update(_ id: String, _ change: (inout Reminder) -> Void) {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        change(&reminders[index])
        saveReminders()
        rebuildMenu()
    }

    private func schedule(_ reminder: Reminder) {
        nextDue[reminder.id] = Date().addingTimeInterval(Double(reminder.intervalMinutes) * 60)
    }

    private func scheduleAll() {
        for reminder in reminders { schedule(reminder) }
    }

    private func due(_ reminder: Reminder) -> Date {
        nextDue[reminder.id] ?? Date.distantFuture
    }

    private var activeReminders: [Reminder] {
        reminders.filter(\.enabled).sorted { due($0) < due($1) }
    }

    // MARK: Ciclo

    private var isMuted: Bool {
        guard let until = mutedUntil else { return false }
        if Date() >= until { mutedUntil = nil; return false }
        return true
    }

    private func tick() {
        defer { refreshStatusItem() }

        ticks += 1
        if ticks % 15 == 0 { checkAuthorization(promptIfDenied: false) }

        let now = Date()

        // Durante a pausa só conta o tempo que falta.
        if let end = breakEndsAt {
            if now >= end {
                endBreak(completed: true)
            } else {
                overlay.update(remaining: end.timeIntervalSince(now))
            }
            return
        }

        guard !isMuted else { return }

        // Lembrete desligado não acumula atraso.
        for reminder in reminders where !reminder.enabled { schedule(reminder) }

        // Se estiveste longe do Mac, isso já foi uma pausa: recomeça a contagem.
        let idleLimit = Double(Pref.int(Pref.idleMinutes)) * 60
        if idleLimit > 0, secondsSinceLastInput() >= idleLimit {
            scheduleAll()
            return
        }

        warnIfBreakIsClose(now: now)

        // Se houver mais do que um a dever, ganha o de pausa mais longa.
        let overdue = activeReminders.filter { due($0) <= now }
        guard let winner = overdue.max(by: { $0.durationSeconds < $1.durationSeconds }) else { return }
        startBreak(winner)
    }

    /// Com o ecrã inteiro ligado, avisa uns segundos antes para a pausa não cair em cima de ti.
    private func warnIfBreakIsClose(now: Date) {
        let warning = Double(Pref.int(Pref.warnSeconds))
        guard warning > 0, Pref.bool(Pref.fullScreenBreak) else { return }
        guard let next = activeReminders.first else { return }
        let target = due(next)
        guard target > now, target.timeIntervalSince(now) <= warning, warnedFor != target else { return }
        warnedFor = target

        let content = UNMutableNotificationContent()
        content.title = "\(next.name) daqui a \(Int(target.timeIntervalSince(now).rounded())) s"
        content.body = "Vai passar a ecrã inteiro. Se estiveres a meio de alguma coisa, adia ou fica só com o aviso."
        content.categoryIdentifier = "cuco.aviso"
        content.sound = Pref.breakSound()
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "cuco.aviso", content: content, trigger: nil)
        )
    }

    private func startBreak(_ reminder: Reminder) {
        activeBreak = reminder
        breakEndsAt = Date().addingTimeInterval(reminder.duration)

        // Uma pausa longa serve também as curtas: não vale a pena encadeá-las.
        for other in reminders where other.durationSeconds <= reminder.durationSeconds {
            schedule(other)
        }

        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [
            reminder.notificationID, reminder.notificationID + ".fim", "cuco.aviso",
        ])

        let content = UNMutableNotificationContent()
        content.title = reminder.name
        content.body = reminder.message.isEmpty
            ? "Pausa de \(durationLabel(reminder.durationSeconds))."
            : "\(reminder.message) (\(durationLabel(reminder.durationSeconds)))"
        content.categoryIdentifier = "cuco.acoes"
        content.sound = Pref.breakSound()
        center.add(UNNotificationRequest(identifier: reminder.notificationID, content: content, trigger: nil))

        if Pref.bool(Pref.fullScreenBreak), !skipFullScreenOnce {
            overlay.show(reminder, total: reminder.duration)
        }
        skipFullScreenOnce = false
    }

    private func endBreak(completed: Bool) {
        guard let reminder = activeBreak else { return }
        activeBreak = nil
        breakEndsAt = nil
        overlay.hide()

        if completed, Pref.bool(Pref.notifyBreakEnd) {
            let content = UNMutableNotificationContent()
            content.title = "Pausa terminada"
            content.body = "Já podes voltar ao ecrã."
            content.sound = Pref.breakSound()
            UNUserNotificationCenter.current().add(UNNotificationRequest(
                identifier: reminder.notificationID + ".fim", content: content, trigger: nil
            ))
        }
        refreshStatusItem()
    }

    private func snooze() {
        for reminder in reminders {
            nextDue[reminder.id] = max(due(reminder), Date().addingTimeInterval(5 * 60))
        }
        refreshStatusItem()
    }

    // MARK: Autorização

    private func checkAuthorization(promptIfDenied: Bool) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let allowed = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            DispatchQueue.main.async {
                let changed = allowed != self.notificationsAllowed
                self.notificationsAllowed = allowed
                if changed { self.rebuildMenu() }
                if !allowed, promptIfDenied { self.showPermissionAlert() }
            }
        }
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "O Cuco não pode enviar notificações"
        alert.informativeText = """
            As notificações estão desligadas para esta app, por isso os avisos de pausa não aparecem.

            Liga-as em Definições do Sistema → Notificações → Cuco.
            """
        alert.addButton(withTitle: "Abrir definições")
        alert.addButton(withTitle: "Agora não")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openNotificationSettings()
        }
    }

    // MARK: Barra de menus

    private func refreshStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = nil

        let active = activeReminders

        if let reminder = activeBreak, let end = breakEndsAt {
            let remaining = clockLabel(end.timeIntervalSinceNow)
            var parts = [(reminder.symbol, remaining)]
            // Os outros continuam a contar, por isso continuam à vista.
            for other in active where other.id != reminder.id {
                parts.append((other.symbol, compactLabel(until: due(other))))
            }
            button.attributedTitle = statusTitle(Array(parts.prefix(3)))
            updateHeader(active, breakRemaining: remaining, reminder: reminder)
            return
        }

        if isMuted {
            button.attributedTitle = statusTitle([("eye.slash", "")])
        } else if active.isEmpty {
            button.attributedTitle = statusTitle([("eye.slash", "")])
        } else if Pref.bool(Pref.showCountdown) {
            let parts = active.prefix(3).map { ($0.symbol, compactLabel(until: due($0))) }
            button.attributedTitle = statusTitle(Array(parts))
        } else {
            button.attributedTitle = statusTitle([(active[0].symbol, "")])
        }

        updateHeader(active, breakRemaining: nil, reminder: nil)
    }

    private func updateHeader(_ active: [Reminder], breakRemaining: String?, reminder: Reminder?) {
        guard !headerItems.isEmpty else { return }

        if let remaining = breakRemaining, let reminder {
            headerItems[0].title = "\(reminder.name) — \(remaining)"
            for item in headerItems.dropFirst() { item.title = "" }
            for (index, other) in active.filter({ $0.id != reminder.id }).enumerated()
            where index + 1 < headerItems.count {
                headerItems[index + 1].title = "\(other.name): daqui a \(minutesLabel(until: due(other)))"
            }
            return
        }

        if isMuted {
            headerItems[0].title = "Silenciado \(mutedLabel())"
            for item in headerItems.dropFirst() { item.title = "" }
            return
        }

        for (index, item) in headerItems.enumerated() {
            if index < active.count {
                item.title = "\(active[index].name): daqui a \(minutesLabel(until: due(active[index])))"
            } else {
                item.title = ""
            }
        }
    }

    private func minutesLabel(until date: Date) -> String {
        let remaining = date.timeIntervalSinceNow
        if remaining <= 60 { return "<1 min" }
        return "\(Int(ceil(remaining / 60))) min"
    }

    private func compactLabel(until date: Date) -> String {
        let remaining = date.timeIntervalSinceNow
        if remaining <= 60 { return "<1" }
        return "\(Int(ceil(remaining / 60)))"
    }

    private func mutedLabel() -> String {
        guard let until = mutedUntil else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDateInToday(until) ? "HH:mm" : "d MMM, HH:mm"
        return "até \(formatter.string(from: until))"
    }

    /// Título da barra de menus: pares de (símbolo, texto), com os símbolos pintados
    /// na cor do texto do menu — um NSTextAttachment não herda a tinta sozinho.
    private func statusTitle(_ parts: [(String, String)]) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: 13, weight: .regular)
        let result = NSMutableAttributedString()

        for (index, part) in parts.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "  ", attributes: [.font: font]))
            }
            if let image = tintedSymbol(part.0) {
                let attachment = NSTextAttachment()
                attachment.image = image
                attachment.bounds = NSRect(
                    x: 0, y: font.descender + 1, width: image.size.width, height: image.size.height
                )
                result.append(NSAttributedString(attachment: attachment))
            }
            if !part.1.isEmpty {
                result.append(NSAttributedString(
                    string: " \(part.1)",
                    attributes: [.font: font, .foregroundColor: NSColor.labelColor]
                ))
            }
        }
        return result
    }

    private func tintedSymbol(_ name: String) -> NSImage? {
        let appearance = statusItem.button?.effectiveAppearance.name.rawValue ?? ""
        let key = "\(name)|\(appearance)"
        if let cached = symbolCache[key] { return cached }

        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular)) else { return nil }

        var tint = NSColor.labelColor
        statusItem.button?.effectiveAppearance.performAsCurrentDrawingAppearance {
            tint = NSColor.labelColor.usingColorSpace(.deviceRGB) ?? .black
        }

        let image = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            tint.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        symbolCache[key] = image
        return image
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if !notificationsAllowed {
            menu.addItem(item("⚠︎  Notificações desligadas — clica aqui", #selector(openNotificationSettings)))
            menu.addItem(.separator())
        }

        // Uma linha por lembrete ligado, preenchida a cada segundo.
        headerItems = []
        for _ in 0..<max(1, activeReminders.count) {
            let line = NSMenuItem()
            line.isEnabled = false
            menu.addItem(line)
            headerItems.append(line)
        }
        menu.addItem(.separator())

        let now = NSMenu()
        for reminder in reminders {
            now.addItem(item(reminder.name, #selector(breakNowFor(_:)), object: reminder.id))
        }
        menu.addItem(submenu("Fazer pausa agora", now))
        menu.addItem(item("Adiar 5 minutos", #selector(snoozeFromMenu)))
        menu.addItem(item("Recomeçar a contagem", #selector(restart)))
        menu.addItem(.separator())

        let list = NSMenu()
        for reminder in reminders {
            let entry = NSMenuItem(title: reminder.name, action: nil, keyEquivalent: "")
            entry.state = reminder.enabled ? .on : .off
            entry.image = NSImage(systemSymbolName: reminder.symbol, accessibilityDescription: nil)
            entry.submenu = reminderMenu(for: reminder)
            list.addItem(entry)
        }
        list.addItem(.separator())
        list.addItem(item("Novo lembrete…", #selector(newReminder)))
        menu.addItem(submenu("Lembretes", list))

        let mute = NSMenu()
        mute.addItem(item("1 hora", #selector(muteFor(_:)), object: 60))
        mute.addItem(item("2 horas", #selector(muteFor(_:)), object: 120))
        mute.addItem(item("Até amanhã", #selector(muteFor(_:)), object: -1))
        mute.addItem(.separator())
        mute.addItem(item("Retomar", #selector(unmute)))
        menu.addItem(submenu("Silenciar", mute))
        menu.addItem(.separator())

        menu.addItem(toggle("Iniciar com o sistema", #selector(toggleLogin), SMAppService.mainApp.status == .enabled))
        menu.addItem(toggle("Pausa em ecrã inteiro", #selector(toggleFullScreen), Pref.bool(Pref.fullScreenBreak)))

        let options = NSMenu()
        options.addItem(toggle("Contagem na barra de menus", #selector(toggleCountdown), Pref.bool(Pref.showCountdown)))
        options.addItem(toggle("Avisar quando a pausa acaba", #selector(toggleBreakEnd), Pref.bool(Pref.notifyBreakEnd)))

        let sounds = NSMenu()
        let silent = item("Sem som", #selector(pickSound(_:)), object: "")
        silent.state = Pref.bool(Pref.playSound) ? .off : .on
        sounds.addItem(silent)
        sounds.addItem(.separator())
        for name in Pref.sounds {
            let entry = item(name, #selector(pickSound(_:)), object: name)
            entry.state = (Pref.bool(Pref.playSound) && Pref.string(Pref.soundName) == name) ? .on : .off
            sounds.addItem(entry)
        }
        options.addItem(submenu("Som", sounds))

        let warning = NSMenu()
        for value in [0, 5, 10, 30] {
            let title = value == 0 ? "Sem aviso" : "\(value) s antes"
            let entry = item(title, #selector(setWarning(_:)), object: value)
            entry.state = (Pref.int(Pref.warnSeconds) == value) ? .on : .off
            warning.addItem(entry)
        }
        options.addItem(submenu("Aviso antes do ecrã inteiro", warning))
        options.addItem(.separator())
        options.addItem(item("Definições de notificações…", #selector(openNotificationSettings)))
        menu.addItem(submenu("Mais opções", options))

        menu.addItem(.separator())
        menu.addItem(item("Sair", #selector(quit)))
        return menu
    }

    /// Tudo o que se pode mexer num lembrete.
    private func reminderMenu(for reminder: Reminder) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let power = item(reminder.enabled ? "Ligado" : "Desligado", #selector(toggleReminder(_:)), object: reminder.id)
        power.state = reminder.enabled ? .on : .off
        menu.addItem(power)
        menu.addItem(.separator())

        let intervals = NSMenu()
        for value in [10, 15, 20, 25, 30, 45, 60, 90] {
            let entry = item(minutesText(value), #selector(setInterval(_:)), object: ["id": reminder.id, "value": value])
            entry.state = (reminder.intervalMinutes == value) ? .on : .off
            intervals.addItem(entry)
        }
        intervals.addItem(.separator())
        let customInterval = item(
            [10, 15, 20, 25, 30, 45, 60, 90].contains(reminder.intervalMinutes)
                ? "Personalizar…" : "Personalizado: \(minutesText(reminder.intervalMinutes))…",
            #selector(customInterval(_:)), object: reminder.id
        )
        customInterval.state = [10, 15, 20, 25, 30, 45, 60, 90].contains(reminder.intervalMinutes) ? .off : .on
        intervals.addItem(customInterval)
        menu.addItem(submenu("De quanto em quanto tempo", intervals))

        let durations = NSMenu()
        for value in [20, 30, 60, 120, 300, 600] {
            let entry = item(durationLabel(value), #selector(setDuration(_:)), object: ["id": reminder.id, "value": value])
            entry.state = (reminder.durationSeconds == value) ? .on : .off
            durations.addItem(entry)
        }
        durations.addItem(.separator())
        let customDuration = item(
            [20, 30, 60, 120, 300, 600].contains(reminder.durationSeconds)
                ? "Personalizar…" : "Personalizado: \(durationLabel(reminder.durationSeconds))…",
            #selector(customDuration(_:)), object: reminder.id
        )
        customDuration.state = [20, 30, 60, 120, 300, 600].contains(reminder.durationSeconds) ? .off : .on
        durations.addItem(customDuration)
        menu.addItem(submenu("Quanto dura a pausa", durations))
        menu.addItem(.separator())

        menu.addItem(item("Mudar o nome…", #selector(renameReminder(_:)), object: reminder.id))
        menu.addItem(item("Mudar a mensagem…", #selector(editMessage(_:)), object: reminder.id))

        let icons = NSMenu()
        for (symbol, label) in Reminder.symbols {
            let entry = item(label, #selector(setSymbol(_:)), object: ["id": reminder.id, "symbol": symbol])
            entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            entry.state = (reminder.symbol == symbol) ? .on : .off
            icons.addItem(entry)
        }
        menu.addItem(submenu("Ícone", icons))

        if reminders.count > 1 {
            menu.addItem(.separator())
            menu.addItem(item("Apagar este lembrete", #selector(deleteReminder(_:)), object: reminder.id))
        }
        return menu
    }

    private func item(_ title: String, _ action: Selector, object: Any? = nil) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        menuItem.representedObject = object
        return menuItem
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menuItem.submenu = menu
        return menuItem
    }

    private func toggle(_ title: String, _ action: Selector, _ on: Bool) -> NSMenuItem {
        let menuItem = item(title, action)
        menuItem.state = on ? .on : .off
        return menuItem
    }

    private func rebuildMenu() {
        statusItem.menu = buildMenu()
        refreshStatusItem()
    }

    // MARK: Acções

    @objc private func testBreak() {
        guard let first = activeReminders.first ?? reminders.first else { return }
        startBreak(first)
    }

    @objc private func breakNowFor(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let reminder = reminder(id) else { return }
        mutedUntil = nil
        startBreak(reminder)
        refreshStatusItem()
    }

    @objc private func snoozeFromMenu() {
        endBreak(completed: false)
        snooze()
    }

    @objc private func restart() {
        mutedUntil = nil
        endBreak(completed: false)
        scheduleAll()
        refreshStatusItem()
    }

    @objc private func toggleReminder(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        update(id) { reminder in
            reminder.enabled.toggle()
            if reminder.enabled { self.schedule(reminder) }
        }
    }

    @objc private func setInterval(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? [String: Any],
              let id = payload["id"] as? String, let value = payload["value"] as? Int else { return }
        update(id) { reminder in
            reminder.intervalMinutes = value
            self.schedule(reminder)
        }
    }

    @objc private func setDuration(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? [String: Any],
              let id = payload["id"] as? String, let value = payload["value"] as? Int else { return }
        update(id) { $0.durationSeconds = value }
    }

    @objc private func setSymbol(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? [String: Any],
              let id = payload["id"] as? String, let symbol = payload["symbol"] as? String else { return }
        symbolCache.removeAll()
        update(id) { $0.symbol = symbol }
    }

    @objc private func customInterval(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let current = reminder(id) else { return }
        guard let value = askNumber(
            title: "De quanto em quanto tempo: \(current.name)",
            explanation: "Em minutos, entre 1 minuto e 8 horas.",
            current: current.intervalMinutes, range: 1...480, unitIsSeconds: false
        ) else { return }
        update(id) { reminder in
            reminder.intervalMinutes = value
            self.schedule(reminder)
        }
    }

    @objc private func customDuration(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let current = reminder(id) else { return }
        guard let value = askNumber(
            title: "Quanto dura a pausa: \(current.name)",
            explanation: "Em segundos, entre 5 segundos e 30 minutos. Aceita 30 s, 2 min ou 1:30.",
            current: current.durationSeconds, range: 5...1800, unitIsSeconds: true
        ) else { return }
        update(id) { $0.durationSeconds = value }
    }

    @objc private func renameReminder(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let current = reminder(id) else { return }
        guard let name = askText(
            title: "Que nome dás a este lembrete?",
            explanation: "É o que aparece na notificação e no ecrã de pausa.",
            current: current.name, placeholder: "Estudo"
        ) else { return }
        update(id) { $0.name = name }
    }

    @objc private func editMessage(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let current = reminder(id) else { return }
        guard let message = askText(
            title: "O que te deve dizer?",
            explanation: "A linha que aparece por baixo do nome.",
            current: current.message, placeholder: "Revê os apontamentos em voz alta."
        ) else { return }
        update(id) { $0.message = message }
    }

    @objc private func deleteReminder(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let current = reminder(id) else { return }
        let alert = NSAlert()
        alert.messageText = "Apagar \u{201C}\(current.name)\u{201D}?"
        alert.informativeText = "Deixas de ser avisado por este lembrete."
        alert.addButton(withTitle: "Apagar")
        alert.addButton(withTitle: "Cancelar")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        reminders.removeAll { $0.id == id }
        nextDue[id] = nil
        saveReminders()
        rebuildMenu()
    }

    @objc private func newReminder() {
        guard let name = askText(
            title: "Que lembrete queres criar?",
            explanation: "Por exemplo: Estudo, Beber água, Postura.",
            current: "", placeholder: "Estudo"
        ) else { return }

        let message = askText(
            title: "O que te deve dizer?",
            explanation: "Podes deixar vazio.",
            current: "", placeholder: "Revê os apontamentos em voz alta.",
            allowEmpty: true
        ) ?? ""

        guard let interval = askNumber(
            title: "De quanto em quanto tempo?",
            explanation: "Em minutos, entre 1 minuto e 8 horas.",
            current: 30, range: 1...480, unitIsSeconds: false
        ) else { return }

        guard let duration = askNumber(
            title: "Quanto dura a pausa?",
            explanation: "Em segundos, entre 5 segundos e 30 minutos. Aceita 30 s, 2 min ou 1:30.",
            current: 60, range: 5...1800, unitIsSeconds: true
        ) else { return }

        var reminder = Reminder(
            name: name, message: message, symbol: "bell",
            intervalMinutes: interval, durationSeconds: duration
        )
        reminder.enabled = true
        reminders.append(reminder)
        schedule(reminder)
        saveReminders()
        rebuildMenu()
    }

    @objc private func muteFor(_ sender: NSMenuItem) {
        endBreak(completed: false)
        let minutes = sender.representedObject as? Int ?? 60
        if minutes > 0 {
            mutedUntil = Date().addingTimeInterval(Double(minutes) * 60)
        } else {
            var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            components.day! += 1
            components.hour = 8
            mutedUntil = Calendar.current.date(from: components)
        }
        refreshStatusItem()
    }

    @objc private func unmute() {
        mutedUntil = nil
        restart()
    }

    @objc private func toggleCountdown() {
        Pref.set(!Pref.bool(Pref.showCountdown), Pref.showCountdown)
        rebuildMenu()
    }

    @objc private func toggleBreakEnd() {
        Pref.set(!Pref.bool(Pref.notifyBreakEnd), Pref.notifyBreakEnd)
        rebuildMenu()
    }

    @objc private func toggleFullScreen() {
        Pref.set(!Pref.bool(Pref.fullScreenBreak), Pref.fullScreenBreak)
        rebuildMenu()
    }

    @objc private func pickSound(_ sender: NSMenuItem) {
        let name = sender.representedObject as? String ?? ""
        Pref.set(!name.isEmpty, Pref.playSound)
        if !name.isEmpty {
            Pref.set(name, Pref.soundName)
            // Tocar já, para ouvires no que estás a pegar.
            NSSound(named: name == "Predefinido" ? "Funk" : name)?.play()
        }
        rebuildMenu()
    }

    @objc private func setWarning(_ sender: NSMenuItem) {
        Pref.set(sender.representedObject as? Int ?? 10, Pref.warnSeconds)
        rebuildMenu()
    }

    private func syncLoginItem() {
        let wanted = Pref.bool(Pref.openAtLogin)
        let service = SMAppService.mainApp
        do {
            if wanted, service.status != .enabled {
                try service.register()
            } else if !wanted, service.status == .enabled {
                try service.unregister()
            }
        } catch {
            NSLog("Cuco: não consegui mudar o arranque automático: \(error)")
        }
    }

    @objc private func toggleLogin() {
        Pref.set(SMAppService.mainApp.status != .enabled, Pref.openAtLogin)
        syncLoginItem()
        rebuildMenu()
    }

    @objc private func openNotificationSettings() {
        checkAuthorization(promptIfDenied: false)
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Caixas de diálogo

    private func askText(
        title: String, explanation: String, current: String,
        placeholder: String, allowEmpty: Bool = false
    ) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = explanation
        alert.addButton(withTitle: "Guardar")
        alert.addButton(withTitle: "Cancelar")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = current
        field.placeholderString = placeholder
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return allowEmpty ? "" : nil }
        return text
    }

    /// Aceita "45", "45 s", "2 min", "1h" ou "1:30" e devolve o valor na unidade do campo.
    private func parseAmount(_ raw: String, unitIsSeconds: Bool) -> Int? {
        var text = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty else { return nil }

        if text.contains(":") {
            let parts = text.split(separator: ":")
            guard parts.count == 2,
                  let big = Int(parts[0]), let small = Int(parts[1].trimmingCharacters(in: .whitespaces)),
                  small >= 0, small < 60 else { return nil }
            return big * 60 + small
        }

        var multiplier = 1.0
        for (suffix, seconds) in [("horas", 3600.0), ("hora", 3600.0), ("h", 3600.0),
                                  ("minutos", 60.0), ("minuto", 60.0), ("min", 60.0), ("m", 60.0),
                                  ("segundos", 1.0), ("segundo", 1.0), ("seg", 1.0), ("s", 1.0)]
        where text.hasSuffix(suffix) {
            text = String(text.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            multiplier = unitIsSeconds ? seconds : seconds / 60
            break
        }

        guard let number = Double(text.replacingOccurrences(of: ",", with: ".")) else { return nil }
        let value = number * multiplier
        guard value >= 1 else { return nil }
        return Int(value.rounded())
    }

    private func askNumber(
        title: String, explanation: String, current: Int,
        range: ClosedRange<Int>, unitIsSeconds: Bool
    ) -> Int? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = explanation
        alert.addButton(withTitle: "Guardar")
        alert.addButton(withTitle: "Cancelar")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
        field.stringValue = "\(current)"
        field.alignment = .right
        field.placeholderString = unitIsSeconds ? "ex.: 30 s" : "ex.: 45"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        guard let value = parseAmount(field.stringValue, unitIsSeconds: unitIsSeconds),
              range.contains(value) else {
            let low = unitIsSeconds ? durationLabel(range.lowerBound) : minutesText(range.lowerBound)
            let high = unitIsSeconds ? durationLabel(range.upperBound) : minutesText(range.upperBound)
            let error = NSAlert()
            error.messageText = "Esse valor não serve"
            error.informativeText = "Escolhe algo entre \(low) e \(high)."
            NSApp.activate(ignoringOtherApps: true)
            error.runModal()
            return nil
        }
        return value
    }

    // MARK: Respostas às notificações

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        let isWarning = response.notification.request.content.categoryIdentifier == "cuco.aviso"
        DispatchQueue.main.async {
            if isWarning {
                switch action {
                case "sem_ecra": self.skipFullScreenOnce = true
                case "adiar": self.snooze()
                default: break
                }
                return
            }
            if action == "adiar" {
                self.endBreak(completed: false)
                self.snooze()
            } else if action == "feito" {
                self.endBreak(completed: false)
            }
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

let app = NSApplication.shared
let controller = Controller()
app.delegate = controller
app.setActivationPolicy(.accessory)
app.run()
