@testable import SkipSyntax
import XCTest

final class PluginTests: XCTestCase {
    func testTestPlugin() async throws {
        try await check(swift: """
        import XCTest

        class TestCase: XCTestCase {
            func testSomeTest() throws {
            }

            func testSomeOtherTest() throws {
            }

            static func testDoNotTestStatic() throws {
            }
        }
        """, kotlin: """
        import skip.unit.*

        internal open class TestCase: XCTestCase {
            @Test internal open fun testSomeTest() {
            }
        
            @Test internal open fun testSomeOtherTest() {
            }

            companion object {

                internal fun testDoNotTestStatic() {
                }
            }
        }
        """, plugins: [TestCaseAnnotationPlugin()])
    }
}

class TestCaseAnnotationPlugin: KotlinPlugin {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        if let codebaseInfo = translator.codebaseInfo {
            syntaxTree.root.visit { visit($0, codebaseInfo: codebaseInfo) }
        }
    }

    private func visit(_ node: KotlinSyntaxNode, codebaseInfo: CodebaseInfo.Context) -> VisitResult<KotlinSyntaxNode> {
        if let functionDeclaration = node as? KotlinFunctionDeclaration {
            if !functionDeclaration.isStatic && !functionDeclaration.isGlobal && functionDeclaration.extends == nil {
                functionDeclaration.annotations += ["@Test"]
            }
        }
        return .recurse(nil)
    }
}

