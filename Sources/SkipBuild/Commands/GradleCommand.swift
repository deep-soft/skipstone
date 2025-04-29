import Foundation
import ArgumentParser
import SkipSyntax
#if canImport(SkipDriveExternal)
import SkipDriveExternal

extension GradleCommand : GradleHarness { }
//fileprivate let gradleCommandEnabled = true
fileprivate let gradleCommandEnabled = false // advanced command, so do not display
#else
fileprivate let gradleCommandEnabled = false
#endif

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct GradleCommand: SkipCommand {
    static var configuration = CommandConfiguration(
        commandName: "gradle",
        abstract: "Launch the gradle build tool",
        shouldDisplay: gradleCommandEnabled)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @Option(help: ArgumentHelp("App package name", valueName: "package-name"))
    var package: String?

    @Option(help: ArgumentHelp("App module name", valueName: "ModuleName"))
    var module: String?

    @Option(help: ArgumentHelp("Project folder", valueName: "dir"))
    var project: String = "."

    @Argument(parsing: .allUnrecognized, help: ArgumentHelp("The arguments to pass to the gradle command"))
    var gradleArguments: [String]

    func run() async throws {
        // when the environment "SKIP_ACTION" is set to "none", completely ignore the gradle launch command; this is to provide backwards compatibility for pre-existing projects that do not have updated Xcode target's Build Phases "Run script" actions.
        // https://github.com/skiptools/skip/issues/408
        // TODO: should we just handle all the short-circuit envrionment variables here, like SKIP_ZERO, ENABLE_PREVIEWS, and ACTION="insall"?
        if ProcessInfo.processInfo.environment["SKIP_ACTION"] == "none" {
            print("note: skipping skip due to SKIP_ACTION none")
            return
        }

        do {
            try await withLatestVersionCheck(project: project) {
                #if !canImport(SkipDriveExternal)
                throw SkipDriveError(errorDescription: "SkipDrive not linked")
                #else
                try await self.gradleExec(in: projectRoot(forModule: module, packageName: package, projectFolder: project), moduleName: module, packageName: package, arguments: gradleArguments)
                #endif
            }
        } catch {
            // output error message
            print("\(error.localizedDescription)")
            throw error
        }
    }
}

extension SkipCommand {
    /// Perform the given block, first issuing a check for the latest version of Skip, and after the block is executed, issuing a message when the latest version is greater than the current version
    func withLatestVersionCheck(project: String, messageKind: Message.Kind = .warning, block: () async throws -> ()) async rethrows {
        // check for updates unless they have been explicitly disabled
        let checkUpdatesDisabled = ["false", "0", "no"].contains(ProcessInfo.processInfo.environment["SKIP_CHECK_UPDATES"]?.lowercased() ?? "")

        var latestRelease: String? = nil
        if !checkUpdatesDisabled {
            Task {
                do {
                    latestRelease = try await fetchLatestRelease()
                } catch {
                    // silently ignore update check failures (we may be offline)
                }
            }
        }

        try await block()

        // after gradle runs, issue a warning if Skip is not on the latest version
        if let latestRelease, isVersionOutdated(versionString: latestRelease) {
            // packagePath is like /opt/src/github/skiptools/skipapp-showcase/Darwin, so check root for Package.swift
            let packagePath = try? URL(fileURLWithPath: "../Package.swift", relativeTo: URL(fileURLWithPath: project)).resourceValues(forKeys: [.canonicalPathKey]).canonicalPath
            let sourceFile = packagePath.flatMap({ Source.FilePath(path: $0) })
            let sourceRange: Source.Range? = {
                // perform some very simplistic parsing to try to identify the location of the skip plugin version in the source file path
                guard let packagePath,
                      let packageContents = try? String(contentsOfFile: packagePath, encoding: .utf8) else {
                    return nil
                }
                // match e.g.: .package(url: "https://source.skip.tools/skip.git", from: "1.4.0"),
                guard let index = packageContents
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .firstIndex(where: { $0.contains(".package(url:") && ($0.contains("/skip.git\"") || $0.contains("/skip\"")) }) else {
                    return nil
                }
                let pos = Source.Position(line: index + 1, column: 0)
                return Source.Range(start: pos, end: pos)
            }()
            let msg = Message(kind: messageKind, message: "Skip update (\(latestRelease)) available with Xcode File / Packages / Update to Latest Package Versions", sourceFile: sourceFile, sourceRange: sourceRange)
            print(msg.formattedMessage)
        }
    }

    func isVersionOutdated(versionString: String) -> Bool {
        // SkipDriveExternal needed for Version
        #if canImport(SkipDriveExternal)
        if let latestVersion = try? Version(versionString: versionString),
           let currentVersion = try? Version(versionString: skipVersion) {
            if latestVersion >= currentVersion {
                return true
            }
        }
        return false
        #else
        return versionString != skipVersion
        #endif
    }
}

