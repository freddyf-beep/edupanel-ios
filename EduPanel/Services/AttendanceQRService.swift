import Foundation

protocol AttendanceQRResolving {
    func resolve(
        payload: String,
        scope: AttendanceDataScope,
        course: String
    ) async throws -> AttendanceQRResolveResponse
}

struct AttendanceQRAPIResolver: AttendanceQRResolving {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func resolve(
        payload: String,
        scope: AttendanceDataScope,
        course: String
    ) async throws -> AttendanceQRResolveResponse {
        do {
            let request = AttendanceQRResolveRequest(
                payload: payload,
                schoolId: scope.schoolID,
                yearId: scope.yearID,
                course: course
            )
            return try await client.post("/api/asistencia/qr/resolve", body: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                throw AttendanceQRFailure.offline
            case .timedOut:
                throw AttendanceQRFailure.timeout
            case .cancelled:
                throw CancellationError()
            default:
                throw AttendanceQRFailure.server
            }
        } catch let error as APIClientError {
            throw Self.map(error)
        } catch let error as AttendanceQRFailure {
            throw error
        } catch {
            throw AttendanceQRFailure.server
        }
    }

    static func map(_ error: APIClientError) -> AttendanceQRFailure {
        guard case .requestFailed(let status, let code, _, let retryAfter) = error else {
            if case .missingUser = error { return .sessionExpired }
            return .server
        }

        switch (status, code) {
        case (400, "INVALID_PAYLOAD"):
            return .invalidQRCode
        case (401, _):
            return .sessionExpired
        case (403, "CREDENTIAL_REVOKED"):
            return .revoked
        case (403, _):
            return .forbidden
        case (409, "STALE_CREDENTIAL"):
            return .stale
        case (409, "SCOPE_MISMATCH"):
            return .scopeMismatch
        case (409, "STUDENT_NOT_IN_ROSTER"):
            return .studentNotInRoster
        case (429, "RATE_LIMITED"), (429, _):
            return .rateLimited(seconds: retryAfter)
        case (503, "CONFIGURATION_ERROR"):
            return .configuration
        case (503, "RATE_LIMIT_UNAVAILABLE"), (503, _):
            return .temporarilyUnavailable
        default:
            return .server
        }
    }
}

#if DEBUG
struct AttendanceQRPreviewResolver: AttendanceQRResolving {
    func resolve(
        payload: String,
        scope: AttendanceDataScope,
        course: String
    ) async throws -> AttendanceQRResolveResponse {
        try await Task.sleep(for: .milliseconds(550))
        let studentID = payload == "preview-exception" ? "est_3" : "est_4"
        return AttendanceQRResolveResponse(
            studentId: studentID,
            studentName: studentID == "est_3" ? "Catalina Muñoz" : "Diego Contreras",
            credentialId: "preview-credential-\(studentID)"
        )
    }
}
#endif
