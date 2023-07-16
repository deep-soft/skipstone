import XCTest
@testable import SkipBuild
import SkipSyntax
#if canImport(Crypto)
import Crypto
#else
import CryptoKit
#endif

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
        // GNU Lesser
        //     General Public License
        public struct XYZ { }
        """)

        try await sourceCheck(expectFailure: true, swift: """
        // GNU UnLesser
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
        func date(_ year: Int, _ month: Int, _ day: Int) -> Date! {
            DateComponents(calendar: Calendar.current, year: year, month: month, day: day).date
        }

        func check(_ keyString: String, _ license: LicenseKey) throws {
            let licenseKeyString = try license.licenseKeyString

            if !keyString.isEmpty {
                let license2 = try LicenseKey(licenseString: keyString)
                XCTAssertEqual(license, license2)
            } else {
                XCTAssertEqual(keyString, licenseKeyString)
            }

            let license3 = try LicenseKey(licenseString: licenseKeyString)
            XCTAssertEqual(license, license3)
        }

        try check("SKP704DD5FD0B93575EFFCF9FD13D1A439BC6FE14AEC29C0919BA6F9A77A1F1C5FF7BB837D81F679BA62DA67DD844F18C39237F447BBAPKS", LicenseKey(id: "*", expiration: date(2023, 7, 1)))
        try check("SKP2543ECF34060EB22A97F930A7379D9E4C414A3F67149FB6E32969B67F43EBEE127D835FB10EC0CBC590D5D91066D6B0DA69E7BFBF1PKS", LicenseKey(id: "*", expiration: date(2023, 8, 1)))
        try check("SKPAC9716A644749B5058568045BE7EE3901C75D5E34A0798B272E3C1B712918D0DEF70E637C129E150A96AC58EAAC34AF7698019B8C9PKS", LicenseKey(id: "*", expiration: date(2023, 9, 1)))
        try check("SKPE5E43DD18F52CC667E8B58A9E5BBAC6BE9A6ED36657DAE4007CA9764329C7827878554DAE5634527010B11187D567D5C88BDF2B231PKS", LicenseKey(id: "*", expiration: date(2023, 10, 1)))
        try check("SKP841395D34EAD316F5C128BA0B2FDC8E551F478931CE49426B79B23BC5B0A1C5642EE7A92DD9C5AB828292BDE4AAC44D74D1A59A6BBPKS", LicenseKey(id: "*", expiration: date(2023, 11, 1)))
        try check("SKPF585170957233961DE8AD9EA164F4A803E67CC8BD84BA830B3AB58F442C011BDD997A0D66E0EAA99865E662746C80CE696BB277487PKS", LicenseKey(id: "*", expiration: date(2023, 12, 1)))

        try check("SKP8E01797DE1C02740C35C253FAFE170827AA706A28DF72E8748BCAAEE72EDC769156AAAB33F4685F2886877F70BCEAA936DC3C22F7FPKS", LicenseKey(id: "*", expiration: date(2024, 1, 1)))
        try check("SKP6800A73E0EE8896103BA8C4F5DD819CC00C97B0BFC5FC37B0D81AC71B411C5950A2AFEB35D8E0714C17C6226766B5E249ED5EDEA64PKS", LicenseKey(id: "*", expiration: date(2024, 2, 1)))
        try check("SKP804ED2406F19255E9E32E0E975B995BC1D13CD0007666B46AF15B5E1A6C16515579EE62513446F94944C4F5D053870BF4C5C9FFA6EPKS", LicenseKey(id: "*", expiration: date(2024, 3, 1)))
        try check("SKP4AE19D0E8370C4CD8E3C60D7DC2A0221266E3A71B002ACB6AE65297D3D75FF3D0C4A57D001E7E0EB116BDDB83E36316DC38F958F91PKS", LicenseKey(id: "*", expiration: date(2024, 4, 1)))
        try check("SKPAC452200719A3762003777C7653830969234AE585D989E4591825685F22E41583A5DD6C85BEF1B9C43CE9719EE5AE0C0BF8D2FC1D5PKS", LicenseKey(id: "*", expiration: date(2024, 5, 1)))
        try check("SKP20AB6671AE3F0886E9F6C0168F009F49F122DB8F339E07F9A75AFA6BA2CC8C4B4F6078DAA3CE35AD025B8A3F1CB2DCA4BCCD7FAC9DPKS", LicenseKey(id: "*", expiration: date(2024, 6, 1)))
        try check("SKPDE0BE80908DCF29D888213369D905AF5E2796DE3B863355888A371C6EA808C717AE9DB1FA6B3DD94CB2F9F9B61A2732167BFCC5E38PKS", LicenseKey(id: "*", expiration: date(2024, 7, 1)))
        try check("SKP79683712F273574515BCC55696166DB0D0A0CFCD352304F1D972672D3BB671DD09EC6734A6D9883E9B9E63A5E4BAFD6514AA5041B6PKS", LicenseKey(id: "*", expiration: date(2024, 8, 1)))
        try check("SKP3FD4955FEDAF0EF91870C5D50C08B8907ED3A6C39A917B37A23092ED1FE5B8863F844478361C3D06EE6B101EB84455E5D46F48499DPKS", LicenseKey(id: "*", expiration: date(2024, 9, 1)))
        try check("SKP8F6CD58E3B3240C890F035A5CEC0FCBDE02EF2B81DE176B8B1BA707F6F87A79D71AA8963873B7090707C27A723F9014CCB97C740D4PKS", LicenseKey(id: "*", expiration: date(2024, 10, 1)))
        try check("SKP153DD46BFF4D2700EEBC0F5DCFB7CBE473EDA6B208F49F66207B33B059CF1266EFD4AFCFEAD785E5F0AFD1D236CA76DECCF82055BEPKS", LicenseKey(id: "*", expiration: date(2024, 11, 1)))
        try check("SKP60CAECE86A3E31AB87D29D36C726FC07F405CA7396714382C94667CD6474940F9A27985E86703C50DBE07C65D6203BC3DD942BFC49PKS", LicenseKey(id: "*", expiration: date(2024, 12, 1)))

        XCTAssertThrowsError(try LicenseKey(licenseString: ""), "empty license key")
        XCTAssertThrowsError(try LicenseKey(licenseString: "F156BB3B02FA20AD8259FCD1872B363A3D7EA4FE87060DD3FDAA00B29BC03483241572DDAC842776365F04FB7009EABE"), "license key with invalid prefix/suffix")
        XCTAssertThrowsError(try LicenseKey(licenseString: "SKPPKS"), "empty payload")
        XCTAssertThrowsError(try LicenseKey(licenseString: "SKPQQPKS"), "invalid payload hex")
        XCTAssertThrowsError(try LicenseKey(licenseString: "SKP00PKS"), "invalid payload data")

        let license = LicenseKey(id: "com.coolapp.MyApp", expiration: date(2025, 1, 1))
        let license2 = try LicenseKey(licenseString: "SKPF52B75ADC0792A155AC14C3D0B238179671E9CE6D63A3B720958038E5F3D43C43156CD91291C3F1944A89D0030C021ED1D64B8ABFAFDDA3AA890692D2908D4B82A3EB22446PKS")
        XCTAssertEqual(license, license2)
    }

    func testCryptoKit() throws {
        let data = Data([8, 12, 7, 143])

        let iv = try AES.GCM.Nonce(data: Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]))
        let key = SymmetricKey(data: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15])

        do { // with tag
            // Encrypt the data using AES.GCM.seal
            let encryptor = try AES.GCM.seal(data, using: key, nonce: iv)
            let etag = encryptor.tag

            XCTAssertEqual("000102030405060708090a0b", encryptor.nonce.hexEncodedString())
            XCTAssertEqual("e10bc4ac33221409b7714bc9c5b0fe41", encryptor.tag.hexEncodedString())
            XCTAssertEqual("000102030405060708090a0b9b60a041e10bc4ac33221409b7714bc9c5b0fe41", encryptor.combined?.hexEncodedString() ?? "")
            XCTAssertEqual("9b60a041", encryptor.ciphertext.hexEncodedString())
            XCTAssertEqual("9b60a041", encryptor.combined?.dropFirst(Array(iv).count).dropLast(etag.count).hexEncodedString() ?? "")

            let ciphertext = encryptor.ciphertext
            XCTAssertEqual(encryptor.combined, iv + ciphertext + etag)
            //let decryptor = try AES.GCM.SealedBox(nonce: iv, ciphertext: ciphertext, tag: etag)
            let decryptor = try AES.GCM.SealedBox(combined: iv + ciphertext + etag)
            let decryptedData = try AES.GCM.open(decryptor, using: key)
            XCTAssertEqual(decryptedData, data)
        }
    }

    func testCrypt() throws {
        // random blob of data
        let data = Data((0...(Int.random(in: 1024...(1024 * 1024)))).map { _ in
            UInt8.random(in: UInt8.min...UInt8.max)
        })

        let encrypted = try aes(data: data, encrypt: true)
        XCTAssertNotEqual(data, encrypted, "data should have been encrypted")

        let decrypted = try aes(data: encrypted, encrypt: false)
        XCTAssertEqual(data, decrypted, "data should have been decrypted")

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
