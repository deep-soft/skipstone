import XCTest
@testable import SkipBuild
import SkipSyntax

final class SkipLicenseTests: XCTestCase {
    /// Verified that the source header scanner will check for the expected expressions.
    func testSourceHeaders() async throws {
        // no source header
        try await sourceCheck(expectFailure: true, swift: """
        // Header comment
        import Foundation
        import XCTest
        
        // Type comment
        public struct XYZ {
        }
        """)

        try await sourceCheck(expectFailure: true, swift: """
        // XYZ General Public License
        public struct XYZ { }
        """)

        try await sourceCheck(expectFailure: true, swift: """
        // Some commercial header
        public struct XYZ { }
        """)

        try await sourceCheck(expectFailure: true, swift: """
        public struct XYZ { }
        """)

        try await sourceCheck(expectFailure: false, swift: """
        // GNU General Public License
        public struct XYZ { }
        """)

        try await sourceCheck(expectFailure: false, swift: """
        // GNU Affero General Public License
        public struct XYZ { }
        """)

        try await sourceCheck(expectFailure: false, swift: """
        // GNU Limited
        //     General Public License
        public struct XYZ { }
        """)
    }

    func sourceCheck(expectFailure: Bool, swift: String) async throws {
        let srcFile = try tmpFile(named: "Source.swift", contents: swift)

        // first make sure that everything below the codebase threshold passes regardless of the header comment
        try await SourceValidator.scanSources(from: [srcFile], codebaseThreshold: 1_000_000_000)

        // also make sure that everything passes when a valid license is provided
        try await SourceValidator.scanSources(from: [srcFile], codebaseThreshold: 1_000_000_000)

        do {
            // scan with a minimal codebase threshold to activate the header scan
            try await SourceValidator.scanSources(from: [srcFile], codebaseThreshold: 1)
            if expectFailure {
                XCTFail("Expected error")
            }
        } catch {
            if !expectFailure {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testLicenseKeys() throws {
        XCTAssertThrowsError(try LicenseKey(licenseString: ""), "empty license key")
        XCTAssertThrowsError(try LicenseKey(licenseString: "F156BB3B02FA20AD8259FCD1872B363A3D7EA4FE87060DD3FDAA00B29BC03483241572DDAC842776365F04FB7009EABE"), "license key with invalid prefix/suffix")
        XCTAssertThrowsError(try LicenseKey(licenseString: "SKPPKS"), "empty payload")
        XCTAssertThrowsError(try LicenseKey(licenseString: "SKPQQPKS"), "invalid payload hex")
        XCTAssertThrowsError(try LicenseKey(licenseString: "SKP00PKS"), "invalid payload data")

        let license = LicenseKey(id: "com.coolapp.MyApp", expiration: DateComponents(calendar: Calendar.current, year: 2025, month: 1, day: 1).date!)
        let licenseKey = "SKPF156BB3B02FA20AD8259FCD1872B363A3D7EA4FE87060DD3FDAA00B29BC03483241572DDAC842776365F04FB7009EABEPKS"
        XCTAssertEqual(licenseKey, try license.licenseKeyString)
        let license2 = try LicenseKey(licenseString: licenseKey)
        XCTAssertEqual(license, license2)

        // random blob of data
        let data = Data((0...(Int.random(in: 10...100_000))).map { _ in
            UInt8.random(in: UInt8.min...UInt8.max)
        })

        let encrypted = try aes(data: data, encrypt: true)
        XCTAssertNotEqual(data, encrypted)

        let decrypted = try aes(data: encrypted, encrypt: false)
        XCTAssertEqual(data, decrypted)

        // try the license as if we were fast-forwarded to a date when it becomes invalid
        XCTAssertThrowsError(try aes(data: encrypted, encrypt: false, currentDate: DateComponents(calendar: Calendar.current, year: 2030, month: 1, day: 1).date!), "expected key expiration error") { error in
            guard case LicenseError.cryptKeyExpired = error else {
                XCTFail("expected expiration error but got: \(error)")
                return
            }
        }
    }

    func testCreateRandomKeys() {
        for _ in 1...25 {
            //print(UUID().base64String)
        }
    }

    /// Creates a temporary file with the given name and optional contents.
    public func tmpFile(named fileName: String, contents: String? = nil) throws -> URL {
        let tmpDir = URL(fileURLWithPath: UUID().uuidString, isDirectory: true, relativeTo: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let tmpFile = URL(fileURLWithPath: fileName, isDirectory: false, relativeTo: tmpDir)
        if let contents = contents {
            try contents.write(to: tmpFile, atomically: true, encoding: .utf8)
        }
        return tmpFile
    }

}

