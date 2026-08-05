import Foundation
import FirebaseAuth

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case delete = "DELETE"
}

enum APIClientError: LocalizedError {
    case missingUser
    case invalidURL(String)
    case requestFailed(status: Int, code: String?, message: String, retryAfter: Int?)
    case invalidResponse
    case responseTooLarge(limit: Int)

    var errorDescription: String? {
        switch self {
        case .missingUser:
            return "No hay una sesión activa."
        case .invalidURL(let path):
            return "Ruta API invalida: \(path)"
        case .requestFailed(_, _, let message, _):
            return message
        case .invalidResponse:
            return "Respuesta invalida del servidor."
        case .responseTooLarge(let limit):
            return "El archivo supera el límite permitido de \(limit / 1_000_000) MB."
        }
    }
}

struct CheckAllowlistResponse: Decodable {
    let allowed: Bool
    let isAdmin: Bool?
}

struct RedeemInviteRequest: Encodable {
    let code: String
    let testerName: String?
}

struct RedeemInviteResponse: Decodable {
    let success: Bool
    let alreadyAllowed: Bool?
}

struct APIClient {
    let config: AppConfig
    let session: URLSession

    init(config: AppConfig, session: URLSession? = nil) {
        self.config = config
        self.session = session ?? Self.authenticatedSession
    }

    /// Las respuestas autenticadas no deben sobrevivir un cambio de cuenta ni
    /// reutilizar un asset autorizado para otro usuario desde el caché HTTP.
    private static let authenticatedSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }()

    func get<Response: Decodable>(_ path: String) async throws -> Response {
        try await request(path: path, method: .get, body: Optional<Data>.none)
    }

    func get<Response: Decodable>(_ path: String, headers: [String: String]) async throws -> Response {
        try await request(
            path: path,
            method: .get,
            body: Optional<Data>.none,
            additionalHeaders: headers
        )
    }

    func getData(
        _ path: String,
        headers: [String: String] = [:],
        maximumBytes: Int = 12_000_000
    ) async throws -> APIBinaryResponse {
        try await requestData(path: path, additionalHeaders: headers, maximumBytes: maximumBytes)
    }

    func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        let payload = try JSONEncoder().encode(body)
        return try await request(path: path, method: .post, body: payload)
    }

    func delete<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        let payload = try JSONEncoder().encode(body)
        return try await request(path: path, method: .delete, body: payload)
    }

    func postJSONObject(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        try await postJSONObject(path, body: body, forcingTokenRefresh: false)
    }

    private func postJSONObject(_ path: String, body: [String: Any], forcingTokenRefresh: Bool) async throws -> [String: Any] {
        guard JSONSerialization.isValidJSONObject(body) else { throw APIClientError.invalidResponse }
        guard let user = Auth.auth().currentUser else { throw APIClientError.missingUser }

        let token = try await user.fetchIDToken(forcingRefresh: forcingTokenRefresh)
        var request = URLRequest(
            url: try makeURL(path: path),
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        if http.statusCode == 401, !forcingTokenRefresh {
            return try await postJSONObject(path, body: body, forcingTokenRefresh: true)
        }
        guard (200..<300).contains(http.statusCode) else {
            let details = Self.extractError(from: data)
            throw APIClientError.requestFailed(
                status: http.statusCode,
                code: details.code,
                message: details.message ?? "Request failed with status \(http.statusCode).",
                retryAfter: Self.retryAfterSeconds(from: http)
            )
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIClientError.invalidResponse
        }
        return object
    }

    private func request<Response: Decodable>(
        path: String,
        method: HTTPMethod,
        body: Data?,
        forcingTokenRefresh: Bool = false,
        additionalHeaders: [String: String] = [:]
    ) async throws -> Response {
        guard let user = Auth.auth().currentUser else {
            throw APIClientError.missingUser
        }

        let token = try await user.fetchIDToken(forcingRefresh: forcingTokenRefresh)
        let url = try makeURL(path: path)
        var urlRequest = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )
        urlRequest.httpMethod = method.rawValue
        for (name, value) in additionalHeaders {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            urlRequest.httpBody = body
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        if http.statusCode == 401, !forcingTokenRefresh {
            return try await request(
                path: path,
                method: method,
                body: body,
                forcingTokenRefresh: true,
                additionalHeaders: additionalHeaders
            )
        }

        guard (200..<300).contains(http.statusCode) else {
            let details = Self.extractError(from: data)
            throw APIClientError.requestFailed(
                status: http.statusCode,
                code: details.code,
                message: details.message ?? "Request failed with status \(http.statusCode).",
                retryAfter: Self.retryAfterSeconds(from: http)
            )
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw APIClientError.invalidResponse
        }
    }

    private func requestData(
        path: String,
        forcingTokenRefresh: Bool = false,
        additionalHeaders: [String: String],
        maximumBytes: Int
    ) async throws -> APIBinaryResponse {
        guard let user = Auth.auth().currentUser else { throw APIClientError.missingUser }
        let token = try await user.fetchIDToken(forcingRefresh: forcingTokenRefresh)
        var request = URLRequest(
            url: try makeURL(path: path),
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )
        request.httpMethod = HTTPMethod.get.rawValue
        for (name, value) in additionalHeaders { request.setValue(value, forHTTPHeaderField: name) }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            bytes.task.cancel()
            throw APIClientError.invalidResponse
        }
        if http.statusCode == 401, !forcingTokenRefresh {
            bytes.task.cancel()
            return try await requestData(
                path: path,
                forcingTokenRefresh: true,
                additionalHeaders: additionalHeaders,
                maximumBytes: maximumBytes
            )
        }
        let responseLimit = (200..<300).contains(http.statusCode) ? maximumBytes : min(maximumBytes, 64_000)
        if response.expectedContentLength > Int64(responseLimit) {
            bytes.task.cancel()
            throw APIClientError.responseTooLarge(limit: responseLimit)
        }
        let data = try await collect(bytes, maximumBytes: responseLimit)
        guard (200..<300).contains(http.statusCode) else {
            let details = Self.extractError(from: data)
            throw APIClientError.requestFailed(
                status: http.statusCode,
                code: details.code,
                message: details.message ?? "Request failed with status \(http.statusCode).",
                retryAfter: Self.retryAfterSeconds(from: http)
            )
        }
        return APIBinaryResponse(data: data, mimeType: http.value(forHTTPHeaderField: "Content-Type"))
    }

    private func collect(_ bytes: URLSession.AsyncBytes, maximumBytes: Int) async throws -> Data {
        var data = Data()
        if bytes.task.response?.expectedContentLength ?? -1 > 0 {
            data.reserveCapacity(min(Int(bytes.task.response?.expectedContentLength ?? 0), maximumBytes))
        }
        for try await byte in bytes {
            guard data.count < maximumBytes else {
                bytes.task.cancel()
                throw APIClientError.responseTooLarge(limit: maximumBytes)
            }
            data.append(byte)
        }
        return data
    }

    private func makeURL(path: String) throws -> URL {
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard var components = URLComponents(url: config.backendBaseURL, resolvingAgainstBaseURL: false) else {
            throw APIClientError.invalidURL(path)
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, cleanPath].filter { !$0.isEmpty }.joined(separator: "/")

        guard let url = components.url else {
            throw APIClientError.invalidURL(path)
        }

        return url
    }

    private static func extractError(from data: Data) -> (message: String?, code: String?) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil)
        }
        let nestedError = object["error"] as? [String: Any]
        let rawMessage = nestedError?["message"] as? String
            ?? object["error"] as? String
            ?? object["message"] as? String
        let message = rawMessage?.isEmpty == false ? rawMessage : nil
        let rawCode = nestedError?["code"] as? String ?? object["code"] as? String
        let code = rawCode?.isEmpty == false ? rawCode : nil
        return (message, code)
    }

    private static func retryAfterSeconds(from response: HTTPURLResponse) -> Int? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

