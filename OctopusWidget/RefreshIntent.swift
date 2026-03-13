import AppIntents
import WidgetKit

struct RefreshEnergyIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Energy Data"
    static var description: IntentDescription = "Fetches the latest energy reading"

    func perform() async throws -> some IntentResult {
        // Widget timeline automatically reloads after this returns
        return .result()
    }
}
