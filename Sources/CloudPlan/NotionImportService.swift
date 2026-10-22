import Foundation

struct NotionImportFile: Codable, Equatable, Identifiable {
    var name: String
    var content: String

    var id: String { name }
}

struct NotionImportPayload: Equatable {
    var files: [NotionImportFile]

    var characterCount: Int { files.reduce(0) { $0 + $1.content.count } }
    var sourceMaterial: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(files) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }
}

enum NotionImportError: LocalizedError {
    case unsupportedFile(String)
    case unreadableFile(String)
    case fileTooLarge(String)
    case totalTooLarge
    case empty

    var errorDescription: String? {
        switch self {
        case .unsupportedFile(let name): return "“\(name)”不是支持的 Notion 导出文件。请选择 CSV、Markdown 或文本文件。"
        case .unreadableFile(let name): return "无法读取“\(name)”，请先确认文件已经从 Notion 导出并解压。"
        case .fileTooLarge(let name): return "“\(name)”过大。单个导入文件不能超过 2 MB。"
        case .totalTooLarge: return "这批 Notion 内容过多，请分几次导入。"
        case .empty: return "没有读到可导入的 Notion 内容。"
        }
    }
}

enum NotionImportService {
    static let supportedExtensions = Set(["csv", "md", "markdown", "txt"])
    static let maximumFileBytes = 2 * 1_024 * 1_024
    static let maximumCharacters = 180_000

    static func load(urls: [URL]) throws -> NotionImportPayload {
        var files: [NotionImportFile] = []
        var totalCharacters = 0

        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = url.lastPathComponent
            guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
                throw NotionImportError.unsupportedFile(name)
            }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            guard let data = try? Data(contentsOf: url), data.count <= maximumFileBytes else {
                if let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
                   let size = values.fileSize, size > maximumFileBytes {
                    throw NotionImportError.fileTooLarge(name)
                }
                throw NotionImportError.unreadableFile(name)
            }
            guard var content = String(data: data, encoding: .utf8) else {
                throw NotionImportError.unreadableFile(name)
            }
            content = content
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }
            totalCharacters += content.count
            guard totalCharacters <= maximumCharacters else { throw NotionImportError.totalTooLarge }
            files.append(NotionImportFile(name: name, content: content))
        }

        guard !files.isEmpty else { throw NotionImportError.empty }
        return NotionImportPayload(files: files)
    }
}
