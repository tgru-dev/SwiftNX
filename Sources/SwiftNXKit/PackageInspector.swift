import Foundation

public enum PackageFileKind: String, Codable, Sendable, CaseIterable {
    case nsp
    case xci
    case nsz
    case xcz

    public init?(url: URL) {
        self.init(rawValue: url.pathExtension.lowercased())
    }

    public var displayName: String { rawValue.uppercased() }
    public var isCompressed: Bool { self == .nsz || self == .xcz }

    public var isContainer: Bool { self == .nsp || self == .xci || isCompressed }
}

public enum DetectionSource: String, Codable, Sendable {
    case content
    case filename
    case none
}

/// What SwiftNX can learn about a game file without decrypting it.
///
/// nxnative itself resolves the authoritative values from the control data and
/// ticket while building; this metadata is used for the wizard, the profile
/// lookup and a stable working-folder name.
public struct InspectedPackage: Equatable, Sendable {
    public let url: URL
    public let kind: PackageFileKind
    public let titleID: TitleID?
    public let version: UInt64?
    public let detectionSource: DetectionSource
    public let fileSize: Int64
    public let contentMetaTitleIDs: [TitleID]
    public let note: String?

    public init(
        url: URL,
        kind: PackageFileKind,
        titleID: TitleID?,
        version: UInt64?,
        detectionSource: DetectionSource,
        fileSize: Int64,
        contentMetaTitleIDs: [TitleID] = [],
        note: String? = nil
    ) {
        self.url = url
        self.kind = kind
        self.titleID = titleID
        self.version = version
        self.detectionSource = detectionSource
        self.fileSize = fileSize
        self.contentMetaTitleIDs = contentMetaTitleIDs
        self.note = note
    }

    public var displayName: String {
        PackageInspector.displayName(for: url)
    }

    public var fileExtension: String { url.pathExtension.lowercased() }
}

public enum PackageInspector {
    /// Inspects an NSP/XCI/NSZ/XCZ without needing `prod.keys`.
    ///
    /// NSP files are PFS0 archives. Their content-meta NCA is named after the
    /// title ID, which is the only title-related metadata readable without
    /// decrypting anything. XCI files keep their content in the secure HFS0
    /// partition; SwiftNX falls back to the conventional `[TITLEID]` filename
    /// tag for those (and for compressed NSZ/XCZ files).
    public static func inspect(url: URL) -> InspectedPackage {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        guard let kind = PackageFileKind(url: url) else {
            return InspectedPackage(
                url: url, kind: .nsp, titleID: nil, version: nil,
                detectionSource: .none, fileSize: size,
                note: "Not an NSP, XCI, NSZ or XCZ file."
            )
        }

        let filenameID = TitleID.extract(fromFilename: url.lastPathComponent)
        let filenameVersion = TitleID.extractVersion(fromFilename: url.lastPathComponent)
        var contentIDs: [TitleID] = []
        var note: String?

        if !kind.isCompressed {
            do {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let prefix = try handle.read(upToCount: 0x200) ?? Data()

                if let nspIDs = try parsePFS0TitleIDs(handle: handle, prefix: prefix), !nspIDs.isEmpty {
                    contentIDs = nspIDs
                } else if isXCI(prefix: prefix) {
                    // The secure partition is encrypted HFS0; without keys the
                    // clean title ID is normally the one in the file name.
                    note = "XCI detected. The title ID comes from the file name when it carries one."
                } else if prefix.count >= 4 {
                    note = "Could not read an NSP (PFS0) header from this file."
                }
            } catch {
                note = "Could not read the file: \(error.localizedDescription)"
            }
        } else {
            note = "\(kind.displayName) is compressed; the title ID comes from the file name."
        }

        let chosenContentID = contentIDs.first(where: { $0.isUpdate }) ?? contentIDs.first
        let titleID = chosenContentID ?? filenameID
        let source: DetectionSource = chosenContentID != nil ? .content : (filenameID != nil ? .filename : .none)
        if titleID == nil, note == nil {
            note = "No title ID found. nxnative will resolve it while building; the profile lookup may be unavailable."
        }

        return InspectedPackage(
            url: url,
            kind: kind,
            titleID: titleID,
            version: filenameVersion,
            detectionSource: source,
            fileSize: size,
            contentMetaTitleIDs: contentIDs,
            note: note
        )
    }

