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

        try await sourceCheck(expectFailure: true, swift: """
        
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
        try SourceValidator.scanSources(from: [srcFile], codebaseThreshold: 1_000_000_000, headerExpressions: [])

        do {
            // scan with a minimal codebase threshold to activate the header scan
            try SourceValidator.scanSources(from: [srcFile], codebaseThreshold: 1)
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
            DateComponents(calendar: Calendar.current, timeZone: TimeZone(secondsFromGMT: 0), year: year, month: month, day: day).date
        }

        func check(_ keyString: String, _ license: LicenseKey, iv: Data? = nil) throws {
            let licenseKeyString = try license.licenseKeyString(iv: iv)

            if !keyString.isEmpty {
                let license2 = try LicenseKey(licenseString: keyString)
                XCTAssertEqual(license, license2)
            }

            if iv != nil {
                // this doesn't always generate the same key
                //XCTAssertEqual(keyString, licenseKeyString)
            }

            let license3 = try LicenseKey(licenseString: licenseKeyString)
            XCTAssertEqual(license, license3)
        }


        try check("SKP000000000000000000000000EB195AE8771A91FC78BB75BE9DAF55CEF98A795EA2B050A0DDC83B532FEA17C80F684A4C5404ACC9PKS", LicenseKey(id: "*", expiration: date(2000, 1, 1)), iv: Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))
        try check("SKP010000000000000000000000EA33D2E0AC2A8873E568EC96A02FA367556607F0E66579C59A155D8B69E350E5DDBD3C5DA4D83C6CPKS", LicenseKey(id: "*", expiration: date(2000, 1, 1)), iv: Data([0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))
        try check("SKPFFFFFFFFFFFFFFFFFFFFFFFFEB717659AAC56B8C1FABA11B16D8A0532DDB6F663EA90F8028611B26075D9C2C32404FAC9A3E8DE9PKS", LicenseKey(id: "*", expiration: date(2000, 1, 1)), iv: Data([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]))

        try check("SKPA0774FE5E6799A1DDBF57B5A16D66498F578FAB36A4D88B93917DBCEF6FADC3FE3E936E6EDACF1E83F89EEC90D011212597075083APKS", LicenseKey(id: "*", expiration: date(2023, 7, 1)))
        try check("SKP76D90003EF9BE861F47620463C2D34B5CDAB0864810BA475936112C2854944EFC2396689585BD05B9A5CC2365C96F837CD42726A4FPKS", LicenseKey(id: "*", expiration: date(2023, 8, 1)))
        try check("SKP4D1D6B1CD44D5BE7371A56185F236C9DD18422870137413B9133C7F931E4D189D21DDD6F1431AEEC0E5268F72462619F41A2015F07PKS", LicenseKey(id: "*", expiration: date(2023, 9, 1)))
        try check("SKP608F80EB8498216CE483A0F77CB8157BFA74881CB68EE44316D87275669EBC39454A4FEDC67E705EF72B18349FD7394B4EC01E612FPKS", LicenseKey(id: "*", expiration: date(2023, 10, 1)))
        try check("SKP3D6BB84AE896FE2809765D29792F04945CB8CB8C3EB626919FAD264ED712AA0CB2D38CF61C5EF8D9FFE28075BD3928AD3756DC9936PKS", LicenseKey(id: "*", expiration: date(2023, 11, 1)))
        try check("SKP9BA8FEA3B934A9E11DC6624DFEB920523943379A42B497DF5FEA546703F037251E977430958D7D388289F8F8D3C40F47DA30B94124PKS", LicenseKey(id: "*", expiration: date(2023, 12, 1)))

        try check("SKP81A6D889A7BC53F37E69EF9DEC5A7EA29218E2B2C100026E8252F373E107774E04C8C263CA7FA42F506C2013AE5FD9BF2ADB570E5EPKS", LicenseKey(id: "*", expiration: date(2024, 1, 1)))
        try check("SKPE280D7C2B94FD47166060D8347B7253FBB32165E44715D82F985D6DC15EA0BEC773CDD655B85C592A24F1C4F3F4F4DDFC0D415879EPKS", LicenseKey(id: "*", expiration: date(2024, 2, 1)))
        try check("SKP3974D08BF2E72C5A3817747DAC96969CC8ADEFD65A1632CBFC85277C2BE66E6A789A7548DA2F18B26D5BB376C6DD7C53F5B58E504FPKS", LicenseKey(id: "*", expiration: date(2024, 3, 1)))
        try check("SKPC413322F10802E0A8D224DC76FACA1469C209AF95A46589D5819AC070832E6853A9A30990021CD552B2C0CE6C0674B259C598EB944PKS", LicenseKey(id: "*", expiration: date(2024, 4, 1)))
        try check("SKP89905002728CE56E7CFDC702DF6AFE22F71B305E1BB7BFC386EA8645AE6C932A314201B874EA56C9CD8BC10E8B7DA6A88316C8D7E7PKS", LicenseKey(id: "*", expiration: date(2024, 5, 1)))
        try check("SKP4DAE70E479BD565BE64737304FEA2D744EF6DB3F5A246AB278C4D7891152A2DCD91F8FEF736C55735F850E5F2101C7A39F0433D7DCPKS", LicenseKey(id: "*", expiration: date(2024, 6, 1)))
        try check("SKP1F5AA67B24907C8609F6D87D2B090163C2BF711D02FC5C0967336AAB2BFD2B8AC550F13BAEA6BFA8A07D456FB4357C0D9D09D9ED8EPKS", LicenseKey(id: "*", expiration: date(2024, 7, 1)))
        try check("SKP7A77B0F15AD7E8D19A17C542A1ACBBE1CBD8C3E292381D6E1FF4B87013AB0DA9C4B85D4596B23A9AD9B8E82A8B06BD7E0783FB36C4PKS", LicenseKey(id: "*", expiration: date(2024, 8, 1)))
        try check("SKP5DF466FE0DB63BA5B90604895EC7748513444581ED2578ADAE5625134CCA0DDF57A4967CDA8254069D340953C295194FBFE6DA1FE4PKS", LicenseKey(id: "*", expiration: date(2024, 9, 1)))
        try check("SKPF32AE2CE7D0F31F7EF6A121349D39A7E7CAA87398E50FFAB0608AD7E68778455A99824562E0AA1E84795172945DB19468D08BCD133PKS", LicenseKey(id: "*", expiration: date(2024, 10, 1)))
        try check("SKP0F871D72DBE74E6D40B5E18E99F55D979547B7D31A9B1B1E8790381E102FFC52FD6FE7CC91000ADE0B1AC82662C5660324ADA30DD5PKS", LicenseKey(id: "*", expiration: date(2024, 11, 1)))
        try check("SKPCBF0E9FDA08CEB59479D66F16C4C5E52E07D6EF53AD92A1272F11D13D33C47913BEC2600C500B03BE7FCD9B519A06225E7405E3EC7PKS", LicenseKey(id: "*", expiration: date(2024, 12, 1)))

        XCTAssertThrowsError(try LicenseKey(licenseString: ""), "empty license key")
        XCTAssertThrowsError(try LicenseKey(licenseString: "F156BB3B02FA20AD8259FCD1872B363A3D7EA4FE87060DD3FDAA00B29BC03483241572DDAC842776365F04FB7009EABE"), "license key with invalid prefix/suffix")
        XCTAssertThrowsError(try LicenseKey(licenseString: "SKPPKS"), "empty payload")
        XCTAssertThrowsError(try LicenseKey(licenseString: "SKPQQPKS"), "invalid payload hex")
        XCTAssertThrowsError(try LicenseKey(licenseString: "SKP00PKS"), "invalid payload data")

        let license = LicenseKey(id: "com.coolapp.MyApp", expiration: date(2025, 1, 1))
        let license2 = try LicenseKey(licenseString: "SKPD4917F97507E8F30855A3F16AF3EB7C221D3381C31500DFE83F17C9D6F6BA9C77D2D21F878D04202E5C8342EDAECEF39494AE3C2EF5B30D0B874613E3FE5DD561B5A2E3496PKS")
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
        XCTAssertThrowsError(try aes(data: encrypted, encrypt: false, currentDate: DateComponents(calendar: Calendar.current, timeZone: TimeZone(secondsFromGMT: 0), year: 2030, month: 1, day: 1).date!), "expected key expiration error") { error in
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
