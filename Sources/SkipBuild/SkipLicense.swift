import Foundation
import SkipSyntax
import ArgumentParser
import struct Universal.YAML
#if canImport(Crypto)
import Crypto
#else
import CryptoKit
#endif

/// the list of header match expressions that we permit for codebases above the given threshold
internal let validLicenseHeaders = [
    try! NSRegularExpression(pattern: #".*GNU(?:\sAffero|\sLesser)*\sGeneral\sPublic\sLicense.*"#), // full license text
    //try! NSRegularExpression(pattern: #".*Open\sSoftware\sLicense.*"#), // TODO: accept OSL-3.0?
    try! NSRegularExpression(pattern: #".*SPDX-License-Identifier: (?:OSL|GPL|LGPL|AGPL)-3*"#), // accept SPDX ID: LGPL-3.0-only, GPL-3.0-or-greater, AGPL-3.1
]

/// The user-facing path name for the license key file
private let licenseKeyLocationPath = skipkeyFile.path.abbreviatingWithTilde // "~/.skiptools/skipkey.env"

private var skipkeyFile: URL = {
    let skiptoolsFolder = URL(fileURLWithPath: ".skiptools", relativeTo: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true))
    let skipkeyFile = URL(fileURLWithPath: "skipkey.env", isDirectory: false, relativeTo: skiptoolsFolder)
    return skipkeyFile
}()

public enum LicenseError: LocalizedError {
    /// The license did not start and end with the necessary strings
    case invalidLicenseFormat
    /// The license has expired
    case licenseExpired(expiration: Date)
    /// No encryption keys could be used to decrypt the data
    case noKeys
    /// The encryption key is invalid
    case invalidKey
    /// The data was invalid
    case invalidData
    /// A encryption/decryption error
    case cryptorFailure(status: Int32)
    /// The key that was used to encrypt the license is no longer valid for decryption
    case cryptKeyExpired(date: Date)
    /// The encryption key that created this license has been revoked
    case cryptKeyRevoked
    /// The specific license key has been added to the revocation list
    case licenseKeyRevoked
    /// The header comment of the source file does not match an approved expression
    case unmatchedHeaders(sourceURLs: [URL])
    /// The format of the expiration date is invalid
    case licenseExpirationDateInvalid
    /// The nonce encoding was not valid
    case invalidNonceFormat
    /// The Skip installation information was not found
    case skipNotInstalled

    public var errorDescription: String? {
        switch self {
        case .invalidLicenseFormat:
            return "The Skip.tools license is invalid."
        case .licenseExpired(expiration: let expiration):
            return "The Skip.tools license expired on \(expiration) and must be renewed."
        case .noKeys:
            return "The Skip.tools license has an internal error."
        case .invalidKey:
            return "The Skip.tools license content in \(licenseKeyLocationPath) was invalid."
        case .invalidData:
            return "The Skip.tools license data was invalid."
        case .cryptorFailure(status: let status):
            return "Internal Skip.tools license error: \(status)."
        case .cryptKeyExpired(date: let date):
            return "The Skip.tools license was created with a version of the software that expired on \(date) and must be re-generated."
        case .cryptKeyRevoked:
            return "The Skip.tools license needs to be re-constructed."
        case .licenseKeyRevoked:
            return "The Skip.tools license needs to be re-generated."
        case .unmatchedHeaders(sourceURLs: let sourceURLs):
            return "No Skip.tools license key found in \(licenseKeyLocationPath) for source files: \(sourceURLs.map(\.lastPathComponent).joined(separator: ", "))."
        case .licenseExpirationDateInvalid:
            return "The format of the expiration date is invalid."
        case .invalidNonceFormat:
            return "The format of the 12-byte hex-encoded nonce is invalid"
        case .skipNotInstalled:
            return "Skip is not installed — see https://skip.tools and install with: brew install skiptools/skip/skip"
        }
    }

    /// True if this error comes from the content of the data (rather than the key)
    @usableFromInline var isContentError: Bool {
        if case .cryptorFailure = self {
            return true
        }

        return false
    }

    /// The source file that should be associated with this error, if any
    var sourceFile: Source.FilePath? {
        switch self {
        case .unmatchedHeaders(let urls):
            guard let url = urls.first else {
                return nil
            }
            return .init(path: url.path)
        default:
            return nil
        }
    }
}

/// The serialized license key that contains the appid and the expiration date, as well as any other information that needs to be encoded in the key.
struct LicenseKey: Equatable, Codable {
    let id: String
    let expiration: Date
    let hostid: String?
    let flags: LicenseFlags?

    // bookends make the key identifiable with a regular expression ("^SKP[0-9A-F]{10,}PKS$"), so we can be notified of leaked keys by key scanning services like:
    // https://docs.github.com/en/code-security/secret-scanning/secret-scanning-partner-program#the-secret-scanning-process
    static let (keyStart, keyEnd) = ("SKP", "PKS") // this can be anything, as long as it is somewhat unique

    /// Short keys to keep the license string as compact as possible
    enum CodingKeys: String, CodingKey {
        case id = "id"
        case expiration = "x"
        case hostid = "h"
        case flags = "f"
    }

    struct LicenseFlags : OptionSet, Codable {
        static let trial = LicenseFlags(rawValue: 1 << 0)
        static let eval = LicenseFlags(rawValue: 1 << 1)
        static let indie = LicenseFlags(rawValue: 1 << 2)
        static let smallbusiness = LicenseFlags(rawValue: 1 << 3)
        static let professional = LicenseFlags(rawValue: 1 << 4)

        let rawValue: Int
        init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }

    enum LicenseType : String, CaseIterable, Codable {
        case trial
        case eval
        case indie
        case smallbusiness
        case professional

        var licenseFlags: LicenseFlags {
            switch self {
            case .trial: return [.trial]
            case .eval: return [.eval]
            case .indie: return [.indie]
            case .smallbusiness: return [.smallbusiness]
            case .professional: return [.professional]
            }
        }
    }

    @inlinable init(id: String, expiration: Date, hostid: String? = nil, flags: LicenseFlags?) {
        self.id = id
        self.expiration = expiration
        self.hostid = hostid
        self.flags = flags
    }

    @inlinable init(licenseString: String) throws {
        let licenseData = try Self.parseLicenseContent(licenseString: licenseString)
        let jsonData = try Self.aes(data: licenseData, encrypt: false)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        self = try decoder.decode(LicenseKey.self, from: jsonData)
    }

    /// The type of the license is encoded in the flags
    var licenseType: LicenseType? {
        guard let flags else {
            return nil // legacy without a flag field
        }

        for type in LicenseType.allCases.reversed() {
            if flags.contains(type.licenseFlags) {
                return type
            }
        }
        return nil // unknown or unset
    }

    /// Returns the unencrypted JSON-encoded license string
    @inlinable var licenseJSON: String {
        get throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .secondsSince1970
            return try String(data: encoder.encode(self), encoding: .utf8) ?? ""
        }
    }

    /// Returns the encrypted license string, using the optional 12-byte initialization vector data
    func licenseKeyString(iv: Data? = nil) throws -> String {
        try Self.keyStart + Self.aes(nonce: iv.flatMap(AES.GCM.Nonce.init(data:)), data: licenseJSON.utf8Data, encrypt: true).hexEncodedString().uppercased() + Self.keyEnd
    }

    static func parseLicenseContent(licenseString: String) throws -> Data {
        guard licenseString.hasPrefix(Self.keyStart) && licenseString.hasSuffix(Self.keyEnd) else {
            throw LicenseError.invalidLicenseFormat
        }

        let hexString = licenseString.dropFirst(Self.keyStart.count).dropLast(Self.keyEnd.count)
        guard let data = Data(hexString: String(hexString)) else {
            throw LicenseError.invalidLicenseFormat
        }

        // a static embedded list of license strings that should be blocked
        // leaked keys will be added to new releases of the software to prevent them from being used
        let revokedLicenseKeys: Set<String> = [
            //"SKP00000000000000000000000000000000000000PKS", // example of a leaked key
            "SKP8EA6DB28FCC9E14E1D04F6F3C27446F85ACD05350C046F8733AA980980980F1EF3EACB3C49A6CB271FEE2E73F0B9D8C4D6C9D06C61222AC45E1581E40DF80BA8C62E2BEF4BF03D118A2A267967E5CAA0013CB44D0F3B85624C5C017EB2D1596D2B4B8F142CF0346E1B764E032FA3FD4301E28C96E163209A3549DD35996A11700073930CPKS", // change of hostid from 25429A59-8F34-5502-8455-9F1AEF860FA5 to E7E67EEE-B69C-5D41-9DFD-C3ED33F4220B requested by angel.henderson@salemwebnetwork.com on 2024-08-28 (replaced with: SKP8290E7E92AA3033A7AF1909DA76460AD1E86241CC813D6FECF5CFC1C643FA30786476F16E0DF0541321BC866E169A1242E9B2AD4A7AC6B2AEA79D80BC61CA9A579A3754B4B921FC12E0B77D5EEBAAC1B83615D435498DB8APKS)
            "SKP8BC5E57A2FBD674FCCC032BA695B96C9B4C70DE6634B7449D1402BDE604C10893BAAC247EAE300B880F9138B6A3C0603F1E9C980F29799C5E4272DC57B69A57D6E42920245357E0993CC16C58DA5C2110FA649065EBB7D5E4EA8FA00D16E5F3027E81051C056C0018C116F2D954F9AB441056F9C88PKS", // change of hostid from 8410326C-D9B6-5A3F-8382-F8B978322EF3 to 12008BD0-ECAC-55C3-A9FF-FC6CED4436FD for Pierluigi Cifani <pcifani@theleftbit.com> on April 26, 2025
        ]

        if revokedLicenseKeys.contains(licenseString) {
            throw LicenseError.licenseKeyRevoked
        }

        return data
    }

    /// Takes the AES128 base64 key string as a String argument, the Data to encrypt or decrypt, and a boolean flag called encrypt that indicates whether the function should encrypt or decrypt the data. The function returns a Data object containing the encrypted or decrypted data.
    ///
    /// The function first checks that the key is valid by decoding it from base64 and ensuring that it is the correct length. If the key is invalid, the function throws an invalidKey error.
    ///
    /// - Parameters:
    ///   - keyBase64: the base64-encoded key
    ///   - data: the data to encrypt or decrypt
    ///   - encrypt: whether the data should be encrypted or decrypted
    /// - Returns: the encrypted or decrypted data
    @inline(__always) private static func aes(nonce: AES.GCM.Nonce? = nil, keyBase64 keyString: String? = nil, data: Data, encrypt: Bool, currentDate: Date = Date()) throws -> Data {
        func k(_ b1: UInt8, _ b2: UInt8, _ b3: UInt8, _ b4: UInt8, _ b5: UInt8, _ b6: UInt8, _ b7: UInt8, _ b8: UInt8, _ b9: UInt8, _ b10: UInt8, _ b11: UInt8, _ b12: UInt8, _ b13: UInt8, _ b14: UInt8, _ b15: UInt8, _ b16: UInt8) -> Data {
            Data([b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13, b14, b15, b16])
        }

        // a wheel of AES-128 encryption/decryption keys that is meant to be rotated periodically in conjunction with the expiration scheme of the license that it encrypts
        // The most recent key will always be used to encrypt data, but older keys will be attempted for decryption. This allows older (and possibly compromised) keys to eventually be rotated out and expired after such time that any license that would have been encoded would have been expired anyway.
        // The active (i.e., most recent) key will be the one the order fulfillment provider should be configured to issue for future orders (e.g., https://fastspring.com/docs/license-key-fulfillments/#anchor-script)
        let keyWheel = [
            // revoked keys; any license encrypted with one of these keys will be considered invalid and the user will need to contact the vendor to obtain a new key
            (k(0x08, 0x3A, 0x89, 0x56, 0xC5, 0xC3, 0x41, 0x80, 0xAC, 0xB0, 0x38, 0x4F, 0x2F, 0x78, 0x11, 0xA2), nil),
            (k(0x94, 0x04, 0x59, 0x99, 0x80, 0x7F, 0x40, 0xD5, 0xA9, 0x9F, 0x04, 0x74, 0xDE, 0x4D, 0x03, 0xE0), nil),

            (k(0xB2, 0xA9, 0x77, 0x4F, 0x6A, 0xD8, 0x42, 0x89, 0x81, 0xB2, 0x8F, 0x42, 0xD7, 0x65, 0x26, 0x38), date(month: 1, year: 2024)),
            (k(0x68, 0x1B, 0x87, 0x33, 0x03, 0xD9, 0x45, 0xBF, 0xA9, 0xFD, 0xA2, 0xD4, 0x5F, 0x06, 0x0C, 0xC8), date(month: 4, year: 2024)),
            (k(0x3E, 0xC3, 0x40, 0xDC, 0x9B, 0xB2, 0x4A, 0xCE, 0xB7, 0x5B, 0xB1, 0xA8, 0x89, 0x56, 0xD1, 0x59), date(month: 7, year: 2024)),
            (k(0x23, 0xB7, 0x15, 0x1D, 0x6B, 0xDC, 0x4F, 0x0E, 0x98, 0xC8, 0x03, 0x4E, 0xB5, 0x85, 0x8B, 0xC1), date(month: 10, year: 2024)),

            // active keys; the final key will be used for encryption
            (k(0x23, 0xB7, 0x15, 0x1D, 0x6B, 0xDC, 0x4F, 0x0E, 0x98, 0xC8, 0x03, 0x4E, 0xB5, 0x85, 0x8B, 0xC1), date(month: 1, year: 2025)),
            (k(0x23, 0xB7, 0x15, 0x1D, 0x6B, 0xDC, 0x4F, 0x0E, 0x98, 0xC8, 0x03, 0x4E, 0xB5, 0x85, 0x8B, 0xC1), date(month: 4, year: 2025)),
            (k(0x23, 0xB7, 0x15, 0x1D, 0x6B, 0xDC, 0x4F, 0x0E, 0x98, 0xC8, 0x03, 0x4E, 0xB5, 0x85, 0x8B, 0xC1), date(month: 7, year: 2025)),
            (k(0x23, 0xB7, 0x15, 0x1D, 0x6B, 0xDC, 0x4F, 0x0E, 0x98, 0xC8, 0x03, 0x4E, 0xB5, 0x85, 0x8B, 0xC1), date(month: 10, year: 2025)),

            (k(0xF5, 0xE9, 0x48, 0xC0, 0x16, 0x4B, 0x49, 0xB0, 0xB0, 0x6A, 0xDB, 0x56, 0x27, 0x07, 0x3C, 0x37), date(month: 1, year: 2026)),
            (k(0x87, 0x6D, 0x0F, 0x56, 0x9A, 0x93, 0x4E, 0x1A, 0xB5, 0x86, 0xC5, 0xFD, 0x0C, 0xD2, 0x04, 0x98), date(month: 4, year: 2026)),
            (k(0x02, 0xAF, 0xDA, 0x82, 0x8A, 0xE7, 0x42, 0xB0, 0xA7, 0xA1, 0x56, 0x03, 0xC2, 0xC8, 0x1B, 0x87), date(month: 7, year: 2026)),
            (k(0xDF, 0x97, 0x7C, 0xEF, 0xB0, 0x72, 0x4B, 0x15, 0x8A, 0x3F, 0x69, 0xB1, 0x41, 0xC8, 0x62, 0xE1), date(month: 10, year: 2026)),

            // future keys (random; made using: `uuidgen -hdr`)

            (k(0x6C, 0x28, 0x37, 0xAB, 0xEB, 0xC9, 0x40, 0x20, 0x9E, 0x8C, 0xE7, 0xCA, 0xC2, 0xA5, 0x5C, 0x71), date(month: 1, year: 2027)),
            (k(0xA2, 0xC5, 0x3C, 0xEE, 0x9A, 0xF9, 0x46, 0xA7, 0xB0, 0x5E, 0x1A, 0x17, 0x33, 0x74, 0x82, 0x8D), date(month: 4, year: 2027)),
            (k(0x97, 0x34, 0x29, 0xF3, 0x73, 0xC0, 0x42, 0xB9, 0x86, 0x6A, 0xD6, 0xD3, 0x92, 0xED, 0x28, 0x53), date(month: 7, year: 2027)),
            (k(0x60, 0x51, 0x7D, 0xA5, 0xA2, 0x79, 0x4F, 0x7C, 0x84, 0xE1, 0xF0, 0x18, 0x44, 0x27, 0x8B, 0x2A), date(month: 10, year: 2027)),

            (k(0x02, 0x6A, 0x81, 0x1A, 0xF8, 0x4E, 0x4A, 0x82, 0x85, 0xAE, 0xA0, 0xE8, 0x9A, 0x46, 0x47, 0xAA), date(month: 1, year: 2028)),
            (k(0x69, 0xD1, 0x9F, 0x2A, 0x43, 0x58, 0x4E, 0x08, 0x9E, 0x59, 0x9D, 0xAA, 0x86, 0x3A, 0x46, 0xC0), date(month: 4, year: 2028)),
            (k(0x98, 0x18, 0x6A, 0x44, 0xF7, 0xF4, 0x46, 0xD8, 0xA8, 0x30, 0x28, 0xFC, 0xDF, 0x20, 0xF6, 0xBA), date(month: 7, year: 2028)),
            (k(0xF7, 0x96, 0xD4, 0xC5, 0x2F, 0x49, 0x4A, 0xE3, 0x92, 0x0E, 0xFC, 0x69, 0x99, 0xBB, 0xC8, 0xC5), date(month: 10, year: 2028)),

            (k(0x49, 0x0C, 0x39, 0xDF, 0x9C, 0x18, 0x4F, 0xBB, 0xB1, 0x13, 0xE4, 0xB9, 0xF6, 0x35, 0x48, 0x2E), date(month: 1, year: 2029)),
            (k(0x52, 0x55, 0xCE, 0x5A, 0x1A, 0x35, 0x45, 0x07, 0xA2, 0x1C, 0x2D, 0x9F, 0x79, 0x16, 0x48, 0x1F), date(month: 4, year: 2029)),
            (k(0xE5, 0xBE, 0xDC, 0x62, 0x79, 0x66, 0x4C, 0x9C, 0x9E, 0xDA, 0x54, 0x0A, 0xDC, 0xDC, 0x07, 0x48), date(month: 7, year: 2029)),
            (k(0x0D, 0x6B, 0x1B, 0x12, 0x1C, 0x39, 0x40, 0xD3, 0xA6, 0x64, 0x06, 0xEC, 0x43, 0x85, 0xF3, 0xEE), date(month: 10, year: 2029)),

            (k(0xDB, 0x80, 0x08, 0x55, 0x20, 0xC5, 0x44, 0x8E, 0xB9, 0xF1, 0xCF, 0x99, 0x16, 0x9D, 0x1A, 0xA3), date(month: 1, year: 2030)),
            (k(0xD2, 0x1C, 0x47, 0xDB, 0x50, 0x2E, 0x44, 0x57, 0xA3, 0xA8, 0x59, 0x42, 0xA6, 0x01, 0xB4, 0xEB), date(month: 4, year: 2030)),
            (k(0x23, 0xA5, 0x6F, 0xF6, 0x84, 0xB3, 0x42, 0x68, 0x91, 0xFF, 0x78, 0xEC, 0x70, 0xEC, 0x91, 0xF0), date(month: 7, year: 2030)),
            (k(0x30, 0x2A, 0x8D, 0x34, 0xEE, 0x80, 0x4E, 0xAF, 0xB6, 0x0F, 0xD6, 0x29, 0x78, 0x0E, 0xC3, 0xE8), date(month: 10, year: 2030)),
        ]

        func date(day: Int = 1, month: Int, year: Int) -> Date {
            DateComponents(calendar: Calendar.current, timeZone: TimeZone(secondsFromGMT: 0), year: year, month: month, day: day).date!
        }

        // always encypt using the most recent key whose date is greater than the current
        if encrypt {
            guard let currentKey = keyWheel.last(where: { ($1 ?? .distantFuture) <= Date.now }) else {
                throw LicenseError.noKeys
            }

            let key = SymmetricKey(data: currentKey.0)
            let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce ?? AES.GCM.Nonce())
            return sealedBox.combined ?? sealedBox.ciphertext
        }

        // for decryption, try each of the valid keys in turn until one of them works
        for (keyIndex, (keyData, expirationDate)) in keyWheel.enumerated().reversed() {
            do {
                guard keyData.count == 16 else { // kCCKeySizeAES128: 16-byte keys
                    throw LicenseError.invalidKey
                }

                guard let expirationDate else {
                    // a nil expiration date indicates that the key has been revoked and any licenses using that key are no longer valid
                    throw LicenseError.cryptKeyRevoked
                }

                let _ = expirationDate
                //if currentDate > expirationDate {
                //    throw LicenseError.cryptKeyExpired(date: expirationDate)
                //}

                let key = SymmetricKey(data: keyData)

                let sealedBox = try AES.GCM.SealedBox(combined: data)
                return try AES.GCM.open(sealedBox, using: key)
            } catch let error as LicenseError where error.isContentError {
                throw error // immediately re-throw the content error
            } catch let error { // as LicenseError where error.isContentError {
                // when we get to last (i.e., first) key, re-throw the error
                if keyIndex == 0 {
                    throw error
                }
            }
        }

        // we've exhaused the keywheel
        throw LicenseError.noKeys
    }
}

