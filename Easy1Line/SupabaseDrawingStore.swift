import Foundation

struct SupabaseConfiguration {
    let url: URL
    let anonKey: String

    static var current: SupabaseConfiguration? {
        guard let rawURL = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              let url = URL(string: rawURL),
              let anonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !anonKey.isEmpty else {
            return nil
        }
        return SupabaseConfiguration(url: url, anonKey: anonKey)
    }
}

struct SupabaseDrawingStore {
    enum StoreError: Error {
        case missingConfiguration
        case invalidResponse
        case requestFailed(Int, String)
    }

    private let configuration: SupabaseConfiguration

    init?(configuration: SupabaseConfiguration? = .current) {
        guard let configuration else { return nil }
        self.configuration = configuration
    }

    // appending(path:) percent-encodes "?", which turns the query string into a 404ing path.
    private func endpoint(_ pathAndQuery: String) -> URL {
        URL(string: pathAndQuery, relativeTo: configuration.url)!.absoluteURL
    }

    func saveDrawing(id: UUID, name: String, data: Data, createdByName: String = "", updatedByName: String = "") async throws {
        let dataObject = try JSONSerialization.jsonObject(with: data)
        let payload: [String: Any] = [
            "p_id": id.uuidString,
            "p_name": name,
            "p_data": dataObject,
            "p_created_by_name": createdByName,
            "p_updated_by_name": updatedByName
        ]
        var request = URLRequest(url: endpoint("/rest/v1/rpc/save_drawing"))
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.setValue("Bearer \(configuration.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            try await perform(request)
        } catch StoreError.requestFailed(let statusCode, let message) where statusCode == 404 && message.contains("PGRST202") {
            var legacyRequest = URLRequest(url: endpoint("/rest/v1/rpc/save_drawing"))
            legacyRequest.httpMethod = "POST"
            legacyRequest.httpBody = try JSONSerialization.data(withJSONObject: [
                "p_id": id.uuidString,
                "p_name": name,
                "p_data": dataObject
            ])
            legacyRequest.setValue("Bearer \(configuration.anonKey)", forHTTPHeaderField: "Authorization")
            legacyRequest.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
            legacyRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            try await perform(legacyRequest)
        }
    }

