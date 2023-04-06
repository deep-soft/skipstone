import Foundation
import SkipSyntax

struct SourceValidator {
    /// Scans the sources at the given URLs above a total given codebase size for an approved header comments that match the list of header expressions.
    @discardableResult static func scanSources(from sourceURLs: [URL], codebaseThreshold: Int, headerExpressions: [NSRegularExpression]) async throws -> (size: Int, validate: Bool) {
        // get the total codebase size (in bytes)
        let codebaseSize = try sourceURLs.compactMap { try $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }.reduce(0, +)
        if codebaseSize < codebaseThreshold {
            // for small codebases below the threshold don't bother checking anything
            return (codebaseSize, false)
        }

        #if !canImport(CommonCrypto)
        return (codebaseSize, false)
        #else
        // we are above the threshold; if we have a license, vallidate it; otherwise scan the code and ensure that it contains an approved head expression
        var unmatchedHeaderURLs: [URL] = []
        for sourceURL in sourceURLs {
            var headers: [String] = []
            let handle = try FileHandle(forReadingFrom: sourceURL)
            defer { try? handle.close() }
            for try await line in handle.bytes.lines {
                if !line.hasPrefix("//") {
                    break // only scan up to the final opening comment
                } else {
                    headers.append(line.drop(while: { $0 == "/" }).trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }

            // join together the header lines as a single string and match against all the expressions
            let headerString = headers.joined(separator: " ")
            let matches = headerExpressions.contains {
                $0.numberOfMatches(in: headerString, range: NSRange(headerString.startIndex..<headerString.endIndex, in: headerString)) > 0
            }

            // if none of the header expressions matched, then this is an unmatched source
            if !matches {
                unmatchedHeaderURLs += [sourceURL]
            }
        }

        if !unmatchedHeaderURLs.isEmpty {
            // report on all the files that were missing the requisite headers
            throw LicenseError.unmatchedHeaders(sourceURLs: unmatchedHeaderURLs, codebaseThreshold: codebaseThreshold)
        }

        return (codebaseSize, true)
        #endif
    }
}


@usableFromInline enum LicenseError: LocalizedError {
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
    case unmatchedHeaders(sourceURLs: [URL], codebaseThreshold: Int)
    /// This platform does not support the required encryption frameworks
    case cryptoUnsupported

    @usableFromInline var errorDescription: String? {
        switch self {
        case .invalidLicenseFormat:
            return "The Skip license is in an invalid format. Please ensure that the license key is the exact string that was provided to you by the vendor, or contact support."
        case .licenseExpired(expiration: let expiration):
            return "The Skip license expired on \(expiration) and must be renewed."
        case .noKeys:
            return "The Skip license has an internal error. Please contact support."
        case .invalidKey:
            return "The Skip license content was invalid. Please contact support."
        case .invalidData:
            return "The Skip license data was invalid. Please contact support."
        case .cryptorFailure(status: let status):
            return "Internal Skip license error: \(status). Please contact support."
        case .cryptKeyExpired(date: let date):
            return "The Skip license was created with a version of the software that expired on \(date) and must be re-generated. Please contact support."
        case .cryptKeyRevoked:
            return "The Skip license needs to be re-constructed. Please contact support."
        case .licenseKeyRevoked:
            return "The Skip license needs to be re-generated. Please contact support."
        case .unmatchedHeaders(sourceURLs: let sourceURLs, codebaseThreshold: let codebaseThreshold):
            return "All source files in codebases over \(ByteCountFormatter.string(fromByteCount: .init(codebaseThreshold), countStyle: .memory)) must contain a free software license header which is missing from: \(sourceURLs.map(\.lastPathComponent).formatted(.list(type: .and)))."
        case .cryptoUnsupported:
            return "The Skip license cannot be validated on this platform. Please contact support."
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
        case .unmatchedHeaders(let urls, _):
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
struct LicenseKey : Equatable, Codable {
    let id: String
    let expiration: Date

    // bookends make the key identifiable with a regular expression ("^SKP[0-9A-F]{10,}PKS$"), so we can be notified of leaked keys by key scanning services like:
    // https://docs.github.com/en/code-security/secret-scanning/secret-scanning-partner-program#the-secret-scanning-process
    static let (keyStart, keyEnd) = ("SKP", "PKS") // this can be anything, as long as it is somewhat unique

    /// Short keys to keep the license string as compact as possible
    enum CodingKeys: String, CodingKey {
        case id = "id"
        case expiration = "x"
    }

    @inlinable init(id: String, expiration: Date) {
        self.id = id
        self.expiration = expiration
    }

    @inlinable init(licenseString: String) throws {
        #if !canImport(CommonCrypto)
        throw LicenseError.cryptoUnsupported
        #else
        let licenseData = try Self.parseLicenseContent(licenseString: licenseString)
        let jsonData = try aes(data: licenseData, encrypt: false)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        self = try decoder.decode(LicenseKey.self, from: jsonData)
        #endif
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

    /// Returns the encrypted license string
    @inlinable var licenseKeyString: String {
        get throws {
            #if !canImport(CommonCrypto)
            throw LicenseError.cryptoUnsupported
            #else
            try Self.keyStart + aes(data: licenseJSON.utf8Data, encrypt: true).hexEncodedString().uppercased() + Self.keyEnd
            #endif
        }
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

    @inlinable func hexEncodedString() -> String {
        map { String(format: "%02hhx", $0) }.joined()
    }
}

extension UUID {
    /// Take the bytes of the UUID and convert the data to base64
    @inlinable var base64String: String {
        Data([uuid.0, uuid.1, uuid.2, uuid.3, uuid.4, uuid.5, uuid.6, uuid.7, uuid.8, uuid.9, uuid.10, uuid.11, uuid.12, uuid.13, uuid.14, uuid.15]).base64EncodedString()
    }
}

#if canImport(CommonCrypto)
import CommonCrypto

/// Takes the AES128 base64 key string as a String argument, the Data to encrypt or decrypt, and a boolean flag called encrypt that indicates whether the function should encrypt or decrypt the data. The function returns a Data object containing the encrypted or decrypted data.
///
/// The function first checks that the key is valid by decoding it from base64 and ensuring that it is the correct length. If the key is invalid, the function throws an invalidKey error.
///
/// - Parameters:
///   - keyBase64: the base64-encoded key
///   - data: the data to encrypt or decrypt
///   - encrypt: whether the data should be encrypted or decrypted
/// - Returns: the encrypted or decrypted data
@inlinable func aes(keyBase64 keyString: String? = nil, data: Data, encrypt: Bool, currentDate: Date = Date()) throws -> Data {
    // a wheel of AES-128 encryption/decryption keys that is meant to be rotated periodically in conjunction with the expiration scheme of the license that it encrypts
    // The most recent key will always be used to encrypt data, but older keys will be attempted for decryption. This allows older (and possibly compromised) keys to eventually be rotated out and expired after such time that any license that would have been encoded would have been expired anyway.
    // The active (i.e., most recent) key will be the one the order fulfillment provider should be configured to issue for future orders (e.g., https://fastspring.com/docs/license-key-fulfillments/#anchor-script)
    let keyWheel = [
        // revoked keys; any license encrypted with one of these keys will be considered invalid and the user will need to contact the vendor to obtain a new key
        ("DVGp7DB5SBqS+yNKye1ypg==", nil),
        ("zzWEgBtKQ3GEeUkDwLRWNQ==", nil),

        // active keys; the final key will be used for encryption
        ("Frhe03QaQqa5/Sm/gG4j4w==", date(month: 1, year: 2024)),
        ("W4FTzOHqQ/eukXs5o6b45w==", date(month: 4, year: 2024)),
        ("2nyci93lQy61XxnT3rMe9w==", date(month: 7, year: 2024)),
        ("HReU8jDRQUaF1h8cSHc4cg==", date(month: 10, year: 2024)),

        // future keys (random; created with: `print(UUID.randomUUID.base64String)`)

        //("6G+f+F0pSPKPWIQvDj8Cow==", date(month: 1, year: 2025)),
        //("A5zVrNFtQ0m9i8eX/7jEBw==", date(month: 4, year: 2025)),
        //("qhTg/vZ/TkqWHQ3lu79Q2A==", date(month: 7, year: 2025)),
        //("9NSw5y6/QrWrUPAq5aBTHA==", date(month: 10, year: 2025)),
        //("1DqVToJ5QhGiF4c9jiKNdg==", date(month: 1, year: 2026)),
    ]

    func date(day: Int = 1, month: Int, year: Int) -> Date {
        DateComponents(calendar: Calendar.current, year: year, month: month, day: day).date!
    }

    // always encypt using the most recent key; for decryption, try each of the valid
    // keys in turn until one of them works
    for (keyIndex, (keyBase64, expirationDate)) in keyWheel.enumerated().reversed() {
        do {
            guard let keyData = Data(base64Encoded: keyBase64), keyData.count == kCCKeySizeAES128 else {
                throw LicenseError.invalidKey
            }

            let ivSize = kCCBlockSizeAES128
            let keySize = kCCKeySizeAES128
            let options = CCOptions(kCCOptionPKCS7Padding)

            var numBytedMoved: Int = 0

            var buffer = [UInt8](repeating: 0, count: data.count + ivSize)

            // the initialization vector must be the same as the provider that performs the license encryption (which I'm guessing is all zeros)
            let iv = [UInt8](repeating: 0, count: ivSize) // zero IV
            // random hardwired initialization vector
            // let iv: [UInt8] = [ 8, 9, 34, 111, 53, 65, 98, 4, 6, 0, 83, 20, 53, 11, 64, 1 ]

            let cryptorStatus = keyData.withUnsafeBytes { keyBytes in
                iv.withUnsafeBytes { ivBytes in
                    data.withUnsafeBytes { dataBytes in
                        CCCrypt(encrypt ? CCOperation(kCCEncrypt) : CCOperation(kCCDecrypt),
                                CCAlgorithm(kCCAlgorithmAES),
                                options,
                                keyBytes.baseAddress, keySize,
                                ivBytes.baseAddress,
                                dataBytes.baseAddress, data.count,
                                &buffer, buffer.count,
                                &numBytedMoved)
                    }
                }
            }

            guard cryptorStatus == kCCSuccess else {
                throw LicenseError.cryptorFailure(status: cryptorStatus)
            }

            guard let expirationDate else {
                // a nil expiration date indicates that the key has been revoked and any licenses using that key are no longer valid
                throw LicenseError.cryptKeyRevoked
            }

            if currentDate > expirationDate {
                throw LicenseError.cryptKeyExpired(date: expirationDate)
            }
            return Data(buffer[..<numBytedMoved])
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
#endif