struct APIBinaryResponse {
    let data: Data
    let mimeType: String?
}

// MARK: - ExamForge (nuevo motor de pruebas y guías)

enum ExamForgeDocumentKind: String, Decodable, Hashable {
    case prueba
    case guia
}

enum ExamForgeStatus: String, Decodable, Hashable {
    case draft
    case ready
    case archived

    var label: String {
        switch self {
        case .draft: return "Borrador"
        case .ready: return "Lista"
        case .archived: return "Archivada"
        }
    }
}

struct ExamForgeIntegrationContext: Decodable, Hashable {
    /// Los primeros documentos del motor no siempre incluían este campo.
    /// La capa de lectura conserva compatibilidad y los trata como pruebas.
    let documentKind: ExamForgeDocumentKind?
    let courseId: String?
    let courseLabel: String?
    let subjectId: String?
    let subjectLabel: String?
    let unitId: String?
    let unitLabel: String?
    let evaluationType: String?
    let guideType: String?
}

struct ExamForgeSummaryMetadata: Decodable, Hashable {
    let durationMinutes: Int?
    let totalPoints: Double?
    let objectivesCount: Int
    let objectiveIds: [String]?
}

struct ExamForgeExamSummary: Decodable, Identifiable, Hashable {
    let id: String
    let workspaceId: String
    let title: String
    let status: ExamForgeStatus
    let schemaVersion: String
    let lockVersion: Int
    let currentRevision: Int
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?
    let integration: ExamForgeIntegrationContext?
    let metadata: ExamForgeSummaryMetadata

    var kind: ExamForgeDocumentKind { integration?.documentKind ?? .prueba }
}

