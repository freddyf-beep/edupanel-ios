import Foundation

enum AppConfigurationIssue: LocalizedError, Equatable {
    case missingFirebasePlist
    case missingAPIBaseURL
    case invalidAPIBaseURL(String)
    case insecureAPIBaseURL(String)
    case localAPIUnavailableOnDevice

    var message: String {
        switch self {
        case .missingFirebasePlist:
            return "Falta GoogleService-Info.plist. Agregalo en EduPanel/Resources y marca target membership EduPanel."
        case .missingAPIBaseURL:
            return "Falta EDUPANEL_API_BASE_URL. Configura el build con la URL HTTPS accesible del backend."
        case .invalidAPIBaseURL(let value):
            return "EDUPANEL_API_BASE_URL no es valida: \(value)"
        case .insecureAPIBaseURL(let value):
            return "El backend debe usar HTTPS fuera del Simulator: \(value)"
        case .localAPIUnavailableOnDevice:
            return "127.0.0.1 apunta a este iPhone, no al Mac. Configura una URL HTTPS accesible para probar QR en el dispositivo."
        }
    }

    var errorDescription: String? { message }
}

struct AppConfig: Equatable {
    let backendBaseURL: URL

    static func load() -> Result<AppConfig, AppConfigurationIssue> {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "EDUPANEL_API_BASE_URL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !raw.isEmpty, !raw.contains("REPLACE_ME"), raw != "$(EDUPANEL_API_BASE_URL)" else {
            return .failure(.missingAPIBaseURL)
        }

        guard let url = URL(string: raw), let scheme = url.scheme, scheme == "https" || scheme == "http", url.host != nil else {
            return .failure(.invalidAPIBaseURL(raw))
        }

#if !targetEnvironment(simulator)
        let localHosts = ["localhost", "127.0.0.1", "::1"]
        if localHosts.contains(url.host?.lowercased() ?? "") {
            return .failure(.localAPIUnavailableOnDevice)
        }
        if url.scheme != "https" {
            return .failure(.insecureAPIBaseURL(raw))
        }
#endif

        return .success(AppConfig(backendBaseURL: url))
    }
}
