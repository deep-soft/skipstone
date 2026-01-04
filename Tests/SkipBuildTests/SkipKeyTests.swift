import XCTest
@testable import SkipBuild
import SkipSyntax
import struct JSON.JSON
import TSCBasic

public class SkipKeyTests : XCTestCase {
    @discardableResult func licenseInfo(_ key: String) async throws -> JSON {
        let keyInfo = try await skipstone(["license", "info", "-jM", key]).json()
        return keyInfo
    }

    @discardableResult func genkey(_ args: String...) async throws -> JSON {
        let nonce = "8BB57450F5084408903A4BC4" // magic nonce for generation
        let keyInfo = try await skipstone(["license", "generate", "-jM", "--nonce", nonce] + args).json()
        return keyInfo
    }

    public func testLicenseGeneration() async throws {
        do {
            let key = try await genkey("--id", "ABC", "--expiration", "2027-01-01T00:00:00Z", "--type", "eval")
            let keyString = try XCTUnwrap(key["key"]?.string)
            // keys are not always identical when the generation date steps forward
            //XCTAssertEqual("SKP8BB57450F5084408903A4BC4F01DD5254F9925CB907CA513F3C304BB0B9499F9080521FCDBC3CF0B80598914231842B9B02EA5567431638F85A09E3C2BPKS", keyString.string)

            XCTAssertNotEqual(0, keyString.count)
            let info = try await licenseInfo(keyString)
            XCTAssertEqual("eval", info["type"])
        }

        do {
            // same test. but without the time part of the date
            let key = try await genkey("--id", "ABC", "--expiration", "2027-01-01", "--type", "indie")
            let keyString = try XCTUnwrap(key["key"]?.string)
            //XCTAssertEqual("SKP8BB57450F5084408903A4BC4F01DD5254F9F25CB907CA513F3C304BB0B9499F9080521FCDBC3CF0B8059891423EB0E1CF7C5A06F9AD0C198A192B6FE1DPKS", keyString.string)
            XCTAssertNotEqual(0, keyString.count)
            let info = try await licenseInfo(keyString)
            XCTAssertEqual("indie", info["type"])
        }
        do {
            let key = try await genkey("--id", "123", "--expiration", "2027-01-01T00:00:00Z", "--type", "smallbusiness")
            let keyString = try XCTUnwrap(key["key"]?.string)
            //XCTAssertEqual("SKP8BB57450F5084408903A4BC4F01DD5254F9325CB907CA513F3B374CB0B9499F9080521FCDBC3CF0B8059891423CB12C554D84CB86A3D904F26A8BF92DCPKS", keyString.string)
            XCTAssertNotEqual(0, keyString.count)
            let info = try await licenseInfo(keyString)
            XCTAssertEqual("smallbusiness", info["type"])
        }
    }

    public func testLicenseInfo() async throws {
        do {
            // revoked
            try await licenseInfo("SKP8EA6DB28FCC9E14E1D04F6F3C27446F85ACD05350C046F8733AA980980980F1EF3EACB3C49A6CB271FEE2E73F0B9D8C4D6C9D06C61222AC45E1581E40DF80BA8C62E2BEF4BF03D118A2A267967E5CAA0013CB44D0F3B85624C5C017EB2D1596D2B4B8F142CF0346E1B764E032FA3FD4301E28C96E163209A3549DD35996A11700073930CPKS")
        } catch {
            guard case LicenseError.licenseKeyRevoked = error else {
                throw error // expected
            }
        }

        let key = "SKP8BB57450F5084408903A4BC4F01DD5254F9325CB907CA513F3B374CB0B9499F9080521FCDBC3CF0B8059891423CB12C554D84CB86A3D904F26A8BF92DCPKS"

        for key in [
            key + "X",
            "X" + key,
        ] {
            do {
                try await licenseInfo(key)
                XCTFail("should not have been able to parse)")
            } catch {
                guard case LicenseError.invalidLicenseFormat = error else {
                    throw error // expected
                }
            }
        }

        let keyInfo = try await licenseInfo(key).json()

        XCTAssertEqual(key, keyInfo["key"]?.string)
        XCTAssertEqual("2027-01-01T00:00:00Z", keyInfo["expiration"]?.string)
        XCTAssertEqual("123", keyInfo["id"]?.string)
    }
}