extension LicenseKey.LicenseType : ExpressibleByArgument {
}

/// The command that is run by "SkipKey", which can be used to create and verify Skip license keys
struct LicenseCommand: AsyncParsableCommand {
    public static var configuration = CommandConfiguration(
        commandName: "license",
        abstract: "Skip License Management",
        subcommands: [
            LicenseInfoCommand.self,
            LicenseUpdateCommand.self,

            // hidden commands
            LicenseGenerateCommand.self,
            LicenseModifyCommand.self,
        ])

    public init() {
    }

    struct KeyOutput : MessageEncodable {
        var id: String
        var type: LicenseKey.LicenseType?
        var expiration: Date
        var hostid: String?
        var key: String

        init(key: String, licenseKey: LicenseKey) {
            self.init(id: licenseKey.id, type: licenseKey.licenseType, expiration: licenseKey.expiration, hostid: licenseKey.hostid, key: key)
        }

        init (id: String, type: LicenseKey.LicenseType?, expiration: Date, hostid: String?, key: String) {
            self.id = id
            self.type = type
            self.expiration = expiration
            self.hostid = hostid
            self.key = key
        }

        func message(term: Term) -> String? {
            """
            id: \(id)
            type: \(type?.rawValue ?? "legacy")
            expiration: \(expiration)
            hostid: \(hostid ?? "")
            key: \(key)
            """
        }
    }

