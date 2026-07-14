import AppKit
import Foundation

/// Błędy automatyzacji aplikacji Mail.
public enum MailAutomationError: LocalizedError {
    /// Skrypt nie wykonał się — najczęściej brak zgody na automatyzację
    /// (Ustawienia systemowe → Prywatność i ochrona → Automatyzacja)
    /// albo brak skonfigurowanego konta w Mail.
    case scriptFailed(String)

    public var errorDescription: String? {
        switch self {
        case .scriptFailed(let message):
            return "Nie udało się przekazać wiadomości do aplikacji Mail: \(message). "
                + "Sprawdź zgodę na automatyzację (Ustawienia systemowe → Prywatność "
                + "i ochrona → Automatyzacja → Ksefiarz → Mail) oraz konto pocztowe w Mail."
        }
    }
}

/// Czysta budowa skryptu AppleScript dla aplikacji Mail — oddzielona od
/// wykonania, żeby escaping i strukturę skryptu dało się testować
/// jednostkowo (samo wykonanie to granica AppKit/systemu, poza testami).
public enum MailAutomationScript {

    /// Tekst bezpieczny wewnątrz literału AppleScript: escapowane
    /// backslashe i cudzysłowy, znaki nowej linii/tab jako sekwencje
    /// \n / \r / \t (AppleScript 2.0 zna te sekwencje). Bez escapingu
    /// treść wiadomości mogłaby wstrzyknąć własne polecenia do skryptu.
    public static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    /// Skrypt tworzący wiadomość w Mail: `send == true` wysyła od razu,
    /// `false` zapisuje szkic w skrzynce Wersje robocze (do zatwierdzenia).
    /// Wiadomość jest tworzona bez otwierania okna (visible:false).
    public static func build(
        recipient: String,
        subject: String,
        body: String,
        send: Bool
    ) -> String {
        """
        tell application "Mail"
            set theMessage to make new outgoing message with properties {subject:"\(escaped(subject))", content:"\(escaped(body))", visible:false}
            tell theMessage
                make new to recipient at end of to recipients with properties {address:"\(escaped(recipient))"}
            end tell
            \(send ? "send theMessage" : "save theMessage")
        end tell
        """
    }
}

/// Cicha wysyłka / szkic wiadomości przez aplikację Mail (NSAppleScript).
/// Pierwsze użycie wywołuje systemowe pytanie o zgodę na sterowanie Mail;
/// odmowa jest zgłaszana jako błąd (bez cichego gubienia wiadomości).
@MainActor
public enum MailAutomationService {

    /// Tryb dostarczenia przypomnień.
    public enum DeliveryMode: String, CaseIterable, Identifiable, Sendable {
        /// Szkic w Mail (Wersje robocze) — użytkownik przegląda i wysyła sam.
        case draft
        /// Automatyczna wysyłka bez udziału użytkownika.
        case send

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .draft: return "Szkice w Mail (do zatwierdzenia)"
            case .send: return "Wysyłaj automatycznie"
            }
        }
    }

    /// Przekazuje wiadomość do Mail zgodnie z trybem. Rzuca błąd zamiast
    /// cicho przepadać — wywołujący decyduje, jak go pokazać.
    public static func deliver(
        recipient: String,
        subject: String,
        body: String,
        mode: DeliveryMode
    ) throws {
        let source = MailAutomationScript.build(
            recipient: recipient,
            subject: subject,
            body: body,
            send: mode == .send
        )
        guard let script = NSAppleScript(source: source) else {
            throw MailAutomationError.scriptFailed("nie udało się przygotować skryptu")
        }
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = (errorInfo[NSAppleScript.errorMessage] as? String)
                ?? String(describing: errorInfo)
            throw MailAutomationError.scriptFailed(message)
        }
    }
}
