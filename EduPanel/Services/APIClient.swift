import Foundation
import FirebaseAuth

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
}

enum APIClientError: LocalizedError {
    case missingUser
    case invalidURL(String)
    case requestFailed(status: Int, message: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingUser:
            return "No hay una sesión activa."
        case .invalidURL(let path):
            return "Ruta API invalida: \(path)"
        case .requestFailed(_, let message):
            return message
        case .invalidResponse:
            return "Respuesta invalida del servidor."
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

    init(config: AppConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func get<Response: Decodable>(_ path: String) async throws -> Response {
        try await request(path: path, method: .get, body: Optional<Data>.none)
    }

    func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        let payload = try JSONEncoder().encode(body)
        return try await request(path: path, method: .post, body: payload)
    }

    func postJSONObject(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        guard JSONSerialization.isValidJSONObject(body) else { throw APIClientError.invalidResponse }
        guard let user = Auth.auth().currentUser else { throw APIClientError.missingUser }

        let token = try await user.fetchIDToken()
        var request = URLRequest(url: try makeURL(path: path))
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = Self.extractErrorMessage(from: data) ?? "Request failed with status \(http.statusCode)."
            throw APIClientError.requestFailed(status: http.statusCode, message: message)
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIClientError.invalidResponse
        }
        return object
    }

    private func request<Response: Decodable>(path: String, method: HTTPMethod, body: Data?) async throws -> Response {
        guard let user = Auth.auth().currentUser else {
            throw APIClientError.missingUser
        }

        let token = try await user.fetchIDToken()
        let url = try makeURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = Self.extractErrorMessage(from: data) ?? "Request failed with status \(http.statusCode)."
            throw APIClientError.requestFailed(status: http.statusCode, message: message)
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw APIClientError.invalidResponse
        }
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

    private static func extractErrorMessage(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let value = object["error"] as? String ?? object["message"] as? String,
            !value.isEmpty
        else {
            return nil
        }
        return value
    }
}

private extension User {
    func fetchIDToken() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            getIDToken { token, error in
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