    struct LicenseUpdateCommand: SingleStreamingCommand {
        typealias Output = MessageBlock

        static var configuration = CommandConfiguration(
            commandName: "update",
            abstract: "Update the licence key file with the new license",
            //usage: "skip license update <licensekey>",
            discussion: """
            This command will update the ~/.skiptools/skipkey.env YAML with the specified license key.
            
            License keys can be obtained from https://skip.tools/pricing/ or by contacting support@skip.tools
            """,
            shouldDisplay: true)

        @OptionGroup(title: "Output Options", visibility: .hidden)
        var outputOptions: OutputOptions

        @Argument(help: ArgumentHelp("The license key to update"))
        var key: String

        func executeCommand() async throws -> MessageBlock {
            let licenseKey = try LicenseKey(licenseString: self.key)
            try validateLicense(licenseKey)

            let output = KeyOutput(key: key, licenseKey: licenseKey)

            let skiptoolsFolder = skipkeyFile.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: skiptoolsFolder, withIntermediateDirectories: true)

            var skipkeyFileContents = (try? String(contentsOf: skipkeyFile, encoding: .utf8)) ?? ""

            let keyline = try NSRegularExpression(pattern: "^[:space:]*SKIPKEY:", options: .anchorsMatchLines)
            skipkeyFileContents = keyline.stringByReplacingMatches(in: skipkeyFileContents, options: [], range: NSRange(location: 0, length: skipkeyFileContents.count), withTemplate: "# SKIPKEY:") // comment-out older licenses
            if !skipkeyFileContents.hasSuffix("\n") {
                skipkeyFileContents += "\n"
            }
            skipkeyFileContents.append("# license updated on \(Date().formatted(date: .abbreviated, time: .omitted)) with expiration: \(licenseKey.expiration.formatted(date: .abbreviated, time: .omitted))\n")
            skipkeyFileContents.append("SKIPKEY: \(key)\n")

