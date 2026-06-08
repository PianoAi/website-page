import Foundation

enum APIError: LocalizedError {
    case unauthorized
    case forbidden
    case notFound
    case serverError(Int, String?)
    case decodingFailed(Error)
    case network(Error)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unauthorized:            return "登录已过期，请重新登录"
        case .forbidden:               return "权限不足"
        case .notFound:                return "资源不存在"
        case .serverError(_, let msg): return msg ?? "服务器错误"
        case .decodingFailed(let e):   return "数据解析失败：\(e.localizedDescription)"
        case .network(let e):          return e.localizedDescription
        case .invalidResponse:         return "无效的服务器响应"
        }
    }
}

private struct ErrorDetail: Decodable { let detail: String }
