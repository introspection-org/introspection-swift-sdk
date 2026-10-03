import Foundation

/// Query parameters, built in order. Nil values are skipped and arrays expand
/// into repeated keys, matching the API's list filters.
public struct Query: Sendable, Equatable {
    public private(set) var items: [URLQueryItem] = []

    public init() {}

    public mutating func add(_ name: String, _ value: String?) {
        if let value { items.append(URLQueryItem(name: name, value: value)) }
    }

    public mutating func add(_ name: String, _ value: Int?) {
        add(name, value.map(String.init))
    }

    public mutating func add(_ name: String, _ value: Double?) {
        add(name, value.map { String($0) })
    }

    public mutating func add(_ name: String, _ value: Bool?) {
        add(name, value.map { $0 ? "true" : "false" })
    }

    public mutating func add(_ name: String, _ value: Date?) {
        add(name, value.map(ISO8601.format))
    }

    public mutating func add<Value: RawRepresentable>(_ name: String, _ value: Value?) where Value.RawValue == String {
        add(name, value?.rawValue)
    }

    public mutating func add(_ name: String, _ values: [String]?) {
        for value in values ?? [] { items.append(URLQueryItem(name: name, value: value)) }
    }

    public mutating func add<Value: RawRepresentable>(_ name: String, _ values: [Value]?) where Value.RawValue == String {
        add(name, values?.map(\.rawValue))
    }

    /// Replace any existing value for `name`.
    public mutating func set(_ name: String, _ value: String?) {
        items.removeAll { $0.name == name }
        add(name, value)
    }

    public func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
}

/// A request body.
public enum RequestBody: Sendable {
    case none
    case json(Data)
    case form([(String, String)])
    case multipart(MultipartFormData)
    case raw(Data, contentType: String)

    /// Encode an `Encodable` value as a JSON body.
    public static func encode<T: Encodable>(_ value: T) throws -> RequestBody {
        do {
            return .json(try JSONCoding.encoder.encode(value))
        } catch {
            throw IntrospectionError(kind: .invalidRequest, message: "Could not encode request: \(error)", underlying: error)
        }
    }

    var isMultipart: Bool {
        if case .multipart = self { return true }
        return false
    }

    func encoded() -> (Data?, String?) {
        switch self {
        case .none: return (nil, nil)
        case let .json(data): return (data, "application/json")
        case let .form(fields):
            let body = fields.map { "\(formEncode($0.0))=\(formEncode($0.1))" }.joined(separator: "&")
            return (Data(body.utf8), "application/x-www-form-urlencoded")
        case let .multipart(form): return (form.data, form.contentType)
        case let .raw(data, contentType): return (data, contentType)
        }
    }
}

/// `application/x-www-form-urlencoded` component encoding.
func formEncode(_ value: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return (value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value).replacingOccurrences(of: "%20", with: "+")
}

/// Percent-encode one path segment, so an id can never change the route.
public func pathSegment(_ value: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

/// A `multipart/form-data` body.
public struct MultipartFormData: Sendable {
    public let boundary: String
    private var parts = Data()

    public init(boundary: String = "introspection-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    public mutating func append(name: String, value: String) {
        parts.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(Self.escape(name))\"\r\n\r\n".utf8))
        parts.append(Data(value.utf8))
        parts.append(Data("\r\n".utf8))
    }

    public mutating func append(name: String, filename: String, contentType: String, data: Data) {
        parts.append(
            Data(
                "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(Self.escape(name))\"; filename=\"\(Self.escape(filename))\"\r\nContent-Type: \(contentType)\r\n\r\n"
                    .utf8
            ))
        parts.append(data)
        parts.append(Data("\r\n".utf8))
    }

    public var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    public var data: Data {
        var body = parts
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
    }
}

/// A MIME type for a filename, by extension.
public func mimeType(forFilename filename: String) -> String {
    let ext = (filename as NSString).pathExtension.lowercased()
    let types: [String: String] = [
        "txt": "text/plain", "md": "text/markdown", "json": "application/json", "csv": "text/csv",
        "html": "text/html", "htm": "text/html", "xml": "application/xml", "yaml": "application/yaml",
        "yml": "application/yaml", "pdf": "application/pdf", "png": "image/png", "jpg": "image/jpeg",
        "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp", "heic": "image/heic", "svg": "image/svg+xml",
        "zip": "application/zip", "doc": "application/msword",
        "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "xls": "application/vnd.ms-excel",
        "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "ppt": "application/vnd.ms-powerpoint",
        "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "mp3": "audio/mpeg", "m4a": "audio/mp4", "wav": "audio/wav", "mp4": "video/mp4", "mov": "video/quicktime",
    ]
    return types[ext] ?? "application/octet-stream"
}