    func loadProfiles() async throws -> [SupabaseProfileRecord] {
        var request = URLRequest(url: endpoint("/rest/v1/profiles?select=id,display_name&order=display_name.asc"))
        request.setValue("Bearer \(configuration.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode([SupabaseProfileRecord].self, from: data)
    }

    func createProfile(name: String) async throws -> SupabaseProfileRecord {
        var request = URLRequest(url: endpoint("/rest/v1/profiles"))
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["display_name": name])
        request.setValue("Bearer \(configuration.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        guard let profile = try JSONDecoder().decode([SupabaseProfileRecord].self, from: data).first else { throw StoreError.invalidResponse }
        return profile
    }

    func loadDrawings() async throws -> [SupabaseDrawingRecord] {
        var request = URLRequest(url: endpoint("/rest/v1/drawings?select=id,name,data&order=updated_at.desc"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(configuration.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode([SupabaseDrawingRecord].self, from: data)
    }

    func loadTargetTypes() async throws -> [SupabaseTargetTypeRecord] {
        var request = URLRequest(url: endpoint("/rest/v1/target_types?select=kind,name,symbol,color_hex,max_connections,connection_angle,connection_angles"))
        request.setValue("Bearer \(configuration.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode([SupabaseTargetTypeRecord].self, from: data)
    }

    func loadWireDefinitions() async throws -> [SupabaseWireDefinitionRecord] {
        var request = URLRequest(url: endpoint("/rest/v1/wire_definitions?select=id,name,wire_size,wire_type,material,misc,description&order=name.asc"))
        request.setValue("Bearer \(configuration.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode([SupabaseWireDefinitionRecord].self, from: data)
    }

    func upsertWireDefinition(_ definition: SharedWireDefinitionPayload) async throws {
        var request = URLRequest(url: endpoint("/rest/v1/wire_definitions"))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(definition)
        request.setValue("Bearer \(configuration.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        try await perform(request)
    }

    func upsertTargetDefinition(_ definition: SharedTargetDefinitionPayload) async throws {
        var request = URLRequest(url: endpoint("/rest/v1/target_types"))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(definition)
        request.setValue("Bearer \(configuration.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        try await perform(request)
    }

    func loadConductorCatalog() async throws -> [SupabaseConductorRecord] {
        var request = URLRequest(url: endpoint("/rest/v1/conductor_catalog?select=material,wire_size"))
        request.setValue("Bearer \(configuration.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode([SupabaseConductorRecord].self, from: data)
    }

    func loadWireSizes() async throws -> [SupabaseWireSizeRecord] {
        var request = URLRequest(url: endpoint("/rest/v1/wire_sizes?select=id,size_value&order=size_value.asc"))
        request.setValue("Bearer \(configuration.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode([SupabaseWireSizeRecord].self, from: data)
    }

    func loadWireTypes() async throws -> [SupabaseWireTypeRecord] {
        var request = URLRequest(url: endpoint("/rest/v1/wire_types?select=id,type_name,color_hex&order=type_name.asc"))
        request.setValue("Bearer \(configuration.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode([SupabaseWireTypeRecord].self, from: data)
    }

    func loadWireMiscOptions() async throws -> [SupabaseWireMiscRecord] {
        var request = URLRequest(url: endpoint("/rest/v1/wire_misc?select=id,misc_value&order=misc_value.asc"))
        request.setValue("Bearer \(configuration.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode([SupabaseWireMiscRecord].self, from: data)
    }

    func loadWireLibrary() async throws -> [SupabaseWireLibraryRecord] {
        var request = URLRequest(url: endpoint("/rest/v1/wire_library?select=id,size_id,type_id,misc_id,description,display_size,color_hex,wire_sizes(size_value),wire_types(type_name,color_hex),wire_misc(misc_value)&order=id.asc"))
        request.setValue("Bearer \(configuration.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode([SupabaseWireLibraryRecord].self, from: data)
    }

    func createWireLibraryEntry(sizeID: Int, typeID: Int, miscID: Int, description: String = "", displaySize: Double = 2.0, colorHex: String = "31D7E8") async throws -> SupabaseWireLibraryRecord {
        var request = URLRequest(url: endpoint("/rest/v1/wire_library"))
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "size_id": sizeID,
            "type_id": typeID,
            "misc_id": miscID,
            "description": description,
            "display_size": displaySize,
            "color_hex": colorHex
        ])
        request.setValue("Bearer \(configuration.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let results = try JSONDecoder().decode([SupabaseWireLibraryRecord].self, from: data)
        guard let result = results.first else { throw StoreError.invalidResponse }
        return result
    }

    func deleteWireLibraryEntry(id: Int) async throws {
        var request = URLRequest(url: endpoint("/rest/v1/wire_library?id=eq.\(id)"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(configuration.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        try await perform(request)
    }

    func loadDrawingData() async throws -> [(id: UUID, name: String, data: Data)] {
        var request = URLRequest(url: endpoint("/rest/v1/drawings?select=id,name,data&order=updated_at.desc"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(configuration.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw StoreError.invalidResponse }
        return try rows.compactMap { row in
            guard let rawID = row["id"] as? String, let id = UUID(uuidString: rawID),
                  let name = row["name"] as? String, let drawing = row["data"] else { return nil }
            return (id, name, try JSONSerialization.data(withJSONObject: drawing))
        }
    }

    func loadDrawing(id: UUID) async throws -> (id: UUID, name: String, data: Data)? {
        var request = URLRequest(url: endpoint("/rest/v1/drawings?id=eq.\(id.uuidString)&select=id,name,data"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(configuration.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], let row = rows.first else { return nil }
        guard let rawID = row["id"] as? String, let rowID = UUID(uuidString: rawID),
              let name = row["name"] as? String, let drawing = row["data"] else { return nil }
        return (rowID, name, try JSONSerialization.data(withJSONObject: drawing))
    }

    func deleteDrawing(id: UUID) async throws {
        var request = URLRequest(url: endpoint("/rest/v1/drawings?id=eq.\(id.uuidString)"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(configuration.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws {
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else { throw StoreError.invalidResponse }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw StoreError.requestFailed(httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "Unknown Supabase error")
        }
    }
}

struct SupabaseDrawingRecord: Codable {
    let id: UUID
    let name: String
    let data: [String: JSONValue]
}

struct SupabaseProfileRecord: Codable, Identifiable {
    let id: UUID
    let displayName: String
    enum CodingKeys: String, CodingKey { case id; case displayName = "display_name" }
}

struct SupabaseTargetTypeRecord: Codable {
    let kind: String
    let name: String
    let symbol: String?
    let colorHex: String
    let maxConnections: Int?
    let connectionAngle: Double
    let connectionAngles: [Double]

    enum CodingKeys: String, CodingKey { case kind, name, symbol, colorHex = "color_hex", maxConnections = "max_connections", connectionAngle = "connection_angle", connectionAngles = "connection_angles" }
}

struct SupabaseWireDefinitionRecord: Codable, Identifiable {
    let id: UUID
    let name: String
    let wireSize: String
    let wireType: String
    let material: String
    let misc: String
    let description: String

    enum CodingKeys: String, CodingKey {
        case id, name, material, misc, description
        case wireSize = "wire_size"
        case wireType = "wire_type"
    }
}

struct SharedWireDefinitionPayload: Codable {
    let id: UUID
    let name: String
    let wireSize: String
    let wireType: String
    let material: String
    let misc: String
    let description: String

    enum CodingKeys: String, CodingKey {
        case id, name, material, misc, description
        case wireSize = "wire_size"
        case wireType = "wire_type"
    }
}

struct SharedTargetDefinitionPayload: Codable {
    let id: UUID
    let kind: String
    let name: String
    let symbol: String
    let colorHex: String
    let maxConnections: Int
    let scale: Double
    let connectionAngle: Double
    let connectionAngles: [Double]

    enum CodingKeys: String, CodingKey {
        case id, kind, name, symbol, scale
        case colorHex = "color_hex"
        case maxConnections = "max_connections"
        case connectionAngle = "connection_angle"
        case connectionAngles = "connection_angles"
    }
}

struct SupabaseConductorRecord: Codable {
    let material: String
    let wireSize: String
    enum CodingKeys: String, CodingKey { case material, wireSize = "wire_size" }
}

struct SupabaseWireSizeRecord: Codable, Identifiable {
    let id: Int
    let sizeValue: String
    enum CodingKeys: String, CodingKey { case id, sizeValue = "size_value" }
}

struct SupabaseWireTypeRecord: Codable, Identifiable {
    let id: Int
    let typeName: String
    let colorHex: String
    enum CodingKeys: String, CodingKey { case id, typeName = "type_name", colorHex = "color_hex" }
}

struct SupabaseWireMiscRecord: Codable, Identifiable {
    let id: Int
    let miscValue: String
    enum CodingKeys: String, CodingKey { case id, miscValue = "misc_value" }
}

struct SupabaseWireLibraryRecord: Codable, Identifiable {
    let id: Int
    let sizeID: Int
    let typeID: Int
    let miscID: Int
    let description: String
    let displaySize: Double
    let colorHex: String
    let wireSizes: [SizeDetail]?
    let wireTypes: [TypeDetail]?
    let wireMisc: [MiscDetail]?
    
    enum CodingKeys: String, CodingKey {
        case id, description
        case sizeID = "size_id"
        case typeID = "type_id"
        case miscID = "misc_id"
        case displaySize = "display_size"
        case colorHex = "color_hex"
        case wireSizes = "wire_sizes"
        case wireTypes = "wire_types"
        case wireMisc = "wire_misc"
    }
    
    struct SizeDetail: Codable {
        let sizeValue: String
        enum CodingKeys: String, CodingKey { case sizeValue = "size_value" }
    }
    
    struct TypeDetail: Codable {
        let typeName: String
        let colorHex: String
        enum CodingKeys: String, CodingKey { case typeName = "type_name", colorHex = "color_hex" }
    }
    
    struct MiscDetail: Codable {
        let miscValue: String
        enum CodingKeys: String, CodingKey { case miscValue = "misc_value" }
    }
    
    var size: String { wireSizes?.first?.sizeValue ?? "Unknown" }
    var type: String { wireTypes?.first?.typeName ?? "Unknown" }
    var misc: String { wireMisc?.first?.miscValue ?? "Unknown" }
}

enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