enum ExamForgeJSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([ExamForgeJSONValue])
    case object([String: ExamForgeJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([ExamForgeJSONValue].self) { self = .array(value) }
        else if let value = try? container.decode([String: ExamForgeJSONValue].self) { self = .object(value) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Valor ExamForge no compatible") }
    }

    var objectValue: [String: ExamForgeJSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var arrayValue: [ExamForgeJSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var numberValue: Double? {
        guard case .number(let value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    /// Extrae texto solo desde nodos de rich text (`text`/`children`). No concatena
    /// ids, metadatos ni respuestas técnicas desconocidas.
    var richPlainText: String {
        switch self {
        case .string(let value):
            return value
        case .array(let values):
            return values.map(\.richPlainText).filter { !$0.isEmpty }.joined(separator: "\n")
        case .object(let value):
            let type = value["type"]?.stringValue
            if type == "hardBreak" { return "\n" }
            if let text = value["text"]?.stringValue { return text }
            guard let children = value["children"]?.arrayValue else { return "" }
            switch type {
            case "paragraph", "heading":
                return children.map(\.richPlainText).joined()
            case "bulletList":
                return children.map { "• \($0.richPlainText)" }.joined(separator: "\n")
            case "orderedList":
                return children.enumerated().map { "\($0.offset + 1). \($0.element.richPlainText)" }.joined(separator: "\n")
            default:
                return children.map(\.richPlainText).filter { !$0.isEmpty }.joined(separator: "\n")
            }
        case .number, .bool, .null:
            return ""
        }
    }
}

struct ExamForgeObjective: Decodable, Identifiable {
    let id: String
    let text: String
}

struct ExamForgeDocumentMetadata: Decodable {
    let id: String
    let title: String
    let subtitle: String?
    let subject: String?
    let course: String?
    let teacher: String?
    let date: String?
    let durationMinutes: Int?
    let totalPoints: Double?
    let objectives: [ExamForgeObjective]
    let instructions: ExamForgeJSONValue
}

struct ExamForgeBlock: Decodable, Identifiable {
    let id: String
    let type: String
    let data: ExamForgeJSONValue
}

struct ExamForgeRegion: Decodable {
    let id: String
    let enabled: Bool?
    let blocks: [ExamForgeBlock]
}

struct ExamForgeRegions: Decodable {
    let header: ExamForgeRegion
    let body: ExamForgeRegion
    let footer: ExamForgeRegion
}

struct ExamForgeDocument: Decodable {
    let schemaVersion: String
    let documentId: String
    let locale: String
    let metadata: ExamForgeDocumentMetadata
    let regions: ExamForgeRegions
}

struct ExamForgeExamRecord: Decodable, Identifiable {
    let id: String
    let workspaceId: String
    let title: String
    let status: ExamForgeStatus
    let schemaVersion: String
    let document: ExamForgeDocument
    let lockVersion: Int
    let currentRevision: Int
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?
}

enum ExamForgeAvailability {
    case disabled
    case enabled([ExamForgeExamSummary])
}

struct ExamForgeRepository {
    let apiClient: APIClient

    func loadActiveDocuments(schoolID: String?) async throws -> ExamForgeAvailability {
        let access: ExamForgeEnvelope<ExamForgeAccessData> = try await apiClient.get(
            "/api/examforge/access",
            headers: headers(schoolID: schoolID)
        )
        guard access.data.enabled else { return .disabled }

        let documents: ExamForgeEnvelope<[ExamForgeExamSummary]> = try await apiClient.get(
            "/api/examforge/v1/exams",
            headers: headers(schoolID: schoolID)
        )
        return .enabled(documents.data)
    }

    func loadDocument(id: String, schoolID: String?) async throws -> ExamForgeExamRecord {
        let cleanID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty, !cleanID.contains("/") else {
            throw APIClientError.invalidURL("/api/examforge/v1/exams/\(id)")
        }
        let response: ExamForgeEnvelope<ExamForgeExamRecord> = try await apiClient.get(
            "/api/examforge/v1/exams/\(cleanID)",
            headers: headers(schoolID: schoolID)
        )
        return response.data
    }

    func loadAsset(id: String, schoolID: String?) async throws -> APIBinaryResponse {
        let cleanID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty, !cleanID.contains("/") else {
            throw APIClientError.invalidURL("/api/examforge/v1/assets/\(id)")
        }
        return try await apiClient.getData(
            "/api/examforge/v1/assets/\(cleanID)",
            headers: headers(schoolID: schoolID)
        )
    }

    private func headers(schoolID: String?) -> [String: String] {
        let clean = schoolID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !clean.isEmpty, !clean.contains("/") else { return [:] }
        return ["x-edupanel-school-id": clean]
    }
}

private struct ExamForgeEnvelope<Value: Decodable>: Decodable {
    let data: Value
}

private struct ExamForgeAccessData: Decodable {
    let mode: String
    let enabled: Bool
}

private extension User {
    func fetchIDToken(forcingRefresh: Bool = false) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            getIDTokenForcingRefresh(forcingRefresh) { token, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let token {
                    continuation.resume(returning: token)
                } else {
                    continuation.resume(throwing: APIClientError.missingUser)
                }
            }
        }
    }
}
