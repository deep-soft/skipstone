import XCTest
@testable import SkipBuild
import CryptoKit


struct LicenseKey : Codable {
    let appid: String
    let expiration: Date

    /// Returns the encoded license string
    var licenseString: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(self).utf8String
    }

    enum CodingKeys: String, CodingKey {
        case appid = "a"
        case expiration = "x"
    }
}

typealias CipherSuite = AES.GCM
//typealias CipherSuite = ChaChaPoly

final class SkipLicenseTests: XCTestCase {
    public func testLicenseKeys() throws {
        let license = LicenseKey(appid: "com.coolapp.MyApp", expiration: Date(timeIntervalSinceReferenceDate: 100_000_000))
        print("License:", license.licenseString!)

        let licenseData = Data(license.licenseString!.utf8)

        let keys = [
            SymmetricKey(data: Data("A080D0DA98B5405D86FB5D1ECAFC7963".utf8)),
            SymmetricKey(data: Data("B0000000000000000000000000000000".utf8)),
            SymmetricKey(data: Data("C0000000000000000000000000000000".utf8)),
            SymmetricKey(data: Data("D0000000000000000000000000000000".utf8)),
            SymmetricKey(data: Data("E0000000000000000000000000000000".utf8)),
        ]

        let sealedBox: CipherSuite.SealedBox

        do {
            let encryptKey = keys.randomElement()!
            print(encryptKey.bitCount)

            // Use AES-GCM to encrypt the plaintext message with the symmetric key
            sealedBox = try CipherSuite.seal(licenseData, using: encryptKey)

            // Extract the ciphertext from the sealed box
            let ciphertext = sealedBox.ciphertext
            print("Encrypted license: \(ciphertext.hexEncodedString())")

            // Extract the nonce from the sealed box
            let nonce = sealedBox.nonce
            print("Nonce: \(nonce)")

            // Extract the tag from the sealed box
            let tag = sealedBox.tag
            print("Tag: \(tag.hexEncodedString())")
        }

        do {
            for key in keys.reversed() {
                do {
                    // Use AES-GCM to decrypt the ciphertext message with the symmetric key and the nonce and tag from the sealed box
                    let decryptedData = try CipherSuite.open(sealedBox, using: key)

                    // Convert the decrypted data to a string
                    guard let decryptedString = String(data: decryptedData, encoding: .utf8) else {
                        throw CryptoError.decryptionFailed
                    }

                    print("Decrypted plaintext message: \(decryptedString)")
                } catch {
                    // try the next key
                }
            }
        }
    }
}

extension String {
    func hexEncodedString() -> String {
        (data(using: .utf8) ?? Data()).hexEncodedString()
    }
}

extension Data {
    func hexEncodedString() -> String {
        map { String(format: "%02hhx", $0) }.joined()
    }
}

enum CryptoError : Error {
    case decryptionFailed
}
