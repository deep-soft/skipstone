import XCTest
@testable import SkipBuild
import SkipSyntax

#if canImport(CommonCrypto)
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
        try await SourceValidator.scanSources(from: [srcFile], codebaseThreshold: 1_000_000_000, headerExpressions: [])

        do {
            // scan with a minimal codebase threshold to activate the header scan
            try await SourceValidator.scanSources(from: [srcFile], codebaseThreshold: 1, headerExpressions: [try! NSRegularExpression(pattern: "GNU.*General.Public.License")])
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
        func date(year: Int, month: Int, day: Int) -> Date! {
            DateComponents(calendar: Calendar.current, year: year, month: month, day: day).date
        }

        XCTAssertEqual("SKP26CCCD7271D3FAF09E9A07A2B9D7E0603927934E2A57BC067395D618FF4AC4BBPKS", try LicenseKey(id: "*", expiration: date(year: 2023, month: 8, day: 1)).licenseKeyString)
        XCTAssertEqual("SKP26CCCD7271D3FAF09E9A07A2B9D7E0603E5F4462A815DF89A9A2B8AF340620E9PKS", try LicenseKey(id: "*", expiration: date(year: 2023, month: 9, day: 1)).licenseKeyString)
        XCTAssertEqual("SKP26CCCD7271D3FAF09E9A07A2B9D7E0604A0AEE6BAE4D50A0BE9B235F77934098PKS", try LicenseKey(id: "*", expiration: date(year: 2023, month: 10, day: 1)).licenseKeyString)
        XCTAssertEqual("SKP26CCCD7271D3FAF09E9A07A2B9D7E060FED3EB647598C51389F405AB0E24E101PKS", try LicenseKey(id: "*", expiration: date(year: 2023, month: 11, day: 1)).licenseKeyString)
        XCTAssertEqual("SKP1E37E619FF079E0D7B0537A3A12F759D0861EFE2B32AA9B84775EFBCB692FE88PKS", try LicenseKey(id: "*", expiration: date(year: 2023, month: 12, day: 1)).licenseKeyString)

        XCTAssertEqual("SKP1E37E619FF079E0D7B0537A3A12F759D4542BD1926D17A039A058AE2822BF720PKS", try LicenseKey(id: "*", expiration: date(year: 2024, month: 1, day: 1)).licenseKeyString)
        XCTAssertEqual("SKP1E37E619FF079E0D7B0537A3A12F759D48C0ACB5AF3A7FF1F040547C7F7C6CC5PKS", try LicenseKey(id: "*", expiration: date(year: 2024, month: 2, day: 1)).licenseKeyString)
        XCTAssertEqual("SKP1E37E619FF079E0D7B0537A3A12F759DF90A2BCD55A2D986D14BB3AF8A43F69FPKS", try LicenseKey(id: "*", expiration: date(year: 2024, month: 3, day: 1)).licenseKeyString)
        XCTAssertEqual("SKP1E37E619FF079E0D7B0537A3A12F759DDA60EF2E4E7AB916B43F4750477412BAPKS", try LicenseKey(id: "*", expiration: date(year: 2024, month: 4, day: 1)).licenseKeyString)
        XCTAssertEqual("SKP1E37E619FF079E0D7B0537A3A12F759D495DF6BE50F104179294230F7E220F94PKS", try LicenseKey(id: "*", expiration: date(year: 2024, month: 5, day: 1)).licenseKeyString)
        XCTAssertEqual("SKP1E37E619FF079E0D7B0537A3A12F759DA27710CA8216BBF4F18FDDCDD257AF86PKS", try LicenseKey(id: "*", expiration: date(year: 2024, month: 6, day: 1)).licenseKeyString)
        XCTAssertEqual("SKP1E37E619FF079E0D7B0537A3A12F759DB268A17E3E1FDE90338D03B0C1FE790EPKS", try LicenseKey(id: "*", expiration: date(year: 2024, month: 7, day: 1)).licenseKeyString)
        XCTAssertEqual("SKP1E37E619FF079E0D7B0537A3A12F759DA791F0D0D768DA61AEE75E0BDC8889D5PKS", try LicenseKey(id: "*", expiration: date(year: 2024, month: 8, day: 1)).licenseKeyString)
        XCTAssertEqual("SKP1E37E619FF079E0D7B0537A3A12F759D719C1155288FC3FF2EF7F06A4C204A79PKS", try LicenseKey(id: "*", expiration: date(year: 2024, month: 9, day: 1)).licenseKeyString)
        XCTAssertEqual("SKP1E37E619FF079E0D7B0537A3A12F759D27CD1E102598B3C40EEFC38A865C1944PKS", try LicenseKey(id: "*", expiration: date(year: 2024, month: 10, day: 1)).licenseKeyString)
        XCTAssertEqual("SKP1E37E619FF079E0D7B0537A3A12F759DA74C25D1454E770454AD36AE548CBFF7PKS", try LicenseKey(id: "*", expiration: date(year: 2024, month: 11, day: 1)).licenseKeyString)
        XCTAssertEqual("SKP1E37E619FF079E0D7B0537A3A12F759D997406FA0ACF49BD195B365CDC9F99C2PKS", try LicenseKey(id: "*", expiration: date(year: 2024, month: 12, day: 1)).licenseKeyString)

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
#endif
