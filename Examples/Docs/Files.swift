// docs: patterns/files

import Foundation
import IntrospectionSDK

enum Files {
    static func sdkUpload(runner: Runner, fileId: String) async throws {
        let contract = Data()
        // #region docs:patterns/files/sdk-upload
        let f = try await runner.files.upload(FileUpload(data: contract, filename: "contract.pdf", fileType: .upload))
        let handle = try await runner.tasks.start(prompt: "Review contract.pdf", TaskCreate(files: [TaskFileRef(id: f.id)]))
        let bytes = try await runner.files.download(fileId)
        // #endregion docs:patterns/files/sdk-upload
        _ = (handle, bytes)
    }
}