    public static func displayName(for url: URL) -> String {
        var name = url.deletingPathExtension().lastPathComponent
        name = name.replacingOccurrences(
            of: "\\[[^\\]]*\\]",
            with: " ",
            options: .regularExpression
        )
        name = name.replacingOccurrences(
            of: "\\([^)]*(?:USA|Europe|Japan|Asia|EUR|JPN|v[0-9]+)[^)]*\\)",
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        name = name.replacingOccurrences(of: "_", with: " ")
        name = name.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        name = name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-–—.")))
        return name.isEmpty ? url.deletingPathExtension().lastPathComponent : name
    }

    static func isXCI(prefix: Data) -> Bool {
        guard prefix.count >= 0x104 else { return false }
        let magicRange = 0x100..<0x104
        return String(data: prefix.subdata(in: magicRange), encoding: .ascii) == "HEAD"
    }

    struct PFS0Entry: Equatable {
        let name: String
        let offset: UInt64
        let size: UInt64
    }

    /// Parses the PFS0 header at the start of `handle` and returns all
    /// content-meta title IDs (the `<titleid>.cnmt.nca` entries).
    static func parsePFS0TitleIDs(handle: FileHandle, prefix: Data) throws -> [TitleID]? {
        guard prefix.count >= 16 else { return nil }
        let magic = String(data: prefix.subdata(in: 0..<4), encoding: .ascii)
        guard magic == "PFS0" else { return nil }

        func u32(_ data: Data, _ offset: Int) -> UInt32 {
            data.withUnsafeBytes { raw in
                let value = raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
                return UInt32(littleEndian: value)
            }
        }

        let count = Int(u32(prefix, 4))
        let stringTableSize = Int(u32(prefix, 8))
        guard count > 0, count <= 16_384,
              stringTableSize >= 0, stringTableSize <= 64 * 1024 * 1024
        else { return nil }

        let tableSize = count * 24 + stringTableSize
        guard tableSize <= 128 * 1024 * 1024 else { return nil }
        try handle.seek(toOffset: 16)
        guard let table = try handle.read(upToCount: tableSize), table.count == tableSize else {
            return nil
        }

        let strings = table.subdata(in: (count * 24)..<(count * 24 + stringTableSize))
        var ids: [TitleID] = []
        var seen = Set<TitleID>()

        for index in 0..<count {
            let entryOffset = index * 24
            let nameOffset = Int(u32(table, entryOffset + 16))
            guard nameOffset >= 0, nameOffset < strings.count else { continue }
            let nameBytes = strings.subdata(in: nameOffset..<strings.count)
            let name = String(decoding: nameBytes.prefix(while: { $0 != 0 }), as: UTF8.self)
            guard name.lowercased().hasSuffix(".cnmt.nca") else { continue }
            let base = String(name.dropLast(".cnmt.nca".count))
            guard base.count == 16, let id = TitleID(hex: base), !seen.contains(id) else { continue }
            seen.insert(id)
            ids.append(id)
        }
        return ids
    }

    /// Exposed for tests and diagnostics.
    public static func pfs0Entries(at url: URL) throws -> [String] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let prefix = try handle.read(upToCount: 16) ?? Data()
        guard prefix.count >= 16,
              String(data: prefix.subdata(in: 0..<4), encoding: .ascii) == "PFS0"
        else { return [] }

        func u32(_ data: Data, _ offset: Int) -> UInt32 {
            data.withUnsafeBytes { raw in
                UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
            }
        }
        let count = Int(u32(prefix, 4))
        let stringTableSize = Int(u32(prefix, 8))
        guard count > 0, count <= 16_384, stringTableSize <= 64 * 1024 * 1024 else { return [] }
        let tableSize = count * 24 + stringTableSize
        try handle.seek(toOffset: 16)
        guard let table = try handle.read(upToCount: tableSize), table.count == tableSize else { return [] }
        let strings = table.subdata(in: (count * 24)..<(count * 24 + stringTableSize))
        return (0..<count).compactMap { index in
            let nameOffset = Int(u32(table, index * 24 + 16))
            guard nameOffset >= 0, nameOffset < strings.count else { return nil }
            let nameBytes = strings.subdata(in: nameOffset..<strings.count)
            let name = String(decoding: nameBytes.prefix(while: { $0 != 0 }), as: UTF8.self)
            return name.isEmpty ? nil : name
        }
    }
}