            try skipkeyFileContents.write(to: skipkeyFile, atomically: false, encoding: .utf8)
            return MessageBlock(status: .pass, "Successfully updated \(licenseKeyLocationPath) with new license key:\n\(output.message(term: .plain) ?? "")")
        }
    }

    struct LicenseInfoCommand: SingleStreamingCommand {
        static var configuration = CommandConfiguration(
            commandName: "info",
            abstract: "Show key info",
            discussion: """
            This command will take the specified key argument (or the key specified in the ~/.skiptools/skipkey.env YAML file) and output information about the key like the expiration and associated host id.
            
            License keys can be obtained from https://skip.tools/pricing/ or by contacting support@skip.tools
            """,
            shouldDisplay: true)

        @Argument(help: ArgumentHelp("The license key to show info for"))
        var key: String?

        @OptionGroup(title: "Output Options", visibility: .hidden)
        var outputOptions: OutputOptions

        typealias Output = KeyOutput

        func executeCommand() async throws -> Output {
            //info("create key")
            if let key = self.key { // key specified on the command-line
                let licenseKey = try LicenseKey(licenseString: key)
                return KeyOutput(key: key, licenseKey: licenseKey)
            } else {
                let license = try loadSkipLicense()
                guard let licenseString = license.licenseString,
                      let license = license.license else {
                    throw error("No Skip.tools license key found at \(licenseKeyLocationPath)")
                }
                return KeyOutput(key: licenseString, licenseKey: license)
            }
        }
    }

    struct LicenseGenerateCommand: LicenseActionCommand {
        static var configuration = CommandConfiguration(commandName: "generate", abstract: "Generate a new key", shouldDisplay: false)

        @Option(name: [.customShort("i"), .long], help: ArgumentHelp("The identifier for the key", valueName: "id"))
        var id: String

        @Option(name: [.customShort("t"), .long], help: ArgumentHelp("The type of the license key", valueName: "type"))
        var type: LicenseKey.LicenseType

        @Option(name: [.customShort("e"), .long], help: ArgumentHelp("The ISO-8601 key expiration date", valueName: "date"))
        var expiration: String?

        @Option(name: [.customShort("d"), .long], help: ArgumentHelp("The number of days before expiration", valueName: "days"))
        var expirationDays: Int?

        @Option(name: [.customShort("h"), .long], help: ArgumentHelp("The hostid for the key", valueName: "hostid"))
        var hostid: String?

        @Option(name: [.long], help: ArgumentHelp("A hex-encoded 12-byte initialization vector", valueName: "nonce"))
        var nonce: String?

        @OptionGroup(title: "Output Options")
        var outputOptions: OutputOptions

        typealias Output = KeyOutput

        func executeCommand() async throws -> Output {
            try validateKeyGeneration()
            let exp = try parseExpirationArgument()
            let key = LicenseKey(id: id, expiration: exp, hostid: hostid, flags: type.licenseFlags)
            let iv = nonce.flatMap(Data.init(hexString:))
            if nonce != nil && iv?.count != 12 {
                throw LicenseError.invalidNonceFormat
            }
            let keyString = try key.licenseKeyString(iv: iv)
            return KeyOutput(id: key.id, type: key.licenseType, expiration: key.expiration, hostid: key.hostid, key: keyString)
        }
    }

    struct LicenseModifyCommand: LicenseActionCommand {
        static var configuration = CommandConfiguration(commandName: "modify", abstract: "Modify an existing key with the specified arguments", shouldDisplay: false)

        @Option(name: [.customShort("i"), .long], help: ArgumentHelp("The identifier for the key", valueName: "id"))
        var id: String?

        @Option(name: [.customShort("t"), .long], help: ArgumentHelp("The type of the license key", valueName: "type"))
        var type: LicenseKey.LicenseType?

        @Option(name: [.customShort("e"), .long], help: ArgumentHelp("The ISO-8601 key expiration date", valueName: "date"))
        var expiration: String?

        @Option(name: [.customShort("d"), .long], help: ArgumentHelp("The number of days before expiration", valueName: "days"))
        var expirationDays: Int?

        @Option(name: [.customShort("h"), .long], help: ArgumentHelp("The hostid for the key", valueName: "hostid"))
        var hostid: String?

        @Option(name: [.long], help: ArgumentHelp("A hex-encoded 12-byte initialization vector", valueName: "nonce"))
        var nonce: String?

        @OptionGroup(title: "Output Options")
        var outputOptions: OutputOptions

        @Argument(help: ArgumentHelp("The license key to modify"))
        var key: String

        typealias Output = KeyOutput

        func executeCommand() async throws -> Output {
            try validateKeyGeneration()
            let licenseKey = try LicenseKey(licenseString: self.key)
            let exp = expiration == nil && expirationDays == nil ? licenseKey.expiration : try parseExpirationArgument()
            let key = LicenseKey(id: id ?? licenseKey.id, expiration: exp, hostid: hostid ?? licenseKey.hostid, flags: type?.licenseFlags ?? licenseKey.flags)
            let iv = nonce.flatMap(Data.init(hexString:))
            if nonce != nil && iv?.count != 12 {
                throw LicenseError.invalidNonceFormat
            }
            let keyString = try key.licenseKeyString(iv: iv)
            return KeyOutput(id: key.id, type: key.licenseType, expiration: key.expiration, hostid: key.hostid, key: keyString)
        }
    }
}

