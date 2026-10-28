import XCTest
@testable import SwiftNXKit

final class TitleIDTests: XCTestCase {
    func testParsesHexAndClassifiesUpdates() throws {
        let base = try XCTUnwrap(TitleID(hex: "010015100B514000"))
        XCTAssertEqual(base.hex, "010015100B514000")
        XCTAssertTrue(base.isBase)
        XCTAssertFalse(base.isUpdate)
        XCTAssertEqual(base.baseID, base)

        let update = try XCTUnwrap(TitleID(hex: "010015100B514800"))
        XCTAssertTrue(update.isUpdate)
        XCTAssertEqual(update.baseID, base)
    }

    func testExtractsFromCommonFilenames() {
        XCTAssertEqual(
            TitleID.extract(fromFilename: "Super Mario Bros. Wonder [010015100B514000][v0].nsp"),
            TitleID(value: 0x010015100B514000)
        )
        XCTAssertEqual(
            TitleID.extractVersion(fromFilename: "Super Mario Bros. Wonder [010015100B514800][v327680].nsp"),
            327_680
        )
    }

    func testRejectsInvalidHex() {
        XCTAssertNil(TitleID(hex: "1234"))
        XCTAssertNil(TitleID(hex: "ZZZZZZZZZZZZZZZZ"))
    }
}

final class PackageInspectorTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftNXTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    private func makePFS0(names: [String], at url: URL) throws {
        var stringTable = Data()
        var entries = Data()
        for name in names {
            let offset = UInt32(stringTable.count)
            stringTable.append(name.data(using: .utf8)!)
            stringTable.append(0)
            entries.append(contentsOf: withUnsafeBytes(of: UInt64(0).littleEndian) { Data($0) })
            entries.append(contentsOf: withUnsafeBytes(of: UInt64(0).littleEndian) { Data($0) })
            entries.append(contentsOf: withUnsafeBytes(of: offset.littleEndian) { Data($0) })
            entries.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Data($0) })
        }
        var data = Data("PFS0".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(names.count).littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(stringTable.count).littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Data($0) })
        data.append(entries)
        data.append(stringTable)
        try data.write(to: url)
    }

    func testReadsContentMetaTitleIDFromNSP() throws {
        let url = temporaryDirectory.appendingPathComponent("Wonder [010015100b514000][v0].nsp")
        try makePFS0(names: [
            "010015100b514000.cnmt.nca",
            "abcdef.nca",
            "010015100b514000.tik",
        ], at: url)

        let inspected = PackageInspector.inspect(url: url)
        XCTAssertEqual(inspected.titleID, TitleID(value: 0x010015100B514000))
        XCTAssertEqual(inspected.detectionSource, .content)
        XCTAssertEqual(inspected.kind, .nsp)
        XCTAssertEqual(inspected.version, 0)
    }

    func testUpdateNSPDetection() throws {
        let url = temporaryDirectory.appendingPathComponent("Wonder update.nsp")
        try makePFS0(names: [
            "010015100b514800.cnmt.nca",
            "another.nca",
        ], at: url)

        let inspected = PackageInspector.inspect(url: url)
        XCTAssertEqual(inspected.titleID?.isUpdate, true)
        XCTAssertEqual(inspected.titleID?.baseID, TitleID(value: 0x010015100B514000))
    }

    func testFilenameFallbackForCompressedFile() throws {
        let url = temporaryDirectory.appendingPathComponent("Game [0100ABCD12348000][v65536].nsz")
        try Data("not really compressed".utf8).write(to: url)
        let inspected = PackageInspector.inspect(url: url)
        XCTAssertEqual(inspected.detectionSource, .filename)
        XCTAssertEqual(inspected.titleID, TitleID(value: 0x0100ABCD12348000))
        XCTAssertEqual(inspected.version, 65_536)
        XCTAssertEqual(inspected.kind, .nsz)
    }

    func testDisplayNameCleaning() {
        let url = URL(fileURLWithPath: "/tmp/Super_Mario_Bros._Wonder [010015100B514000][v0].nsp")
        XCTAssertEqual(PackageInspector.displayName(for: url), "Super Mario Bros. Wonder")
    }
}

final class BuildEventTests: XCTestCase {
    func testDecodesStageAndProgress() throws {
        let stage = try XCTUnwrap(BuildEventParser.parse(
            line: #"{"ev":"stage","k":2,"n":7,"name":"extract v327680","step":"","t":123.4}"#
        ))
        XCTAssertEqual(stage.kind, .stage)
        XCTAssertEqual(stage.k, 2)
        XCTAssertEqual(stage.n, 7)
        XCTAssertEqual(stage.name, "extract v327680")

        let progress = try XCTUnwrap(BuildEventParser.parse(
            line: #"{"ev":"progress","k":2,"name":"extract v327680","step":"extracting","done":2048,"total":4096,"unit":"B","est":false,"note":"42 files","frac":0.5,"eta":12.5,"elapsed":4.2}"#
        ))
        XCTAssertEqual(progress.kind, .progress)
        XCTAssertEqual(progress.done, 2048)
        XCTAssertEqual(progress.total, 4096)
        XCTAssertEqual(progress.fraction, 0.5)
        XCTAssertEqual(progress.eta, 12.5)
    }

    func testDecodesSayAndStageEnd() throws {
        let say = try XCTUnwrap(BuildEventParser.parse(line: #"{"ev":"say","msg":"[12:00:00] hello","t":1.0}"#))
        XCTAssertEqual(say.kind, .say)
        XCTAssertEqual(say.message, "[12:00:00] hello")

        let end = try XCTUnwrap(BuildEventParser.parse(
            line: #"{"ev":"stage_end","k":1,"name":"extract v0","ok":true,"summary":"9 files, 1.0 GB","elapsed":20.0}"#
        ))
        XCTAssertEqual(end.kind, .stageEnd)
        XCTAssertEqual(end.ok, true)
        XCTAssertEqual(end.summary, "9 files, 1.0 GB")
    }

    func testIgnoresNonJSON() {
        XCTAssertNil(BuildEventParser.parse(line: "Traceback (most recent call last):"))
        XCTAssertNil(BuildEventParser.parse(line: ""))
    }
}
