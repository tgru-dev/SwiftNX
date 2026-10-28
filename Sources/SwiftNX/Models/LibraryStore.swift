import Foundation
import SwiftNXKit

struct LibraryEntry: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var titleID: String?
    var version: String?
    var path: String
    var builtAt: Date
    var profileName: String?
    var language: String?
    var bundleIdentifier: String?

    init(
        id: UUID = UUID(),
        title: String,
        titleID: String?,
        version: String?,
        path: String,
        builtAt: Date = Date(),
        profileName: String? = nil,
        language: String? = nil,
        bundleIdentifier: String? = nil
    ) {
        self.id = id
        self.title = title
        self.titleID = titleID
        self.version = version
        self.path = path
        self.builtAt = builtAt
        self.profileName = profileName
        self.language = language
        self.bundleIdentifier = bundleIdentifier
    }

    var url: URL { URL(fileURLWithPath: path) }
    var exists: Bool { FileManager.default.fileExists(atPath: path) }
    var titleIDObject: TitleID? { titleID.flatMap(TitleID.init(hex:)) }
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var entries: [LibraryEntry] = []

    private let fileURL: URL

    init(fileURL: URL = AppPaths.libraryFile) {
        self.fileURL = fileURL
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            entries = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([LibraryEntry].self, from: data))?
            .sorted { $0.builtAt > $1.builtAt } ?? []
    }

    func upsert(_ entry: LibraryEntry) {
        if let index = entries.firstIndex(where: {
            $0.path == entry.path || ($0.titleID != nil && $0.titleID == entry.titleID)
        }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        entries.sort { $0.builtAt > $1.builtAt }
        persist()
    }

    func remove(_ entry: LibraryEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    func removeMissing() {
        entries.removeAll { !$0.exists }
        persist()
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
