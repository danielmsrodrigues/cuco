// Faz a Pausa disparar já uma notificação de olhos, para testar sem esperar.
import Foundation

DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("net.danielrodrigues.cuco.teste"),
    object: nil,
    userInfo: nil,
    deliverImmediately: true
)
