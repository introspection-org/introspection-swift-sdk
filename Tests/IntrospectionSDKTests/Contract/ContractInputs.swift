import Foundation

@testable import IntrospectionSDK

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension OpenAPIDocument {
    /// The file named by `environmentKey` when set, otherwise the document at `url`.
    static func load(plane: String, environmentKey: String, url: String) async throws -> OpenAPIDocument {
        let data: Data
        let source: String
        if let path = ProcessInfo.processInfo.environment[environmentKey], !path.isEmpty {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
            source = path
        } else {
            data = try await fetch(URL(string: url)!)
            source = url
        }
        return try parse(plane: plane, data: data, source: source)
    }

    static func parse(plane: String, data: Data, source: String) throws -> OpenAPIDocument {
        guard case let .object(document) = try JSONCoding.decoder.decode(JSONValue.self, from: data) else {
            throw IntrospectionError(kind: .decoding, message: "\(source) is not a JSON object")
        }
        return OpenAPIDocument(plane: plane, document: document, source: source)
    }

    private static func fetch(_ url: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
                    continuation.resume(throwing: IntrospectionError(kind: .network, message: "\(url) answered \(status)"))
                } else {
                    continuation.resume(returning: data ?? Data())
                }
            }.resume()
        }
    }
}

extension SwiftTypeIndex {
    /// Every `.swift` file under `Sources`, paths relative to the repository root.
    static func sources(root: URL) throws -> SwiftTypeIndex {
        let directory = root.appendingPathComponent("Sources")
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        var paths: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "swift" { paths.append(url) }
        }
        let files = try paths.sorted { $0.path < $1.path }.map { url in
            let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
            return SwiftFile(path: relative, source: try String(contentsOf: url, encoding: .utf8))
        }
        return SwiftTypeIndex(files: files)
    }
}

extension ContractCheck {
    /// Check `index` against `documents` and return the report.
    static func run(documents: [OpenAPIDocument], index: SwiftTypeIndex) -> ContractReport {
        var check = ContractCheck(documents: documents, sites: CallSiteScanner(index: index).scan())
        return check.run()
    }
}
