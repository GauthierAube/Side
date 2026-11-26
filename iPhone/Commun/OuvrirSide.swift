import AppIntents

/// Le bouton du centre de contrôle : ouvre Side, qui ajoute aussitôt ce qu'on vient de copier.
/// (Ce fichier est dans l'app ET dans le widget : iOS l'exige pour qu'un bouton du centre de contrôle ouvre l'app.)
struct OuvrirSide: AppIntent {
    static var title: LocalizedStringResource = "Ouvrir Side"
    static var description = IntentDescription("Ouvre Side et ajoute ce que tu viens de copier à l'historique.")
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult { .result() }
}