/// A command that acts on a license key or can be used to generate a new one
protocol LicenseActionCommand: SingleStreamingCommand {
    var expiration: String? { get }
    var expirationDays: Int? { get }
    var nonce: String? { get }
}

extension LicenseActionCommand {
    fileprivate func validateKeyGeneration() throws {
        let keykey = ProcessInfo.processInfo.environment["SKIPKEY_KEY"] ?? self.nonce ?? ""
        // this is a simplistic method to prevent users from being able to generate their own keys without some effort
        // i.e.: keykey != "8BB57450F5084408903A4BC4"
        if Array((keykey.data(using: .utf16BigEndian) ?? Data()).reversed()) != [52, 0, 67, 0, 66, 0, 52, 0, 65, 0, 51, 0, 48, 0, 57, 0, 56, 0, 48, 0, 52, 0, 52, 0, 56, 0, 48, 0, 53, 0, 70, 0, 48, 0, 53, 0, 52, 0, 55, 0, 53, 0, 66, 0, 66, 0, 56, 0] {
            throw error("Operation prohibited")
        }
    }

    func parseExpirationArgument(maxDays: Int = 365) throws -> Date {
        func validateMaxDays(_ date: Date?) throws -> Date {
            guard let date = date else {
                throw error("No expiration date specified")
            }
            if date.timeIntervalSinceNow > (60 * 60 * 24 * 370) {
                throw error("Expiration date is beyond maximum")
            }
            return date
        }

        if let expiration {
            // permit dates without the time specifier (e.g., 2026-04-24)
            return try validateMaxDays(ISO8601DateFormatter().date(from: expiration)
                                       ?? ISO8601DateFormatter().date(from: expiration + "T00:00:00Z"))
        } else if let expirationDays {
            return try validateMaxDays(Date.now.addingTimeInterval(60 * 60 * 24 * Double(expirationDays)))
        } else {
            throw error("Either --expiration or --expiration-days must be specified")
        }
    }
}

