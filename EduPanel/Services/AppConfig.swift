import Foundation

enum AppConfigurationIssue: Error, Equatable {
    case missingFirebasePlist
    case missingAPIBaseURL
    case invalidAPIBaseURL(String)

    var message: String {
        switch self {
        case .missingFirebasePlist:
            return "Falta GoogleService-Info.plist. Agregalo en EduPanel/Resources y marca target membership EduPanel."
        case .missingAPIBaseURL:
            return "Falta EDUPANEL_API_BASE_URL. Configuralo en Config/Shared.xcconfig con la URL HTTPS de Vercel."
        case .invalidAPIBaseURL(let value):
            return "EDUPANEL_API_BASE_URL no es valida: \(value)"
        }
    }
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

        return .success(AppConfig(backendBaseURL: url))
    }
}
