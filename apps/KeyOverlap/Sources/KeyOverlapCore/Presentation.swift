import Foundation

/// Derive claims from the entire plan before filtering cards.
public struct PlanComparison {
    public let pairs: [Overlap]
    public let showPossible: Bool
    public init(pairs: [Overlap], showPossible: Bool) { self.pairs = pairs; self.showPossible = showPossible }
    public var visible: [Overlap] { pairs.filter { showPossible || $0.kind != .possible } }
    public var isClear: Bool { !pairs.contains { $0.kind != .separate } }
    public var hasHiddenPossible: Bool { !showPossible && pairs.contains { $0.kind == .possible } }
}

public enum RecordDefaults {
    public static func scope(for record: ShortcutRecord?, defaultScope: String) -> String {
        guard let record else { return defaultScope }
        return record.scope ?? ""
    }
}

public enum PolicyDestination {
    public static func webURL(_ value: String?) -> URL? {
        guard let value, !value.contains("{"), !value.contains("}"),
              let url = URL(string: value), url.scheme == "https", let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}

public enum PlanText {
    public static let spanish: [String: String] = [
        "Use one letter, digit, punctuation key or a named key such as space or F5.": "Usa una letra, un número, una tecla de puntuación o una tecla con nombre como space o F5.",
        "Modifiers must be unique command, option, shift or control values.": "Los modificadores deben ser valores únicos command, option, shift o control.",
        "Enter a chord such as command+option+k.": "Introduce un atajo como command+option+k.",
        "Enter a command name.": "Introduce un nombre de comando.",
        "A global scope cannot have an app context.": "Un ámbito global no puede tener contexto de aplicación.",
        "Give a context an app scope.": "Asigna un ámbito de aplicación al contexto.",
        "Enter an app and two different contexts.": "Introduce una aplicación y dos contextos diferentes.",
        "The saved plan contains duplicate identifiers.": "El plan guardado contiene identificadores duplicados.",
        "A replacement refers to a missing record.": "Un reemplazo hace referencia a un registro que falta.",
        "Select a saved record before staging a replacement.": "Selecciona un registro guardado antes de proponer un reemplazo.",
        "The root must be a JSON array.": "La raíz debe ser una matriz JSON.",
        "Use exactly command, key, modifiers, scope and context with the documented types.": "Usa exactamente command, key, modifiers, scope y context con los tipos documentados.",
        "Use a supported key with at least one modifier for the planner shortcut.": "Usa una tecla admitida con al menos un modificador para abrir el plan.",
        "KeyOverlap manual change checklist": "Lista de cambios manuales de KeyOverlap",
        "These changes affect your local plan only. Set each shortcut manually in its target app.": "Estos cambios solo afectan a tu plan local. Configura cada atajo manualmente en su aplicación de destino.",
        "Unknown scope": "Ámbito desconocido", "Global": "Global", "in": "en",
        "Sample": "Ejemplo", "Candidate": "Candidato", "Space": "Espacio", "Esc": "Esc", "Return": "Retorno", "Tab": "Tabulación",
        "Delete": "Borrar", "Forward Delete": "Suprimir", "Home": "Inicio", "End": "Fin", "Page Up": "Página arriba", "Page Down": "Página abajo"
    ]
    public static func translate(_ value: String, language: String) -> String {
        guard language == "es" else { return value }
        if let text = spanish[value] { return text }
        if value.hasPrefix("Row index "), let split = value.range(of: " · ") {
            let index = value[value.index(value.startIndex, offsetBy: "Row index ".count)..<split.lowerBound]
            return "Índice de fila " + index + " · " + translate(String(value[split.upperBound...]), language: language)
        }
        if value.hasPrefix("The file is not valid JSON.") { return "El archivo no contiene JSON válido. Revisa la sintaxis y vuelve a intentarlo." }
        for (prefix, translation) in [("Shortcut event handler failed with code ", "El controlador del atajo falló con el código "), ("Shortcut registration failed with code ", "El registro del atajo falló con el código ")] {
            if value.hasPrefix(prefix) { return translation + value.dropFirst(prefix.count) }
        }
        return value
    }
    public static func error(_ error: Error, language: String) -> String {
        if let error = error as? PlanError { return translate(error.localizedDescription, language: language) }
        return language == "es" ? "No se pudo completar la operación. Revisa el archivo y los permisos e inténtalo de nuevo." : error.localizedDescription
    }
}