struct SourceValidator {
    /// Scans the sources and returns the hashes, as well as checking for approved free license headers.
    @discardableResult static func scanSources(from sourceURLs: [URL], in pathExtensions: Set<String>, headerExpressions: [NSRegularExpression] = validLicenseHeaders) throws -> (unlicensedSources: [URL], sourceHashes: [URL: String]) {

        var sourceHashes: [URL: String] = [:]

        // we are above the threshold; if we have a license, validate it; otherwise scan the code and ensure that it contains an approved header regex
        var unmatchedHeaderURLs: [URL] = []
        for sourceURL in sourceURLs {
            var headers: [String] = []
            let contents = try Data(contentsOf: sourceURL)
            sourceHashes[sourceURL] = contents.SHA256Hash()

            // only scan files with the given path extension for a valid license
            if !pathExtensions.contains(sourceURL.pathExtension) {
                continue
            }

            String(data: contents, encoding: .utf8)?.enumerateLines { line, stop in
                if line.hasPrefix("//") && headers.count <= 15 { // scan the first 15 single-line header comments
                    headers.append(line.drop(while: { $0 == "/" }).trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    stop = true // only scan up to the final opening comment single-line comment
                }
            }

            // join together the header lines as a single string and match against all the expressions
            let headerString = headers.joined(separator: " ")
            let matches = headerExpressions.contains {
                $0.numberOfMatches(in: headerString, range: NSRange(headerString.startIndex..<headerString.endIndex, in: headerString)) > 0
            }

            // if none of the header expressions matched, then this is an unlicensed source
            if !matches {
                unmatchedHeaderURLs += [sourceURL]
            }
        }

        return (unlicensedSources: unmatchedHeaderURLs, sourceHashes: sourceHashes)
    }
}

extension StreamingCommand {
    /// Validate the license key if it is present in the tool or environment; otherwise scan the sources for approved license headers
    func createSourceHashes(validateLicense pathExtensions: Set<String>, isNativeModule: Bool, sourceURLs: [URL]) async throws -> [URL: String] {
        let (unlicensedSources, sourceHashes) = try SourceValidator.scanSources(from: sourceURLs.filter({ pathExtensions.contains($0.pathExtension) }), in: pathExtensions)

        // when the source code all passes the free license check (i.e., approved open-source license headers), just return the source hashes
        if unlicensedSources.isEmpty {
            return sourceHashes
        }

        try verifySkipInstallation(sourceFiles: unlicensedSources, isNativeModule: isNativeModule)

        return sourceHashes
    }

