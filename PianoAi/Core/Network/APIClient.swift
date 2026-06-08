import Foundation
import UIKit

final class APIClient {
    static let shared = APIClient()

    private let session: URLSession

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase

        // Support FastAPI's ISO8601 output (with or without fractional seconds)
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let noFrac = ISO8601DateFormatter()
        noFrac.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let d = withFrac.date(from: s) { return d }
            if let d = noFrac.date(from: s)   { return d }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Invalid date: \(s)"
            )
        }
        return d
    }()

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Core request

    func send<T: Decodable>(_ endpoint: Endpoint, token: String? = nil) async throws -> T {
        var request = URLRequest(url: endpoint.url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            Locale.preferredLanguages.prefix(3).joined(separator: ", "),
            forHTTPHeaderField: "Accept-Language"
        )
        // 设备信息 Header（后端用于会话管理和登录通知邮件）
        request.setValue(UIDevice.current.name, forHTTPHeaderField: "X-Device-Name")
        request.setValue(
            "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            forHTTPHeaderField: "X-Platform"
        )
        // 当前会话 ID（用于标记活跃会话）
        if let sid = Keychain.load(for: .sessionId) {
            request.setValue(sid, forHTTPHeaderField: "X-Session-ID")
        }

        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body = endpoint.bodyData {
            request.httpBody = body
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch http.statusCode {
        case 200...299:
            if T.self == EmptyResponse.self {
                return EmptyResponse() as! T
            }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decodingFailed(error)
            }
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        default:
            let detail = try? decoder.decode(DetailError.self, from: data)
            throw APIError.serverError(http.statusCode, detail?.detail)
        }
    }
}

// MARK: - Helpers

struct EmptyResponse: Decodable {}
private struct DetailError: Decodable { let detail: String }
