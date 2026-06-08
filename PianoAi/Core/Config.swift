import Foundation

enum Config {
    #if DEBUG
    static let baseURL = URL(string: "http://127.0.0.1:8000")!
    #else
    static let baseURL = URL(string: "https://api.pianoai.com")!
    #endif
}
