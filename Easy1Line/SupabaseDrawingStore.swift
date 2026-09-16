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

    func saveDrawing(id: UUID, name: String, data: Data) async throws {
        var request = URLRequest(url: configuration.url.appending(path: "/rest/v1/rpc/save_drawing"))
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "p_id": id.uuidString,
            "p_name": name,
            "p_data": try JSONSerialization.jsonObject(with: data)
        ])
        request.setValue("Bearer \(configuration.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try await perform(request)
    }

    func loadDrawings() async throws -> [SupabaseDrawingRecord] {
        var request = URLRequest(url: configuration.url.appending(path: "/rest/v1/drawings?select=id,name,data&order=updated_at.desc"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(configuration.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode([SupabaseDrawingRecord].self, from: data)
    }

    func loadDrawingData() async throws -> [(id: UUID, name: String, data: Data)] {
        var request = URLRequest(url: configuration.url.appending(path: "/rest/v1/drawings?select=id,name,data&order=updated_at.desc"))
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

    func deleteDrawing(id: UUID) async throws {
        var request = URLRequest(url: configuration.url.appending(path: "/rest/v1/drawings?id=eq.\(id.uuidString)"))
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
