import SwiftData

enum GauravaModelContainer {
    static func make(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema(gauravaModelTypes)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: inMemory || !CloudKitConfiguration.isEnabled ? .none : .private(CloudKitConfiguration.containerIdentifier)
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Unable to create Gaurava model container: \(error.localizedDescription)")
        }
    }
}
