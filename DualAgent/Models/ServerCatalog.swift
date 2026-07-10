import Foundation

// MARK: - Server Catalog Types
// Mirrors Hermex/HermesMobile/Models/ServerCatalog.swift

public struct ServerModelCatalog: Equatable, Sendable {
    public let groups: [ServerModelCatalogGroup]
    public let defaultModel: String?

    public init(groups: [ServerModelCatalogGroup], defaultModel: String?) {
        self.groups = groups
        self.defaultModel = defaultModel
    }
}

public struct ServerModelCatalogGroup: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let providerID: String?
    public let models: [ServerModelOption]
    public let extraModels: [ServerModelOption]

    public init(id: String, name: String, providerID: String?, models: [ServerModelOption], extraModels: [ServerModelOption] = []) {
        self.id = id
        self.name = name
        self.providerID = providerID
        self.models = models
        self.extraModels = extraModels
    }
}

public struct ServerModelOption: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let providerID: String?

    public init(id: String, displayName: String, providerID: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.providerID = providerID
    }
}