    /// The Homebrew Caskroom install location for Skip
    var skipHomebrewCaskroomFolder: String { ProcessInfo.homebrewRoot + "/Caskroom/skip" }

    /// The Homebrew Tap location for skiptools
    var skipHomebrewTapsFolder: String { ProcessInfo.homebrewRoot + "/Library/Taps/skiptools" }

    func checkSkipUpdated() {
        // check whether the locally-installed Homebrew version of Skip matches the current version; recommend upgrading if not
        let skipUpdatedMarkerFile = skipHomebrewCaskroomFolder + "/" + skipVersion + "/skip.artifactbundle/info.json"
        if !FileManager.default.fileExists(atPath: skipHomebrewCaskroomFolder) {
            warn("Skip installaton not found. See https://skip.tools and install with: brew install skiptools/skip/skip")
        } else if !FileManager.default.fileExists(atPath: skipUpdatedMarkerFile) {
            warn("Skip installation is out of date with skipstone plugin version \(skipVersion). Please upgrade by running: skip upgrade")
        }
    }

    /// Parse the license file and return information about the key
    func loadSkipLicense() throws -> (licenseString: String?, license: LicenseKey?, trialExpiration: Date, skipkeyFileSourcePath: Source.FilePath, skipkeyFileSourceRange: Source.Range?) {
        // Get the ~/.skiptools/ folder, throwing an error if it does not exist (it should have been created by `skip welcome` in the postinstall for `brew install skiptools/skip/skip`
        let skiptoolsFolder = skipkeyFile.deletingLastPathComponent()
        guard let skiptoolsInstallDate = try? skiptoolsFolder.resourceValues(forKeys: [.creationDateKey]).creationDate else {
            throw LicenseError.skipNotInstalled
        }

        // the install date is the minimum creation date of a set of folders that act as markers for when Skip was first installed on the machine
        let installDate = [
            skiptoolsFolder,
            URL(fileURLWithPath: skipHomebrewCaskroomFolder),
            URL(fileURLWithPath: skipHomebrewTapsFolder),
        ].compactMap({
            try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate
        }).min() ?? skiptoolsInstallDate

        let trialExpiration = installDate.addingTimeInterval(60 * 60 * 24 * 15) // 15-day implicit trial
        let skipkeyFileSourcePath = Source.FilePath(path: skipkeyFile.path)

        // fall back on a system environment "SKIPKEY" for potential CI usage
        var licenseString = ProcessInfo.processInfo.environment["SKIPKEY"]
        var skipkeyFileSourceRange: Source.Range? = nil

        // Load the `skipkey.env` file in ~/.skiptools/ for a license key
        if FileManager.default.fileExists(atPath: skipkeyFile.path) {
            do {
                let skipkeyData = try Data(contentsOf: skipkeyFile)
                let skipkeyLicenseLines = (String(data: skipkeyData, encoding: .utf8) ?? "").split(separator: "\n", omittingEmptySubsequences: false)

                // track the line where the "SKIPKEY" setting is located so any errors/warnings can highlight the correct line
                // if it is missing, select the end of the file by using the index of the count if lines
                let licenseKeyPos = Source.Position(line: (skipkeyLicenseLines.firstIndex(where: { $0.hasPrefix("SKIPKEY:") }) ?? skipkeyLicenseLines.count) + 1, column: 0)
                skipkeyFileSourceRange = Source.Range(start: licenseKeyPos, end: licenseKeyPos)

                let yaml = try YAML.parse(skipkeyData)
                if let license = yaml["SKIPKEY"]?.string, !license.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    licenseString = license
                }
            } catch {
                throw self.error("Unable to parse \(skipkeyFile.path); please ensure it is a valid YAML file and contains a 'SKIPKEY' property with a valid license key issued by https://skip.tools. Error: \(error.localizedDescription)", sourceFile: skipkeyFileSourcePath, sourceRange: skipkeyFileSourceRange)
            }
        }

