import AppKit
import UserNotifications

/// Um lembrete: nome, mensagem, ícone, de quanto em quanto tempo e quanto dura.
/// "Olhos" e "Andar" são apenas os dois primeiros da lista — podes criar os teus.
struct Reminder {
    var id: String
    var name: String
    var message: String
    var symbol: String
    var intervalMinutes: Int
    var durationSeconds: Int
    var enabled: Bool

    var notificationID: String { "cuco.\(id)" }
    var duration: TimeInterval { TimeInterval(max(5, durationSeconds)) }

    init(
        id: String = UUID().uuidString,
        name: String,
        message: String,
        symbol: String,
        intervalMinutes: Int,
        durationSeconds: Int,
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.message = message
        self.symbol = symbol
        self.intervalMinutes = intervalMinutes
        self.durationSeconds = durationSeconds
        self.enabled = enabled
    }

    init?(dictionary: [String: Any]) {
        guard let id = dictionary["id"] as? String,
              let name = dictionary["name"] as? String else { return nil }
        self.id = id
        self.name = name
        message = dictionary["message"] as? String ?? ""
        symbol = dictionary["symbol"] as? String ?? "bell"
        intervalMinutes = dictionary["interval"] as? Int ?? 30
        durationSeconds = dictionary["duration"] as? Int ?? 60
        enabled = dictionary["enabled"] as? Bool ?? true
    }

    var dictionary: [String: Any] {
        [
            "id": id, "name": name, "message": message, "symbol": symbol,
            "interval": intervalMinutes, "duration": durationSeconds, "enabled": enabled,
        ]
    }

    /// Os dois que vêm de origem, na primeira vez que abres a app.
    static let defaults = [
        Reminder(
            id: "olhos", name: "Olhos",
            message: "Olha para algo a 6 metros de distância.",
            symbol: "eye", intervalMinutes: 20, durationSeconds: 20
        ),
        Reminder(
            id: "andar", name: "Andar",
            message: "Dá uns passos e estica as pernas e as costas.",
            symbol: "figure.walk", intervalMinutes: 50, durationSeconds: 300
        ),
    ]

    /// Ícones à escolha ao criar ou editar um lembrete.
    static let symbols: [(String, String)] = [
        ("eye", "Olho"), ("figure.walk", "Andar"), ("figure.stand", "Postura"),
        ("book", "Livro"), ("pencil", "Escrever"), ("brain", "Cabeça"),
        ("cup.and.saucer", "Café"), ("drop", "Água"), ("fork.knife", "Comer"),
        ("lungs", "Respirar"), ("heart", "Coração"), ("hand.raised", "Mãos"),
        ("timer", "Cronómetro"), ("bell", "Sino"),
    ]
}
