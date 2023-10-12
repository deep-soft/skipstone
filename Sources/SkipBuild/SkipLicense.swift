import Foundation
import SkipSyntax
import struct Universal.YAML

#if canImport(Crypto)
@_implementationOnly import Crypto
#else
@_implementationOnly import CryptoKit
#endif

/// the list of header match expressions that we permit for codebases above the given threshold
internal let validLicenseHeaders = [
    try! NSRegularExpression(pattern: #".*GNU(?:\sAffero|\sLesser)*\sGeneral\sPublic\sLicense.*"#)
]

struct SourceValidator {
    /// Scans the sources and returns the hashes, as well as checking for approved free license headers.
    @discardableResult static func scanSources(from sourceURLs: [URL], headerExpressions: [NSRegularExpression] = validLicenseHeaders) throws -> (unlicensedSources: [URL], sourceHashes: [URL: String]) {

        var sourceHashes: [URL: String] = [:]

        // we are above the threshold; if we have a license, validate it; otherwise scan the code and ensure that it contains an approved header regex
        var unmatchedHeaderURLs: [URL] = []
        for sourceURL in sourceURLs {
            var headers: [String] = []
            let contents = try String(contentsOf: sourceURL)
            sourceHashes[sourceURL] = contents.data(using: .utf8)?.SHA256Hash()

            contents.enumerateLines { line, stop in
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

extension FileHandle {
    /// Iterate over the lines in the file until the given closure returning false.
    /// This can be used instead of `bytes.lines` for platforms that do not support it (Linux).
    func iterateLines(separator: String = "\n", encoding: String.Encoding = .utf8, chunkSize: Int = 1024, with closure: (String) throws -> Bool) throws {
        guard let nl = separator.data(using: .utf8) else {
            throw CocoaError(.formatting)
        }
        var buffer = Data(capacity: chunkSize)
        var shouldContinue = true

        while shouldContinue {
            let data = readData(ofLength: chunkSize)
            if data.count == 0 {
                // End of file reached
                break
            }

            buffer.append(data)

            while let range = buffer.range(of: nl) {
                let lineData = buffer.subdata(in: 0..<range.lowerBound)

                if let line = String(data: lineData, encoding: encoding) {
                    shouldContinue = try closure(line)
                } else {
                    //print("Failed to convert line data to string.")
                }

                buffer.removeSubrange(0..<range.upperBound)

                if !shouldContinue {
                    // Halt iteration
                    break
                }
            }
        }
    }
}

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
            return "The skip.tools license in ~/.skiptools/skipkey.env is invalid."
        case .licenseExpired(expiration: let expiration):
            return "The skip.tools license in ~/.skiptools/skipkey.env expired on \(expiration) and must be renewed."
        case .noKeys:
            return "The skip.tools license in ~/.skiptools/skipkey.env has an internal error."
        case .invalidKey:
            return "The skip.tools license content in ~/.skiptools/skipkey.env was invalid."
        case .invalidData:
            return "The skip.tools license data was invalid."
        case .cryptorFailure(status: let status):
            return "Internal skip.tools license error: \(status)."
        case .cryptKeyExpired(date: let date):
            return "The skip.tools license was created with a version of the software that expired on \(date) and must be re-generated."
        case .cryptKeyRevoked:
            return "The skip.tools license needs to be re-constructed."
        case .licenseKeyRevoked:
            return "The skip.tools license needs to be re-generated."
        case .unmatchedHeaders(sourceURLs: let sourceURLs):
            return "No skip.tools license key found in ~/.skiptools/skipkey.env for transpilation of: \(sourceURLs.map(\.lastPathComponent).joined(separator: ", "))."
        case .licenseExpirationDateInvalid:
            return "The format of the expiration date is invalid."
        case .invalidNonceFormat:
            return "The format of the 12-byte hex-encoded nonce is invalid"
        case .skipNotInstalled:
            return "This project's Skip transpiler needs to be installed and configured – see https://skip.tools and install with: brew install skiptools/skip/skip"
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

extension StreamingCommand {
    /// Validate the license key if it is present in the tool or environment; otherwise scan the sources for approved license headers
    func createSourceHashes(validateLicense: Bool, sourceURLs: [URL], against now: Date = Date.now) async throws -> [URL: String] {
        let (unlicensedSources, sourceHashes) = try SourceValidator.scanSources(from: sourceURLs)

        // when the source code all passes the free license check (e.g., GPL license headers), just return the source hashes
        if unlicensedSources.isEmpty {
            return sourceHashes
        }

        /// Loads the `skipkey.env` file in ~/.skiptools/ for a license key
        func parseLicenseConfig() throws -> (Date, String?) {
            let (folder, installDate) = try skiptoolsFolder()
            let skipkeyFile = URL(fileURLWithPath: "skipkey.env", isDirectory: false, relativeTo: folder)
            if FileManager.default.fileExists(atPath: skipkeyFile.path) {
                let yaml = try YAML.parse(Data(contentsOf: skipkeyFile))
                if let license = yaml["SKIPKEY"]?.string, !license.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return (installDate, license)
                }
            }

            return (installDate, nil)
        }

        var (installDate, licenseString) = try parseLicenseConfig()
        let trialExpiration = installDate.addingTimeInterval(60 * 60 * 24 * 15) // 15-day implicit trial

        licenseString = licenseString ?? ProcessInfo.processInfo.environment["SKIPKEY"]

        let license = try licenseString.flatMap { try LicenseKey(licenseString: $0) }

        if let license = license {
            let exp = DateFormatter.localizedString(from: license.expiration, dateStyle: .short, timeStyle: .none)
            let daysLeft = Int(ceil(license.expiration.timeIntervalSince(now) / (12 * 60 * 60)))

            // if the license key has a hostid encoded into it, then validate it against the current machine
            if let hostid = license.hostid, hostid != ProcessInfo.processInfo.hostIdentifier {
                throw error("Skip license key validation failed – manage your skipkeys at https://skip.tools")
            }

            // allow padding the license expiration for up to 14 days
            if daysLeft < 0 {
                throw error("Skip license key expired on \(exp) – get a new skipkey from https://skip.tools")
            } else if daysLeft <= 10 { // warn when the license is about to expire
                warn("Skip license key will expire in \(daysLeft) day\(daysLeft == 1 ? "" : "s") on \(exp) – get a new skipkey from https://skip.tools")
            } else {
                info("Skip license key valid through \(exp)")
            }
        } else if now < trialExpiration {
            let exp = DateFormatter.localizedString(from: trialExpiration, dateStyle: .short, timeStyle: .none)
            let daysLeft = Int(ceil(trialExpiration.timeIntervalSince(now) / (12 * 60 * 60)))
            if daysLeft <= 10 {
                warn("Skip trial will expire in \(daysLeft) day\(daysLeft == 1 ? "" : "s") on \(exp) – get a skipkey from https://skip.tools")
            }
        } else if !unlicensedSources.isEmpty {
            // report on all the files that were missing the requisite headers
            let licenseError = LicenseError.unmatchedHeaders(sourceURLs: unlicensedSources)
            error(licenseError.localizedDescription, sourceFile: licenseError.sourceFile)
            throw licenseError
        }

        return sourceHashes
    }
}


/// The serialized license key that contains the appid and the expiration date, as well as any other information that needs to be encoded in the key.
struct LicenseKey : Equatable, Codable {
    let id: String
    let expiration: Date
    let hostid: String?

    // bookends make the key identifiable with a regular expression ("^SKP[0-9A-F]{10,}PKS$"), so we can be notified of leaked keys by key scanning services like:
    // https://docs.github.com/en/code-security/secret-scanning/secret-scanning-partner-program#the-secret-scanning-process
    static let (keyStart, keyEnd) = ("SKP", "PKS") // this can be anything, as long as it is somewhat unique

    /// Short keys to keep the license string as compact as possible
    enum CodingKeys: String, CodingKey {
        case id = "id"
        case expiration = "x"
        case hostid = "h"
    }

    @inlinable init(id: String, expiration: Date, hostid: String? = nil) {
        self.id = id
        self.expiration = expiration
        self.hostid = hostid
    }

    @inlinable init(licenseString: String) throws {
        let licenseData = try Self.parseLicenseContent(licenseString: licenseString)
        let jsonData = try aes(data: licenseData, encrypt: false)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        self = try decoder.decode(LicenseKey.self, from: jsonData)
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
        try Self.keyStart + aes(nonce: iv.flatMap(AES.GCM.Nonce.init(data:)), data: licenseJSON.utf8Data, encrypt: true).hexEncodedString().uppercased() + Self.keyEnd
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
        ]

        if revokedLicenseKeys.contains(licenseString) {
            throw LicenseError.licenseKeyRevoked
        }

        return data
    }
}

extension String {
    @inlinable func hexEncodedString() -> String {
        (data(using: .utf8) ?? Data()).hexEncodedString()
    }
}

extension Data {
    /// Create a data instance from a hex string
    @inlinable init?(hexString: String) {
        var hex = hexString
        // If the hex string has an odd number of characters, pad it with a leading zero
        if hex.count % 2 != 0 {
            hex = "0" + hex
        }
        // Create an array of bytes from the hex string
        var bytes = [UInt8]()

        for i in stride(from: 0, to: hex.count, by: 2) {
            let start = hex.index(hex.startIndex, offsetBy: i)
            let end = hex.index(start, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            let hexByte = hex[start..<end]
            if let byte = UInt8(hexByte, radix: 16) {
                bytes.append(byte)
            } else {
                return nil
            }
        }

        self = Data(bytes)
    }
}

extension Sequence where Element == UInt8 {
    /// Encodes a `Data` or `Array<UInt8>` as a hex string
    @inlinable func hexEncodedString() -> String {
        map { String(format: "%02hhx", $0) }.joined()
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

extension UUID {
    /// Take the bytes of the UUID and convert the data to base64
    @inlinable var base64String: String {
        Data([uuid.0, uuid.1, uuid.2, uuid.3, uuid.4, uuid.5, uuid.6, uuid.7, uuid.8, uuid.9, uuid.10, uuid.11, uuid.12, uuid.13, uuid.14, uuid.15]).base64EncodedString()
    }
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
func aes(nonce: AES.GCM.Nonce? = nil, keyBase64 keyString: String? = nil, data: Data, encrypt: Bool, currentDate: Date = Date()) throws -> Data {
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

        // active keys; the final key will be used for encryption
        (k(0xB2, 0xA9, 0x77, 0x4F, 0x6A, 0xD8, 0x42, 0x89, 0x81, 0xB2, 0x8F, 0x42, 0xD7, 0x65, 0x26, 0x38), date(month: 1, year: 2024)),
        (k(0x68, 0x1B, 0x87, 0x33, 0x03, 0xD9, 0x45, 0xBF, 0xA9, 0xFD, 0xA2, 0xD4, 0x5F, 0x06, 0x0C, 0xC8), date(month: 4, year: 2024)),
        (k(0x3E, 0xC3, 0x40, 0xDC, 0x9B, 0xB2, 0x4A, 0xCE, 0xB7, 0x5B, 0xB1, 0xA8, 0x89, 0x56, 0xD1, 0x59), date(month: 7, year: 2024)),
        (k(0x23, 0xB7, 0x15, 0x1D, 0x6B, 0xDC, 0x4F, 0x0E, 0x98, 0xC8, 0x03, 0x4E, 0xB5, 0x85, 0x8B, 0xC1), date(month: 10, year: 2024)),

        // future keys (random; made using: `uuidgen -hdr`)
        //(k(0x9F, 0x37, 0x41, 0xC5, 0xEF, 0xEF, 0x46, 0x69, 0xAB, 0x74, 0x3F, 0x0D, 0x23, 0xA8, 0x75, 0x40), date(month: 1, year: 2025)),
        //(k(0x37, 0x61, 0xCB, 0x3B, 0x26, 0x74, 0x40, 0x2B, 0x93, 0xA3, 0x8C, 0x15, 0x34, 0x76, 0x54, 0xE8), date(month: 4, year: 2025)),
        //(k(0xE7, 0x31, 0xA6, 0xE8, 0x57, 0x05, 0x4A, 0xD8, 0xAC, 0x8C, 0xF1, 0xD9, 0x16, 0xBD, 0x35, 0xB1), date(month: 7, year: 2025)),
        //(k(0x11, 0xC6, 0x75, 0x0F, 0x00, 0x78, 0x49, 0x78, 0x92, 0x44, 0xCC, 0x27, 0xD8, 0xC9, 0xF4, 0xAD), date(month: 10, year: 2025)),
        //(k(0x63, 0x26, 0x72, 0xF5, 0xAA, 0x40, 0x40, 0xA7, 0xB7, 0x36, 0xD5, 0x2B, 0x13, 0xED, 0x56, 0x5F), date(month: 1, year: 2026)),
    ]

    func date(day: Int = 1, month: Int, year: Int) -> Date {
        DateComponents(calendar: Calendar.current, timeZone: TimeZone(secondsFromGMT: 0), year: year, month: month, day: day).date!
    }

    // always encypt using the most recent key; for decryption, try each of the valid
    // keys in turn until one of them works
    for (keyIndex, (keyData, expirationDate)) in keyWheel.enumerated().reversed() {
        do {
            guard keyData.count == 16 else { // kCCKeySizeAES128: 16-byte keys
                throw LicenseError.invalidKey
            }

            guard let expirationDate else {
                // a nil expiration date indicates that the key has been revoked and any licenses using that key are no longer valid
                throw LicenseError.cryptKeyRevoked
            }

            if currentDate > expirationDate {
                throw LicenseError.cryptKeyExpired(date: expirationDate)
            }

            let key = SymmetricKey(data: keyData)

            if encrypt {
                let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce ?? AES.GCM.Nonce())
                return sealedBox.combined ?? sealedBox.ciphertext
            } else {
                let sealedBox = try AES.GCM.SealedBox(combined: data)
                return try AES.GCM.open(sealedBox, using: key)
            }
        } catch let error as LicenseError where error.isContentError {
            // when we get to last (i.e., first) key, re-throw the error
            if keyIndex == 0 {
                throw error
            }
        }
    }

    // we've exhaused the keywheel
    throw LicenseError.noKeys
}

/// Returns the ~/.skiptools/ folder, throwing an error if it does not exist (it should have been created by `skip welcome` in the postinstall for `brew install skiptools/skip/skip`
func skiptoolsFolder() throws -> (URL, Date) {
    let folder = URL(fileURLWithPath: ".skiptools", relativeTo: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true))
    guard let installDate = try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate else {
        throw LicenseError.skipNotInstalled
    }
    return (folder, installDate)
}