        let license: LicenseKey? = try licenseString.flatMap {
            do {
                return try LicenseKey(licenseString: $0)
            } catch {
                // use failureReason to get information about JSON parse failures
                throw self.error("License key error: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
            }
        }

        return (licenseString, license, trialExpiration, skipkeyFileSourcePath, skipkeyFileSourceRange)
    }

    /// The number of days within which to start warning that a license is about to expire
    var licenseWarnDays: Int { 14 }

    fileprivate func validateLicense(_ license: LicenseKey, skipkeyFileSourcePath: Source.FilePath? = nil, skipkeyFileSourceRange: Source.Range? = nil) throws {
        // if the license key has a hostid encoded into it, then validate it against the current machine
        guard let hostid = license.hostid else {
            throw error("Skip license key validation failed: the host identifier is missing. Please contact support@skip.tools", sourceFile: skipkeyFileSourcePath, sourceRange: skipkeyFileSourceRange)
        }

        if hostid != ProcessInfo.processInfo.hostIdentifier {
            throw error("Skip license key validation failed: the host identifier is invalid. Please contact support@skip.tools", sourceFile: skipkeyFileSourcePath, sourceRange: skipkeyFileSourceRange)
        }
    }

    func verifySkipInstallation(sourceFiles: [URL], isNativeModule: Bool, against now: Date = Date.now) throws {
        checkSkipUpdated()

        let (_, license, trialExpiration, skipkeyFileSourcePath, skipkeyFileSourceRange) = try loadSkipLicense()

        if let license = license {
            if isNativeModule && false { // we no longer gate SkipFuse on professional license…
                switch license.licenseType {
                case .indie:
                    error("Skip native mode requires a paid license; please obtain a new license from https://skip.tools or contact support@skip.tools", sourceFile: skipkeyFileSourcePath, sourceRange: skipkeyFileSourceRange)
                    break
                case .trial, .eval:
                    // eval/trial licenses permit native mode
                    break
                case .smallbusiness, .professional:
                    // paid licenses permit native mode
                    break
                case .none:
                    // no flags in legacy license key, so we cannot distinguish between indie, smallbusiess, etc.
                    // TODO: make this an error after a grace period
                    warn("Skip license key needs upgrade in order to use native mode; please obtain a new license from https://skip.tools or contact support@skip.tools", sourceFile: skipkeyFileSourcePath, sourceRange: skipkeyFileSourceRange)
                }
            }

            let exp = DateFormatter.localizedString(from: license.expiration, dateStyle: .short, timeStyle: .none)
            let daysLeft = Int(ceil(license.expiration.timeIntervalSince(now) / (24 * 60 * 60)))

            try validateLicense(license, skipkeyFileSourcePath: skipkeyFileSourcePath, skipkeyFileSourceRange: skipkeyFileSourceRange)

            // allow padding the license expiration for up to 14 days
            if daysLeft < 0 {
                throw error("Skip license key expired on \(exp) – obtain a new license from https://skip.tools")
            } else if daysLeft <= licenseWarnDays { // warn when the license is about to expire
                warn("Skip license key will expire in \(daysLeft) day\(daysLeft == 1 ? "" : "s") on \(exp) – obtain a new license key from https://skip.tools", sourceFile: skipkeyFileSourcePath, sourceRange: skipkeyFileSourceRange)
            } else {
                info("Skip license key valid through \(exp)", sourceFile: skipkeyFileSourcePath, sourceRange: skipkeyFileSourceRange)
            }
        } else if now < trialExpiration {
            let exp = DateFormatter.localizedString(from: trialExpiration, dateStyle: .medium, timeStyle: .none)
            let daysLeft = Int(ceil(trialExpiration.timeIntervalSince(now) / (12 * 60 * 60)))
            if daysLeft <= 21 {
                warn("Skip trial will expire in \(daysLeft) day\(daysLeft == 1 ? "" : "s") on \(exp) – obtain a license key from https://skip.tools", sourceFile: skipkeyFileSourcePath, sourceRange: skipkeyFileSourceRange)
            }
        } else if !sourceFiles.isEmpty {
            // report on all the files that were missing the requisite headers
            let licenseError = LicenseError.unmatchedHeaders(sourceURLs: sourceFiles)
            error(licenseError.localizedDescription, sourceFile: skipkeyFileSourcePath, sourceRange: skipkeyFileSourceRange)
            throw licenseError
        }
    }
}


extension UUID {
    /// Take the bytes of the UUID and convert the data to base64
    @inlinable var base64String: String {
        Data([uuid.0, uuid.1, uuid.2, uuid.3, uuid.4, uuid.5, uuid.6, uuid.7, uuid.8, uuid.9, uuid.10, uuid.11, uuid.12, uuid.13, uuid.14, uuid.15]).base64EncodedString()
    }
}

/// A sequence that both `Data` and `String.UTF8View` conform to.
extension Data {
    func SHA256Hash() -> String {
        SHA256.hash(data: self).compactMap { String(format: "%02x", $0) }.joined()
    }
}

extension URL {
    /// Calculates the hash from a file URL and returns the SHA256 hash.
    func SHA256Hash(bufferSize: Int = 8192) throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: self)
        defer { try? fileHandle.close() }

        var hasher = SHA256()

        while let data = try fileHandle.read(upToCount: bufferSize) {
            hasher.update(data: data)
        }

        let digest = hasher.finalize()
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
