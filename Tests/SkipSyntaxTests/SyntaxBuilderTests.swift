@testable import SkipSyntax
import SwiftSyntax
import SwiftSyntaxBuilder
import Universal
import XCTest

// These tests are copied from https://github.com/apple/swift-syntax/tree/main/Tests/SwiftSyntaxBuilderTest
// They test the creation of a Swift syntax tree using the builder syntax and verify that the syntax generates to the expected Swift.
// Kotlin syntax is additionally expected from all non-deprectated test functions as the third argument to `AssertBuildResult`.
// E.g., to add Kotlin verification to `testDoStmtWithPostfixQuestionMark`, first de-deprecate it and add the `kotlin:` parameter with the anticipated Kotlin source to the `AssertBuildResult` invocation(s).

extension XCTestCase {
    /// This `AssertBuildResult` function is deprecated becase the caller has not yet specified the Kotlin they expect to be generated.
    @available(*, deprecated, message: "need to add expected kotlin")
    func AssertBuildResult(_ buildable: SyntaxProtocol, _ swift: String, trimTrailingWhitespace: Bool = true, function: StaticString = #function, line: UInt = #line) {
        AssertBuildResult(buildable, swift, kotlin: nil, trimTrailingWhitespace: trimTrailingWhitespace, function: function, line: line)
    }

    /// Checks that the given `SyntaxProtocol` generates the expected swift, and that that swift matches the specified Kotlin.
    ///
    /// Example: `AssertBuildResult(ArrayExprSyntax { for i in 1...4 { ArrayElementSyntax(expression: IntegerLiteralExprSyntax(i)) } }, "[1, 2, 3, 4]", kotlin: "arrayOf(1, 2, 3, 4)")`
    func AssertBuildResult(_ buildable: SyntaxProtocol, _ swift: String, kotlin: String!, trimTrailingWhitespace: Bool = true, function: StaticString = #function, line: UInt = #line) {
        func trim(_ string: any StringProtocol) -> String {
            trimTrailingWhitespace ? string.description.trimmingCharacters(in: .whitespacesAndNewlines) : string.description
        }

        let generatedSwift = trim(buildable.formatted().description)
        let expectedSwift = trim(swift)

        // in order to handle inconsistent generated indentation, we compare based on trimmed lines
        if generatedSwift.split(separator: "\n").map(trim) != expectedSwift.split(separator: "\n").map(trim) {
            XCTAssertEqual(generatedSwift, expectedSwift, line: line)
        }

        if let kotlin = kotlin {
            XCTAssertEqual(trim(buildable.toKotlin()), trim(kotlin), line: line)
        } else {
            // throw XCTSkip("No kotlin transpilation to check", line: line)
            print("Skipping transpilation check in \(function):\(line)")
        }
    }
}

extension SyntaxProtocol {
    /// Converts this Swift syntax to Kotlin.
    func toKotlin(codebaseInfo: KotlinCodebaseInfo? = nil, trimImports: Bool = true) -> String {
        // FIXME: rather than re-parsing from the formatted source, we should just use the syntax tree directly
        let tree = SyntaxTree(source: Source(file: Source.File(path: ""), content: self.formatted().description))
        let translator = KotlinTranslator(syntaxTree: tree)
        let codebaseInfo = codebaseInfo ?? KotlinCodebaseInfo()
        let result = translator.transpile(codebaseInfo: codebaseInfo)
        if trimImports {
            return result.output.content
                .split(separator: "\n")
                .filter({ !$0.hasPrefix("import ") })
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            return result.output.content
        }
    }
}

final class ArrayExprTests: XCTestCase {
  @available(*, deprecated) func testPlainArrayExpr() {
    let buildable = ArrayExprSyntax {
      for i in 1...4 {
        ArrayElementSyntax(expression: IntegerLiteralExprSyntax(i))
      }
    }
    AssertBuildResult(buildable, "[1, 2, 3, 4]", kotlin: "arrayOf(1, 2, 3, 4)")
  }

  @available(*, deprecated) func testMultilineArrayLiteral() {
    let builder = ExprSyntax(
      """
      [
        1,
        #"2"3"#,
        4,
      "五",
      ]
      """
    )
    AssertBuildResult(
      builder,
      """
      [
          1,
          #"2"3"#,
          4,
          "五",
      ]
      """
    )
  }
}

final class BooleanLiteralTests: XCTestCase {
    @available(*, deprecated) func testBooleanLiteral() {
    let testCases: [UInt: (BooleanLiteralExprSyntax, String)] = [
      #line: (BooleanLiteralExprSyntax(booleanLiteral: .keyword(.true)), "true"),
      #line: (BooleanLiteralExprSyntax(booleanLiteral: .keyword(.false)), "false"),
      #line: (BooleanLiteralExprSyntax(true), "true"),
      #line: (BooleanLiteralExprSyntax(false), "false"),
      #line: (true, "true"),
      #line: (false, "false"),
    ]

    for (line, testCase) in testCases {
      let (builder, expected) = testCase
      AssertBuildResult(builder, expected, line: line)
    }
  }
}

final class BreakStmtSyntaxTests: XCTestCase {
  @available(*, deprecated) func testBreakStmtSyntax() {
    let testCases: [UInt: (StmtSyntax, String)] = [
      #line: (BreakStmtSyntax().as(StmtSyntax.self)!, "break"),
      #line: (StmtSyntax("break"), "break"),
    ]

    for (line, testCase) in testCases {
      let (builder, expected) = testCase
      AssertBuildResult(builder, expected, trimTrailingWhitespace: false, line: line)
    }
  }
}

final class ClassDeclSyntaxTests: XCTestCase {
  @available(*, deprecated) func testThrowableClassWithStringInterpolation() throws {
    let buildable = try ClassDeclSyntax("class Foo") {
      try FunctionDeclSyntax("func foo() -> String") {
        StmtSyntax(#"return "hello world""#)
      }
    }

    AssertBuildResult(
      buildable,
      """
      class Foo {
          func foo() -> String {
              return "hello world"
          }
      }
      """
    )
  }

  @available(*, deprecated) func testThrowableClass() throws {
    let buildable = try ClassDeclSyntax(identifier: .identifier("Foo")) {
      try FunctionDeclSyntax("func foo() -> String") {
        StmtSyntax(#"return "hello world""#)
      }
    }

    AssertBuildResult(
      buildable,
      """
      class Foo {
          func foo() -> String {
              return "hello world"
          }
      }
      """
    )
  }
}

final class ClosureExprTests: XCTestCase {
  @available(*, deprecated) func testClosureExpr() {
    let buildable = ClosureExprSyntax(
      signature: ClosureSignatureSyntax(
        input: .simpleInput(
          ClosureParamListSyntax {
            ClosureParamSyntax(name: .identifier("area"))
          }
        )
      )
    ) {}

    AssertBuildResult(
      buildable,
      """
      {area in
      }
      """
    )
  }
}

final class CollectionNodeFlatteningTests: XCTestCase {
  @available(*, deprecated) func test_FlattenCodeBlockItemListWithBuilder() {
    let leadingTrivia = Trivia.unexpectedText("␣")

    @CodeBlockItemListBuilder
    func buildInnerCodeBlockItemList() -> CodeBlockItemListSyntax {
      FunctionCallExprSyntax(callee: ExprSyntax("innerBuilder"))
    }

    @CodeBlockItemListBuilder
    func buildOuterCodeBlockItemList() -> CodeBlockItemListSyntax {
      FunctionCallExprSyntax(callee: ExprSyntax("outerBuilder"))

      buildInnerCodeBlockItemList()
    }

    let codeBlock = CodeBlockSyntax(leadingTrivia: leadingTrivia) {
      FunctionCallExprSyntax(callee: ExprSyntax("outsideBuilder"))
      buildOuterCodeBlockItemList()
    }

    AssertBuildResult(
      codeBlock,
      """
      ␣{
          outsideBuilder()
          outerBuilder()
          innerBuilder()
      }
      """
    )
  }
}

final class CustomAttributeTests: XCTestCase {
  @available(*, deprecated) func testCustomAttributeConvenienceInitializer() {
    let testCases: [UInt: (AttributeSyntax, String)] = [
      #line: (AttributeSyntax(attributeName: TypeSyntax("Test")), "@Test"),
      #line: (AttributeSyntax("WithParens") {}, "@WithParens()"),
      #line: (
        AttributeSyntax("WithArgs") {
          TupleExprElementSyntax(expression: ExprSyntax("value1"))
          TupleExprElementSyntax(label: "labelled", expression: ExprSyntax("value2"))
        }, "@WithArgs(value1, labelled: value2)"
      ),
    ]

    for (line, testCase) in testCases {
      let (builder, expected) = testCase
      AssertBuildResult(builder, expected, line: line)
    }
  }
}

final class DictionaryExprTests: XCTestCase {
  func testPlainDictionaryExpr() {
    let buildable = DictionaryExprSyntax {
      for i in 1...3 {
        DictionaryElementSyntax(keyExpression: IntegerLiteralExprSyntax(i), valueExpression: IntegerLiteralExprSyntax(i))
      }
    }
    AssertBuildResult(buildable, "[1: 1, 2: 2, 3: 3]", kotlin: "dictionaryOf(Pair(1, 1), Pair(2, 2), Pair(3, 3))")
  }

  func testEmptyDictionaryExpr() {
    let buildable = DictionaryExprSyntax()
    AssertBuildResult(buildable, "[:]", kotlin: "dictionaryOf()")
  }

  @available(*, deprecated) func testMultilineDictionaryLiteral() {
    let builder = ExprSyntax(
      """
      [
        1:1,
      2: "二",
        "three": 3,
      4:
        #"f"o"u"r"#,
      ]
      """
    )
    AssertBuildResult(
      builder,
      """
      [
          1: 1,
          2: "二",
          "three": 3,
          4:
              #"f"o"u"r"#,
      ]
      """
    )
  }
}

final class DoStmtTests: XCTestCase {
  @available(*, deprecated) func testDoStmt() {
    let buildable = DoStmtSyntax(
      body: CodeBlockSyntax(statementsBuilder: {
        TryExprSyntax(expression: FunctionCallExprSyntax(callee: ExprSyntax("a.b")))
      }),
      catchClauses: [
        CatchClauseSyntax(
          CatchItemListSyntax {
            CatchItemSyntax(pattern: PatternSyntax("Error1"))
            CatchItemSyntax(pattern: PatternSyntax("Error2"))
          }
        ) {
          FunctionCallExprSyntax(callee: ExprSyntax("print")) {
            TupleExprElementSyntax(expression: StringLiteralExprSyntax(content: "Known error"))
          }
        },
        CatchClauseSyntax(
          CatchItemListSyntax {
            CatchItemSyntax(
              pattern: PatternSyntax("Error3"),
              whereClause: WhereClauseSyntax(guardResult: ExprSyntax("error.isError4"))
            )
          }
        ) {
          ThrowStmtSyntax(expression: ExprSyntax("Error4.error3"))
        },
        CatchClauseSyntax {
          FunctionCallExprSyntax(callee: ExprSyntax("print")) {
            TupleExprElementSyntax(expression: ExprSyntax("error"))
          }
        },
      ]
    )

    AssertBuildResult(
      buildable,
      """
      do {
          try a.b()
      } catch Error1, Error2 {
          print("Known error")
      } catch Error3 where error.isError4 {
          throw Error4.error3
      } catch {
          print(error)
      }
      """
    )
  }

  @available(*, deprecated) func testDoStmtWithExclamationMark() {
    let buildable = DoStmtSyntax(
      body: CodeBlockSyntax(statementsBuilder: {
        TryExprSyntax(questionOrExclamationMark: .exclamationMarkToken(), expression: FunctionCallExprSyntax(callee: ExprSyntax("a.b")))
      }),
      catchClauses: [
        CatchClauseSyntax(
          CatchItemListSyntax {
            CatchItemSyntax(pattern: PatternSyntax("Error1"))
            CatchItemSyntax(pattern: PatternSyntax("Error2"))
          }
        ) {
          FunctionCallExprSyntax(callee: ExprSyntax("print")) {
            TupleExprElementSyntax(expression: StringLiteralExprSyntax(content: "Known error"))
          }
        },
        CatchClauseSyntax(
          CatchItemListSyntax {
            CatchItemSyntax(
              pattern: PatternSyntax("Error3"),
              whereClause: WhereClauseSyntax(guardResult: ExprSyntax("error.isError4"))
            )
          }
        ) {
          ThrowStmtSyntax(expression: ExprSyntax("Error4.error3"))
        },
        CatchClauseSyntax {
          FunctionCallExprSyntax(callee: ExprSyntax("print")) {
            TupleExprElementSyntax(expression: ExprSyntax("error"))
          }
        },
      ]
    )

    AssertBuildResult(
      buildable,
      """
      do {
          try! a.b()
      } catch Error1, Error2 {
          print("Known error")
      } catch Error3 where error.isError4 {
          throw Error4.error3
      } catch {
          print(error)
      }
      """
    )
  }

  @available(*, deprecated) func testDoStmtWithPostfixQuestionMark() {
    let buildable = DoStmtSyntax(
      body: CodeBlockSyntax(statementsBuilder: {
        TryExprSyntax(questionOrExclamationMark: .postfixQuestionMarkToken(), expression: FunctionCallExprSyntax(callee: ExprSyntax("a.b")))
      }),
      catchClauses: [
        CatchClauseSyntax(
          CatchItemListSyntax {
            CatchItemSyntax(pattern: PatternSyntax("Error1"))
            CatchItemSyntax(pattern: PatternSyntax("Error2"))
          }
        ) {
          FunctionCallExprSyntax(callee: ExprSyntax("print")) {
            TupleExprElementSyntax(expression: StringLiteralExprSyntax(content: "Known error"))
          }
        },
        CatchClauseSyntax(
          CatchItemListSyntax {
            CatchItemSyntax(
              pattern: PatternSyntax("Error3"),
              whereClause: WhereClauseSyntax(guardResult: ExprSyntax("error.isError4"))
            )
          }
        ) {
          ThrowStmtSyntax(expression: ExprSyntax("Error4.error3"))
        },
        CatchClauseSyntax {
          FunctionCallExprSyntax(callee: ExprSyntax("print")) {
            TupleExprElementSyntax(expression: ExprSyntax("error"))
          }
        },
      ]
    )

    AssertBuildResult(
      buildable,
      """
      do {
          try? a.b()
      } catch Error1, Error2 {
          print("Known error")
      } catch Error3 where error.isError4 {
          throw Error4.error3
      } catch {
          print(error)
      }
      """
    )
  }
}

final class EnumCaseElementTests: XCTestCase {
  @available(*, deprecated) func testEnumInit() {
    let leadingTrivia = Trivia.unexpectedText("␣")
    let buildable = EnumDeclSyntax(
      leadingTrivia: leadingTrivia,
      identifier: "Greeting",
      inheritanceClause: TypeInheritanceClauseSyntax {
        InheritedTypeSyntax(typeName: TypeSyntax("String"))
        InheritedTypeSyntax(typeName: TypeSyntax("Codable"))
        InheritedTypeSyntax(typeName: TypeSyntax("Equatable"))
      }
    ) {
      MemberDeclListItemSyntax(
        decl: EnumCaseDeclSyntax {
          EnumCaseElementSyntax(
            identifier: "goodMorning",
            rawValue: InitializerClauseSyntax(value: StringLiteralExprSyntax(content: "Good Morning"))
          )
          EnumCaseElementSyntax(
            identifier: "helloWorld",
            rawValue: InitializerClauseSyntax(value: StringLiteralExprSyntax(content: "Hello World"))
          )
          EnumCaseElementSyntax(identifier: "hi")
        }
      )
    }

    AssertBuildResult(
      buildable,
      """
      ␣enum Greeting: String, Codable, Equatable {
          case goodMorning = "Good Morning", helloWorld = "Hello World", hi
      }
      """
    )
  }
}

final class ExprListTests: XCTestCase {
  @available(*, deprecated) func testExprList() {
    let testCases: [UInt: (ExprListSyntax, String)] = [
      #line: (ExprListSyntax([IntegerLiteralExprSyntax(1), BinaryOperatorExprSyntax(text: "+"), FloatLiteralExprSyntax(2.34)]), "1 + 2.34"),
      #line: ([IntegerLiteralExprSyntax(1), BinaryOperatorExprSyntax(text: "+"), FloatLiteralExprSyntax(2.34)], "1 + 2.34"),
    ]

    for (line, testCase) in testCases {
      let (builder, expected) = testCase
      AssertBuildResult(builder, expected, line: line)
    }
  }
}

final class ExtensionDeclTests: XCTestCase {
  @available(*, deprecated) func testExtensionDecl() {
    let keywords = ["associatedtype", "class"].map { keyword -> VariableDeclSyntax in
      // We need to use `CodeBlock` here to ensure there is braces around.
      let body = CodeBlockSyntax {
        FunctionCallExprSyntax(callee: ExprSyntax("TokenSyntax.\(raw: keyword)Keyword"))
      }

      return VariableDeclSyntax(
        modifiers: [DeclModifierSyntax(name: .keyword(.public))],
        bindingKeyword: .keyword(.var)
      ) {
        PatternBindingSyntax(
          pattern: PatternSyntax("`\(raw: keyword)`"),
          typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax("TokenSyntax")),
          accessor: .getter(body)
        )

      }
    }
    let members = MemberDeclListSyntax(keywords.map { MemberDeclListItemSyntax(decl: $0) })
    let buildable = ExtensionDeclSyntax(
      extendedType: TypeSyntax("TokenSyntax"),
      members: MemberDeclBlockSyntax(members: members)
    )

    AssertBuildResult(
      buildable,
      """
      extension TokenSyntax {
          public var `associatedtype`: TokenSyntax {
              TokenSyntax.associatedtypeKeyword()
          }
          public var `class`: TokenSyntax {
              TokenSyntax.classKeyword()
          }
      }
      """
    )
  }
}

final class FloatLiteralTests: XCTestCase {
  @available(*, deprecated) func testFloatLiteral() {
    let testCases: [UInt: (FloatLiteralExprSyntax, String)] = [
      #line: (FloatLiteralExprSyntax(floatingDigits: .floatingLiteral(String(123.321))), "123.321"),
      #line: (FloatLiteralExprSyntax(floatingDigits: .floatingLiteral(String(-123.321))), "-123.321"),
      #line: (FloatLiteralExprSyntax(floatingDigits: "2_123.321"), "2_123.321"),
      #line: (FloatLiteralExprSyntax(floatingDigits: "-2_123.321"), "-2_123.321"),
      #line: (FloatLiteralExprSyntax(2_123.321), "2123.321"),
      #line: (FloatLiteralExprSyntax(-2_123.321), "-2123.321"),
      #line: (2_123.321, "2123.321"),
      #line: (-2_123.321, "-2123.321"),
    ]

    for (line, testCase) in testCases {
      let (builder, expected) = testCase
      AssertBuildResult(builder, expected, line: line)
    }
  }
}
import SwiftBasicFormat

final class FunctionTests: XCTestCase {
  @available(*, deprecated) func testFibonacci() throws {
    let buildable = try FunctionDeclSyntax("func fibonacci(_ n: Int) -> Int") {
      StmtSyntax("if n <= 1 { return n }")

      StmtSyntax("return fibonacci(n - 1) + self.fibonacci(n - 2)")
    }

    AssertBuildResult(
      buildable,
      """
      func fibonacci(_ n: Int) -> Int {
          if n <= 1 {
              return n
          }
          return fibonacci(n - 1) + self.fibonacci(n - 2)
      }
      """
    )
  }

  @available(*, deprecated) func testFunctionDeclEnsurePropperSpacing() {
    let testCases: [UInt: (DeclSyntax, String)] = [
      #line: (
        DeclSyntax(
          """
          @available(*, deprecated, message: "Use function on Baz")
          private func visitChildren<SyntaxType: SyntaxProtocol>(_ node: SyntaxType) {
          }
          """
        ),
        """
        @available(*, deprecated, message: "Use function on Baz")
        private func visitChildren<SyntaxType: SyntaxProtocol>(_ node: SyntaxType) {
        }
        """
      ),
      #line: (
        DeclSyntax(
          """
          public static func == (lhs: String, rhs: String) -> Bool {
            return lhs < rhs
          }
          """
        ),
        """
        public static func == (lhs: String, rhs: String) -> Bool {
            return lhs < rhs
        }
        """
      ),
      #line: (
        DeclSyntax(
          """
          public static func == (lhs: String, rhs: String) -> Bool {
            return lhs > rhs
          }
          """
        ),
        """
        public static func == (lhs: String, rhs: String) -> Bool {
            return lhs > rhs
        }
        """
      ),
      #line: (
        DeclSyntax(
          """
          public static func == (lhs1: String, lhs2: String, rhs1: String, rhs2: String) -> Bool {
            return (lhs1, lhs2) > (rhs1, rhs2)
          }
          """
        ),
        """
        public static func == (lhs1: String, lhs2: String, rhs1: String, rhs2: String) -> Bool {
            return (lhs1, lhs2) > (rhs1, rhs2)
        }
        """
      ),
      #line: (
        DeclSyntax(
          """
          public func foo<Generic>(input: Bas) -> Foo<Generic> {
            return input as Foo<Generic>!
          }
          """
        ),
        """
        public func foo<Generic>(input: Bas) -> Foo<Generic> {
            return input as Foo<Generic>!
        }
        """
      ),
      #line: (
        DeclSyntax(
          """
          public func foo<Generic>(input: Bas) -> Foo<Generic?> {
            return input as Foo<Generic?>!
          }
          """
        ),
        """
        public func foo<Generic>(input: Bas) -> Foo<Generic?> {
            return input as Foo<Generic?>!
        }
        """
      ),
      #line: (
        DeclSyntax(
          """
          public func foo<Generic>(input: [Bar]) -> Foo<[Bar]> {
            return input
          }
          """
        ),
        """
        public func foo<Generic>(input: [Bar]) -> Foo<[Bar]> {
            return input
        }
        """
      ),
      #line: (
        DeclSyntax(
          """
          public func foo(myOptionalClosure: MyClosure?)  {
            myOptionalClosure!()
          }
          """
        ),
        """
        public func foo(myOptionalClosure: MyClosure?)  {
            myOptionalClosure!()
        }
        """
      ),
      #line: (
        DeclSyntax(
          """
          public func foo(myOptionalValue: String?, myOtherOptionalValue: [String?])  {
          }
          """
        ),
        """
        public func foo(myOptionalValue: String?, myOtherOptionalValue: [String?])  {
        }
        """
      ),
      #line: (
        DeclSyntax(
          FunctionDeclSyntax(
            modifiers: [DeclModifierSyntax(name: .keyword(.public)), DeclModifierSyntax(name: .keyword(.static))],
            identifier: TokenSyntax.identifier("=="),
            signature: FunctionSignatureSyntax(
              input: ParameterClauseSyntax(
                parameterList: FunctionParameterListSyntax {
                  FunctionParameterSyntax(firstName: TokenSyntax.identifier("lhs"), colon: .colonToken(), type: TypeSyntax("String"))
                  FunctionParameterSyntax(firstName: TokenSyntax.identifier("rhs"), colon: .colonToken(), type: TypeSyntax("String"))
                }
              ),
              output: ReturnClauseSyntax(
                returnType: SimpleTypeIdentifierSyntax(name: TokenSyntax.identifier("Bool"))
              )
            ),
            bodyBuilder: {
              ReturnStmtSyntax(
                expression: SequenceExprSyntax(
                  elements: ExprListSyntax {
                    IdentifierExprSyntax(identifier: .identifier("lhs"))
                    BinaryOperatorExprSyntax(operatorToken: .binaryOperator("<"))
                    IdentifierExprSyntax(identifier: .identifier("rhs"))
                  }
                )
              )
            }
          )
        ),
        """
        public static func ==(lhs: String, rhs: String) -> Bool {
            return lhs < rhs
        }
        """
      ),
      #line: (
        DeclSyntax(
          FunctionDeclSyntax(
            modifiers: [DeclModifierSyntax(name: .keyword(.public)), DeclModifierSyntax(name: .keyword(.static))],
            identifier: TokenSyntax.identifier("=="),
            signature: FunctionSignatureSyntax(
              input: ParameterClauseSyntax(
                parameterList: FunctionParameterListSyntax {
                  FunctionParameterSyntax(firstName: TokenSyntax.identifier("lhs1"), colon: .colonToken(), type: TypeSyntax("String"))
                  FunctionParameterSyntax(firstName: TokenSyntax.identifier("lhs2"), colon: .colonToken(), type: TypeSyntax("String"))
                  FunctionParameterSyntax(firstName: TokenSyntax.identifier("rhs1"), colon: .colonToken(), type: TypeSyntax("String"))
                  FunctionParameterSyntax(firstName: TokenSyntax.identifier("rhs2"), colon: .colonToken(), type: TypeSyntax("String"))
                }
              ),
              output: ReturnClauseSyntax(
                returnType: SimpleTypeIdentifierSyntax(name: TokenSyntax.identifier("Bool"))
              )
            ),
            bodyBuilder: {
              ReturnStmtSyntax(
                expression: SequenceExprSyntax(
                  elements: ExprListSyntax {
                    ExprSyntax("(lhs1, lhs2)")
                    BinaryOperatorExprSyntax(operatorToken: .binaryOperator("<"))
                    ExprSyntax("(rhs1, rhs2)")
                  }
                )
              )
            }
          )
        ),
        """
        public static func ==(lhs1: String, lhs2: String, rhs1: String, rhs2: String) -> Bool {
            return (lhs1, lhs2) < (rhs1, rhs2)
        }
        """
      ),
    ]

    for (line, testCase) in testCases {
      let (builder, expected) = testCase
      AssertBuildResult(builder, expected, line: line)
    }
  }

  @available(*, deprecated) func testArguments() {
    let buildable = FunctionCallExprSyntax(callee: ExprSyntax("test")) {
      for param in (1...5) {
        TupleExprElementSyntax(label: param.isMultiple(of: 2) ? "p\(param)" : nil, expression: ExprSyntax("value\(raw: param)"))
      }
    }
    AssertBuildResult(buildable, "test(value1, p2: value2, value3, p4: value4, value5)")
  }

  @available(*, deprecated) func testFunctionDeclBuilder() {
    let builder = DeclSyntax(
      """
      func test(_ p1: Int, p2: Int, _ p3: Int, p4: Int, _ p5: Int) -> Int {
          return p1 + p2 + p3 + p4 + p5
      }
      """
    )

    AssertBuildResult(
      builder,
      """
      func test(_ p1: Int, p2: Int, _ p3: Int, p4: Int, _ p5: Int) -> Int {
          return p1 + p2 + p3 + p4 + p5
      }
      """
    )
  }

  @available(*, deprecated) func testMultilineFunctionParameterList() {
    let builder = DeclSyntax(
      """
      func test(
        _ p1: Int,
        p2: Int,
        _ p3: Int,
        p4: Int,
        _ p5: Int
      ) -> Int {
        return p1 + p2 + p3 + p4 + p5
      }
      """
    )

    AssertBuildResult(
      builder,
      """
      func test(
          _ p1: Int,
          p2: Int,
          _ p3: Int,
          p4: Int,
          _ p5: Int
      ) -> Int {
          return p1 + p2 + p3 + p4 + p5
      }
      """
    )
  }

  @available(*, deprecated) func testMultilineFunctionCallExpr() {
    let builder = ExprSyntax(
      """
      test(
      p1: value1,
      p2: value2,
      p3: value3,
      p4: value4,
      p5: value5
      )
      """
    )

    AssertBuildResult(
      builder,
      """
      test(
          p1: value1,
          p2: value2,
          p3: value3,
          p4: value4,
          p5: value5
      )
      """
    )
  }

  @available(*, deprecated) func testParensEmittedForNoArgumentsAndNoTrailingClosure() {
    let buildable = FunctionCallExprSyntax(callee: ExprSyntax("test"))
    AssertBuildResult(buildable, "test()")
  }

  @available(*, deprecated) func testParensEmittedForArgumentAndTrailingClosure() {
    let buildable = FunctionCallExprSyntax(callee: ExprSyntax("test"), trailingClosure: ClosureExprSyntax {}) {
      TupleExprElementSyntax(expression: ExprSyntax("42"))
    }
    AssertBuildResult(buildable, "test(42) {\n}")
  }

  @available(*, deprecated) func testParensOmittedForNoArgumentsAndTrailingClosure() {
    let closure = ClosureExprSyntax(statementsBuilder: {
      FunctionCallExprSyntax(callee: ExprSyntax("f")) {
        TupleExprElementSyntax(expression: ExprSyntax("a"))
      }
    })
    let buildable = FunctionCallExprSyntax(callee: ExprSyntax("test"), trailingClosure: closure)

    AssertBuildResult(
      buildable,
      """
      test {
          f(a)
      }
      """
    )
  }
}

final class IfConfigDeclSyntaxTests: XCTestCase {
  @available(*, deprecated) func testIfConfigClauseSyntax() {
    let buildable = IfConfigDeclSyntax(
      clauses: IfConfigClauseListSyntax {
        IfConfigClauseSyntax(
          poundKeyword: .poundIfKeyword(),
          condition: ExprSyntax("DEBUG"),
          elements: .statements(
            CodeBlockItemListSyntax {
              DeclSyntax(
                """
                public func debug(_ data: Foo) -> String {
                  return data.debugDescription
                }
                """
              )
            }
          )
        )
        IfConfigClauseSyntax(
          poundKeyword: .poundElseKeyword(leadingTrivia: .newline),
          elements: .statements(
            CodeBlockItemListSyntax {
              DeclSyntax(
                """
                public func debug(_ data: Foo) -> String {
                  return data.description
                }
                """
              )
            }
          )
        )
      },
      poundEndif: .poundEndifKeyword(leadingTrivia: .newline)
    )

    AssertBuildResult(
      buildable,
      """
      #if DEBUG
      public func debug(_ data: Foo) -> String {
          return data.debugDescription
      }
      #else
      public func debug(_ data: Foo) -> String {
          return data.description
      }
      #endif
      """
    )
  }
}

final class IfStmtTests: XCTestCase {
  @available(*, deprecated) func testEmptyIfExpr() {
    // Use the convenience initializer from IfStmtConvenienceInitializers. This is
    // disambiguated by the absence of a labelName parameter and the use of a
    // trailing closure.
    let buildable = IfExprSyntax(conditions: ConditionElementListSyntax { BooleanLiteralExprSyntax(false) }) {}
    AssertBuildResult(
      buildable,
      """
      if false {
      }
      """
    )
  }

  @available(*, deprecated) func testIfStmtSyntax() throws {
    let testCases: [UInt: (IfExprSyntax, String)] = [
      #line: (
        ExprSyntax(
          """
          if foo == x {
            return foo
          }
          """
        ).cast(IfExprSyntax.self),
        """
        if foo == x {
            return foo
        }
        """
      ),
      #line: (
        try IfExprSyntax("if foo == x") { StmtSyntax("return foo") },
        """
        if foo == x {
            return foo
        }
        """
      ),
      #line: (
        try IfExprSyntax("if foo == x") {
          StmtSyntax("return foo")
        } else: {
          StmtSyntax("return bar")
        },
        """
        if foo == x {
            return foo
        }else {
            return bar
        }
        """
      ),
      #line: (
        try IfExprSyntax("if foo == x", bodyBuilder: { StmtSyntax("return foo") }, elseIf: IfExprSyntax("if foo == z") { StmtSyntax("return baz") }),
        """
        if foo == x {
            return foo
        }else if foo == z {
            return baz
        }
        """
      ),
    ]

    for (line, testCase) in testCases {
      let (builder, expected) = testCase
      AssertBuildResult(builder, expected, line: line)
    }
  }

  @available(*, deprecated) func testIfStmtSpacing() {
    let testCases: [UInt: (IfExprSyntax, String)] = [
      #line: (
        IfExprSyntax(conditions: ConditionElementListSyntax { ExprSyntax("!(true)") }) {},
        """
        if !(true) {
        }
        """
      ),
      #line: (
        ExprSyntax(
          """
          if !(false) {
          }
          """
        ).cast(IfExprSyntax.self),
        """
        if !(false) {
        }
        """
      ),
    ]

    for (line, testCase) in testCases {
      let (builder, expected) = testCase
      AssertBuildResult(builder, expected, line: line)
    }
  }

  @available(*, deprecated) func testIfLetStmt() {
    let buildable = IfExprSyntax(
      conditions: ConditionElementListSyntax {
        OptionalBindingConditionSyntax(
          bindingKeyword: .keyword(.let),
          pattern: PatternSyntax("x"),
          initializer: InitializerClauseSyntax(value: ExprSyntax("y"))
        )
      }
    ) {}
    AssertBuildResult(
      buildable,
      """
      if let x = y {
      }
      """
    )
  }

  @available(*, deprecated) func testIfCaseStmt() {
    let buildable = IfExprSyntax(
      conditions: ConditionElementListSyntax {
        MatchingPatternConditionSyntax(
          pattern: ExpressionPatternSyntax(expression: MemberAccessExprSyntax(name: "x")),
          initializer: InitializerClauseSyntax(value: ExprSyntax("y"))
        )
      }
    ) {}
    AssertBuildResult(
      buildable,
      """
      if case .x = y {
      }
      """
    )
  }
}

final class ImportTests: XCTestCase {
  @available(*, deprecated) func testImport() {
    let leadingTrivia = Trivia.unexpectedText("␣")
    let identifier = TokenSyntax.identifier("SwiftSyntax")

    let importDecl = ImportDeclSyntax(
      leadingTrivia: leadingTrivia,
      path: AccessPathSyntax([AccessPathComponentSyntax(name: identifier)])
    )

    AssertBuildResult(importDecl, "␣import SwiftSyntax")
  }
}

final class InitializerDeclTests: XCTestCase {
  @available(*, deprecated) func testInitializerDecl() {
    let builder = DeclSyntax(
      """
      public init(errorCode: Int) {
        self.code = errorCode
      }
      """
    )

    AssertBuildResult(
      builder,
      """
      public init(errorCode: Int) {
          self.code = errorCode
      }
      """
    )
  }

  @available(*, deprecated) func testFailableInitializerDecl() {
    let builder = DeclSyntax(
      """
      public init?(errorCode: Int) {
        guard errorCode > 0 else { return nil }
        self.code = errorCode
      }
      """
    )

    AssertBuildResult(
      builder,
      """
      public init?(errorCode: Int) {
          guard errorCode > 0 else {
              return nil
          }
          self.code = errorCode
      }
      """
    )
  }

  @available(*, deprecated) func testMultilineParameterList() {
    let builder = DeclSyntax(
      """
      init(
        _ p1: Int,
        p2: Int,
        _ p3: Int,
        p4: Int,
        _ p5: Int
      ) {
        self.init(p1 + p2 + p3 + p4 + p5)
      }
      """
    )

    AssertBuildResult(
      builder,
      """
      init(
          _ p1: Int,
          p2: Int,
          _ p3: Int,
          p4: Int,
          _ p5: Int
      ) {
          self.init(p1 + p2 + p3 + p4 + p5)
      }
      """
    )
  }
}

final class IntegerLiteralTests: XCTestCase {
  @available(*, deprecated) func testIntegerLiteral() {
    let testCases: [UInt: (IntegerLiteralExprSyntax, String)] = [
      #line: (IntegerLiteralExprSyntax(digits: .integerLiteral(String(123))), "123"),
      #line: (IntegerLiteralExprSyntax(digits: .integerLiteral(String(-123))), "-123"),
      #line: (IntegerLiteralExprSyntax(digits: "1_000"), "1_000"),
      #line: (IntegerLiteralExprSyntax(digits: "-1_000"), "-1_000"),
      #line: (IntegerLiteralExprSyntax(1_000), "1000"),
      #line: (IntegerLiteralExprSyntax(-1_000), "-1000"),
      #line: (1_000, "1000"),
      #line: (-1_000, "-1000"),
    ]

    for (line, testCase) in testCases {
      let (builder, expected) = testCase
      AssertBuildResult(builder, expected, line: line)
    }
  }
}

final class ProtocolDeclTests: XCTestCase {
  @available(*, deprecated) func testProtocolDecl() throws {
    let buildable = try ProtocolDeclSyntax("public protocol DeclListBuildable") {
      DeclSyntax("func buildDeclList(format: Format, leadingTrivia: Trivia?) -> [DeclSyntax]")
    }

    AssertBuildResult(
      buildable,
      """
      public protocol DeclListBuildable {
          func buildDeclList(format: Format, leadingTrivia: Trivia?) -> [DeclSyntax]
      }
      """
    )
  }
}

final class ReturnStmtTests: XCTestCase {
  @available(*, deprecated) func testReturnStmt() {
    let testCases: [UInt: (StmtSyntax, String)] = [
      #line: (
        StmtSyntax("return Self.parse(from: &parser)"),
        "return Self.parse(from: &parser)"
      ),
      #line: (
        StmtSyntax("return self.asProtocol(SyntaxProtocol.self) as? DeclSyntaxProtocol"),
        "return self.asProtocol(SyntaxProtocol.self) as? DeclSyntaxProtocol"
      ),
      #line: (
        StmtSyntax("return 0 as! String"),
        "return 0 as! String"
      ),
      #line: (
        StmtSyntax("return 0 as Double"),
        "return 0 as Double"
      ),
      #line: (
        StmtSyntax("return !myBool"),
        "return !myBool"
      ),
      #line: (
        StmtSyntax("return data.child(at: 2, parent: Syntax(self)).map(UnexpectedNodesSyntax.init)"),
        "return data.child(at: 2, parent: Syntax(self)).map(UnexpectedNodesSyntax.init)"
      ),
    ]

    for (line, testCase) in testCases {
      let (builder, expected) = testCase
      AssertBuildResult(builder, expected, line: line)
    }
  }
}

final class SourceFileTests: XCTestCase {
  @available(*, deprecated) func testSourceFile() {
    let source = SourceFileSyntax {
      DeclSyntax("import Foundation")
      DeclSyntax("import UIKit")
      ClassDeclSyntax(
        classKeyword: .keyword(.class),
        identifier: "SomeViewController",
        membersBuilder: {
          DeclSyntax("let tableView: UITableView")
        }
      )
    }

    AssertBuildResult(
      source,
      """
      import Foundation
      import UIKit
      class SomeViewController {
          let tableView: UITableView
      }
      """,
      trimTrailingWhitespace: false
    )
  }
}

class TwoSpacesFormat: BasicFormat {
  override var indentation: TriviaPiece {
    .spaces(indentationLevel * 2)
  }
}

final class StringInterpolationTests: XCTestCase {
  @available(*, deprecated) func testDeclInterpolation() {
    let funcSyntax: DeclSyntax =
      """
      func f(a: Int, b: Int) -> Int {
        a + b
      }
      """
    XCTAssertTrue(funcSyntax.is(FunctionDeclSyntax.self))
    XCTAssertEqual(
      funcSyntax.description,
      """
      func f(a: Int, b: Int) -> Int {
        a + b
      }
      """
    )
  }

  @available(*, deprecated) func testExprInterpolation() {
    let exprSyntax: ExprSyntax =
      """
      f(x + g(y), y.z)
      """
    XCTAssertTrue(exprSyntax.is(FunctionCallExprSyntax.self))

    let addIt: ExprSyntax = "w + \(exprSyntax)"
    XCTAssertTrue(addIt.is(SequenceExprSyntax.self))
  }

  @available(*, deprecated) func testStmtSyntax() {
    let collection: ExprSyntax = "[1, 2, 3, 4, 5]"
    let stmtSyntax: StmtSyntax = "for x in \(collection) { }"
    XCTAssertTrue(stmtSyntax.is(ForInStmtSyntax.self))
  }

  @available(*, deprecated) func testTypeInterpolation() {
    let tupleSyntax: TypeSyntax = "(Int, name: String)"
    XCTAssertTrue(tupleSyntax.is(TupleTypeSyntax.self))
    XCTAssertEqual(tupleSyntax.description, "(Int, name: String)")
    let fnTypeSyntax: TypeSyntax = "(String) async throws -> \(tupleSyntax)"
    XCTAssertTrue(fnTypeSyntax.is(FunctionTypeSyntax.self))
    XCTAssertEqual(
      fnTypeSyntax.description,
      "(String) async throws -> (Int, name: String)"
    )
  }

  @available(*, deprecated) func testPatternInterpolation() {
    let letPattern: PatternSyntax = "let x"
    XCTAssertTrue(letPattern.is(ValueBindingPatternSyntax.self))
  }

  @available(*, deprecated) func testAttributeInterpolation() {
    let attrSyntax: AttributeSyntax = "@discardableResult"
    XCTAssertTrue(attrSyntax.is(AttributeSyntax.self))
    XCTAssertEqual(attrSyntax.description, "@discardableResult")
  }

  @available(*, deprecated) func testStructGenerator() {
    let name = "Type"
    let id = 17

    let structNode: DeclSyntax =
      """
      struct \(raw: name) {
        static var id = \(raw: id)
      }
      """
    XCTAssertTrue(structNode.is(StructDeclSyntax.self))
  }

  func testSourceFile() {
    let _: SourceFileSyntax =
      """
      print("Hello, world!")
      """
  }

  func testParserBuilderInStringInterpolation() {
    let cases = SwitchCaseListSyntax {
      for i in 0..<2 {
        SwitchCaseSyntax(
          """
          case \(raw: i):
            return \(raw: i + 1)
          """
        )
      }
      SwitchCaseSyntax(
        """
        default:
          return -1
        """
      )
    }
    let plusOne = DeclSyntax(
      """
      func plusOne(base: Int) -> Int {
        switch base {
        \(cases, format: TwoSpacesFormat())
        }
      }
      """
    )

    let _ = plusOne

//    AssertStringsEqualWithDiff(
//      plusOne.description.trimmingTrailingWhitespace(),
//      """
//      func plusOne(base: Int) -> Int {
//        switch base {
//        case 0:
//          return 1
//        case 1:
//          return 2
//        default:
//          return -1
//        }
//      }
//      """
//    )
  }

  func testParserBuilderInStringInterpolationLiteral() {
    let cases = SwitchCaseListSyntax {
      for i in 0..<2 {
        SwitchCaseSyntax(
          """
          case \(literal: i):
            return \(literal: i + 1)
          """
        )
      }
      SwitchCaseSyntax(
        """
        default:
          return -1
        """
      )
    }
    let plusOne = DeclSyntax(
      """
      func plusOne(base: Int) -> Int {
        switch base {
        \(cases, format: TwoSpacesFormat())
        }
      }
      """
    )

    let _ = plusOne

//    AssertStringsEqualWithDiff(
//      plusOne.description.trimmingTrailingWhitespace(),
//      """
//      func plusOne(base: Int) -> Int {
//        switch base {
//        case 0:
//          return 1
//        case 1:
//          return 2
//        default:
//          return -1
//        }
//      }
//      """
//    )
  }

  func testStringInterpolationInBuilder() {
    let ext = ExtensionDeclSyntax(extendedType: TypeSyntax("MyType")) {
      DeclSyntax(
        """
        ///
        /// Satisfies conformance to `SyntaxBuildable`.
        func buildSyntax(format: Format) -> Syntax {
          return Syntax(buildTest(format: format))
        }
        """
      )
    }
    let _ = ext
//    AssertStringsEqualWithDiff(
//      ext.formatted(using: TwoSpacesFormat()).description,
//      """
//      extension MyType {
//        ///
//        /// Satisfies conformance to `SyntaxBuildable`.
//        func buildSyntax(format: Format) -> Syntax {
//          return Syntax(buildTest(format: format))
//        }
//      }
//      """
//    )
  }

  func testAccessorInterpolation() {
    let setter: AccessorDeclSyntax =
      """
      set(newValue) {
        _storage = newValue
      }
      """
    XCTAssertTrue(setter.is(AccessorDeclSyntax.self))
//    AssertStringsEqualWithDiff(
//      setter.description,
//      """
//      set(newValue) {
//        _storage = newValue
//      }
//      """
//    )
  }

  func testTrivia() {
    XCTAssertEqual(
      "/// doc comment" as Trivia,
      [
        .docLineComment("/// doc comment")
      ]
    )

    XCTAssertEqual(
      """
      /// doc comment
      /// another doc comment
      """ as Trivia,
      [
        .docLineComment("/// doc comment"),
        .newlines(1),
        .docLineComment("/// another doc comment"),
      ]
    )

    XCTAssertEqual(
      """
      // 1 + 1 = \(1 + 1)
      """ as Trivia,
      [
        .lineComment("// 1 + 1 = 2")
      ]
    )
  }

  func testInvalidTrivia() {
    let invalid = Trivia("/*comment*/ invalid /*comm*/")
    XCTAssertEqual(invalid, [.blockComment("/*comment*/"), .spaces(1), .unexpectedText("invalid"), .spaces(1), .blockComment("/*comm*/")])

//    XCTAssertThrowsError(try Trivia(validating: "/*comment*/ invalid /*comm*/")) { error in
//      AssertStringsEqualWithDiff(
//        String(describing: error),
//        """
//
//        1 │ /*comment*/ invalid /*comm*/
//          ∣             ╰─ error: unexpected trivia 'invalid'
//
//        """
//      )
//    }
  }

  func testInvalidSyntax() {
    let invalid = DeclSyntax("return 1")
    XCTAssert(invalid.hasError)

    XCTAssertThrowsError(try DeclSyntax(validating: "return 1")) { error in
//      AssertStringsEqualWithDiff(
//        String(describing: error),
//        """
//
//        1 │ return 1
//          ∣ │       ╰─ error: expected declaration
//          ∣ ╰─ error: unexpected code 'return 1' before declaration
//
//        """
//      )
    }
  }

  func testInvalidSyntax2() {
    let invalid = StmtSyntax("struct Foo {}")
    XCTAssert(invalid.hasError)

//    XCTAssertThrowsError(try StmtSyntax(validating: "struct Foo {}")) { error in
//      AssertStringsEqualWithDiff(
//        String(describing: error),
//        """
//
//        1 │ struct Foo {}
//          ∣ │            ╰─ error: expected statement
//          ∣ ╰─ error: unexpected code 'struct Foo {}' before statement
//
//        """
//      )
//    }
  }
}

final class StringLiteralTests: XCTestCase {
  @available(*, deprecated) func testStringLiteral() {
    let leadingTrivia = Trivia.unexpectedText("␣")
    let testCases: [UInt: (String, String)] = [
      #line: ("", #"␣"""#),
      #line: ("asdf", #"␣"asdf""#),
    ]

    for (line, testCase) in testCases {
      let (value, expected) = testCase
      let string = TokenSyntax.stringSegment(value)
      let segment = StringSegmentSyntax(content: string)
      let builder = StringLiteralExprSyntax(
        leadingTrivia: leadingTrivia,
        openQuote: .stringQuoteToken(),
        segments: StringLiteralSegmentsSyntax([.stringSegment(segment)]),
        closeQuote: .stringQuoteToken()
      )

      AssertBuildResult(builder, expected, line: line)
    }
  }

  @available(*, deprecated) func testRegular() {
    AssertBuildResult(
      StringLiteralExprSyntax(content: "foobar"),
      """
      "foobar"
      """
    )

    AssertBuildResult(
      StringLiteralExprSyntax(content: "##foobar"),
      """
      "##foobar"
      """
    )
  }

  @available(*, deprecated) func testEscapeLiteral() {
    AssertBuildResult(
      StringLiteralExprSyntax(content: #""""foobar""#),
      ##"""
      #""""foobar""#
      """##
    )
  }

  @available(*, deprecated) func testEscapePounds() {
    AssertBuildResult(
      StringLiteralExprSyntax(content: ###"#####"foobar"##foobar"#foobar"###),
      #####"""
      ###"#####"foobar"##foobar"#foobar"###
      """#####
    )
  }

  @available(*, deprecated) func testEscapeInteropolation() {
    AssertBuildResult(
      StringLiteralExprSyntax(content: ###"\##(foobar)\#(foobar)"###),
      ####"""
      ###"\##(foobar)\#(foobar)"###
      """####
    )
  }

  @available(*, deprecated) func testEscapeBackslash() {
    AssertBuildResult(
      StringLiteralExprSyntax(content: #"\"#),
      ##"""
      #"\"#
      """##
    )

    AssertBuildResult(
      StringLiteralExprSyntax(content: ##"\#n"##),
      ##"""
      ##"\#n"##
      """##
    )

    AssertBuildResult(
      StringLiteralExprSyntax(content: ##"\#\"##),
      ##"""
      ##"\#\"##
      """##
    )

    AssertBuildResult(
      StringLiteralExprSyntax(content: ##"\#"##),
      ##"""
      ##"\#"##
      """##
    )
  }

  @available(*, deprecated) func testNewlines() {
    AssertBuildResult(
      StringLiteralExprSyntax(content: "linux\nwindows\r\nunicode\u{2028}a"),
      #""linux\nwindows\r\nunicode\u{2028}a""#
    )

    AssertBuildResult(
      StringLiteralExprSyntax(content: "\\linux\nwindows\r\nunicode\u{2028}a"),
      ##"#"\linux\#nwindows\#r\#nunicode\#u{2028}a"#"##
    )
  }

  @available(*, deprecated) func testNul() {
    AssertBuildResult(
      StringLiteralExprSyntax(content: "before\0after"),
      #""before\0after""#
    )

    AssertBuildResult(
      StringLiteralExprSyntax(content: "\\before\0after"),
      ##"#"\before\#0after"#"##
    )
  }

  @available(*, deprecated) func testControlChars() {
    // Note that tabs do *not* get escaped.
    AssertBuildResult(
      StringLiteralExprSyntax(content: "before\u{07}\t\u{7f}after"),
      #""before\u{7}\t\u{7f}after""#
    )

    AssertBuildResult(
      StringLiteralExprSyntax(content: "\\before\u{07}\t\u{7f}after"),
      ##"#"\before\#u{7}\#t\#u{7f}after"#"##
    )
  }

  @available(*, deprecated) func testEscapeTab() {
    // Tab should be escaped in single-line string literals
    AssertBuildResult(
      StringLiteralExprSyntax(content: "a\tb"),
      #"""
      "a\tb"
      """#
    )

    // Tab should not be escaped in single-line string literals
    AssertBuildResult(
      StringLiteralExprSyntax(
        openQuote: .multilineStringQuoteToken(trailingTrivia: .newline),
        content: "a\tb",
        closeQuote: .multilineStringQuoteToken(leadingTrivia: .newline)
      ),
      #"""
      """
      a\#tb
      """
      """#
    )
  }

  @available(*, deprecated) func testStringLiteralInExpr() {
    let buildable = ExprSyntax(
      #"""
      "Validation failures: \(nonNilErrors.map({ "- \($0.description)" }).joined(separator: "\n"))"
      """#
    )

    AssertBuildResult(
      buildable,
      #"""
      "Validation failures: \(nonNilErrors.map({ "- \($0.description)" }).joined(separator: "\n"))"
      """#
    )
  }

  @available(*, deprecated) func testStringSegmentWithCode() {
    let buildable = StringSegmentSyntax(content: .stringSegment(#"\(nonNilErrors.map({ "- \($0.description)" }).joined(separator: "\n"))"#))

    AssertBuildResult(
      buildable,
      #"\(nonNilErrors.map({ "- \($0.description)" }).joined(separator: "\n"))"#
    )
  }

  @available(*, deprecated) func testStringLiteralSegmentWithCode() {
    let buildable = StringLiteralSegmentsSyntax {
      StringSegmentSyntax(content: .stringSegment(#"Error validating child at index \(index) of \(nodeKind):"#), trailingTrivia: .newline)
      StringSegmentSyntax(content: .stringSegment(#"Node did not satisfy any node choice requirement."#), trailingTrivia: .newline)
      StringSegmentSyntax(content: .stringSegment(#"Validation failures:"#), trailingTrivia: .newline)
      StringSegmentSyntax(content: .stringSegment(#"\(nonNilErrors.map({ "- \($0.description)" }).joined(separator: "\n"))"#))
    }

    AssertBuildResult(
      buildable,
      #"""
      Error validating child at index \(index) of \(nodeKind):
      Node did not satisfy any node choice requirement.
      Validation failures:
      \(nonNilErrors.map({ "- \($0.description)" }).joined(separator: "\n"))
      """#
    )
  }

  @available(*, deprecated) func testMultiLineStringWithResultBuilder() {
    let buildable = StringLiteralExprSyntax(
      openQuote: .multilineStringQuoteToken(trailingTrivia: .newline),
      segments: StringLiteralSegmentsSyntax {
        StringSegmentSyntax(content: .stringSegment(#"Error validating child at index \(index) of \(nodeKind):"#), trailingTrivia: .newline)
        StringSegmentSyntax(content: .stringSegment(#"Node did not satisfy any node choice requirement."#), trailingTrivia: .newline)
        StringSegmentSyntax(content: .stringSegment(#"Validation failures:"#), trailingTrivia: .newline)
        ExpressionSegmentSyntax(
          expressions: TupleExprElementListSyntax {
            TupleExprElementSyntax(expression: ExprSyntax(#"nonNilErrors.map({ "- \($0.description)" }).joined(separator: "\n"))"#))
          }
        )
      },
      closeQuote: .multilineStringQuoteToken(leadingTrivia: .newline)
    )

    AssertBuildResult(
      buildable,
      #"""
      """
      Error validating child at index \(index) of \(nodeKind):
      Node did not satisfy any node choice requirement.
      Validation failures:
      \(nonNilErrors.map({ "- \($0.description)" }).joined(separator: "\n")))
      """
      """#
    )
  }

  @available(*, deprecated) func testMultiStringLiteralInExpr() {
    let buildable = ExprSyntax(
      #"""
      assertionFailure("""
        Error validating child at index \(index) of \(nodeKind):
        Node did not satisfy any node choice requirement.
        Validation failures:
        \(nonNilErrors.map({ "- \($0.description)" }).joined(separator: "\n"))
        """, file: file, line: line)
      """#
    )

    AssertBuildResult(
      buildable,
      #"""
      assertionFailure("""
          Error validating child at index \(index) of \(nodeKind):
          Node did not satisfy any node choice requirement.
          Validation failures:
          \(nonNilErrors.map({ "- \($0.description)" }).joined(separator: "\n"))
          """, file: file, line: line)
      """#
    )
  }

  @available(*, deprecated) func testMultiStringLiteralInIfExpr() {
    let buildable = ExprSyntax(
      #"""
      if true {
        assertionFailure("""
          Error validating child at index
          Node did not satisfy any node choice requirement.
          Validation failures:
          """)
      }
      """#
    )

    AssertBuildResult(
      buildable,
      #"""
      if true {
          assertionFailure("""
              Error validating child at index
              Node did not satisfy any node choice requirement.
              Validation failures:
              """)
      }
      """#
    )
  }

  @available(*, deprecated) func testMultiStringLiteralOnNewlineInIfExpr() {
    let buildable = ExprSyntax(
      #"""
      if true {
        assertionFailure(
          """
          Error validating child at index
          Node did not satisfy any node choice requirement.
          Validation failures:
          """
        )
      }
      """#
    )

    AssertBuildResult(
      buildable,
      #"""
      if true {
          assertionFailure(
              """
              Error validating child at index
              Node did not satisfy any node choice requirement.
              Validation failures:
              """
          )
      }
      """#
    )
  }
}

final class StructTests: XCTestCase {
  @available(*, deprecated) func testEmptyStruct() {
    let leadingTrivia = Trivia.unexpectedText("␣")
    let buildable = StructDeclSyntax(leadingTrivia: leadingTrivia, identifier: "TestStruct") {}

    AssertBuildResult(
      buildable,
      """
      ␣struct TestStruct {
      }
      """
    )
  }

  @available(*, deprecated) func testNestedStruct() throws {
    let nestedStruct = try StructDeclSyntax(
      """
      /// A nested struct
      /// with multi line comment
      struct NestedStruct<A, B: C, D> where A: X, A.P == D
      """
    ) {}

    let carriateReturnsStruct = StructDeclSyntax(
      leadingTrivia: [
        .docLineComment("/// A nested struct"),
        .carriageReturns(1),
        .docLineComment("/// with multi line comment where the newline is a CR"),
        .carriageReturns(1),
      ],
      structKeyword: .keyword(.struct),
      identifier: "CarriateReturnsStruct",
      members: MemberDeclBlockSyntax(members: [])
    )
    let carriageReturnFormFeedsStruct = StructDeclSyntax(
      leadingTrivia: [
        .docLineComment("/// A nested struct"),
        .carriageReturnLineFeeds(1),
        .docLineComment("/// with multi line comment where the newline is a CRLF"),
        .carriageReturnLineFeeds(1),
      ],
      structKeyword: .keyword(.struct),
      identifier: "CarriageReturnFormFeedsStruct",
      members: MemberDeclBlockSyntax(members: [])
    )
    let testStruct = try StructDeclSyntax("public struct TestStruct") {
      nestedStruct
      carriateReturnsStruct
      carriageReturnFormFeedsStruct
    }

    AssertBuildResult(
      testStruct,
      """
      public struct TestStruct {
          /// A nested struct
          /// with multi line comment
          struct NestedStruct<A, B: C, D> where A: X, A.P == D {
          }
          /// A nested struct\r\
          /// with multi line comment where the newline is a CR\r\
          struct CarriateReturnsStruct {
          }
          /// A nested struct\r\n\
          /// with multi line comment where the newline is a CRLF\r\n\
          struct CarriageReturnFormFeedsStruct {
          }
      }
      """
    )
  }

  @available(*, deprecated) func testControlWithLoopAndIf() {
    let myStruct = StructDeclSyntax(identifier: "MyStruct") {
      for i in 0..<5 {
        if i.isMultiple(of: 2) {
          VariableDeclSyntax(bindingKeyword: .keyword(.let)) {
            PatternBindingSyntax(
              pattern: PatternSyntax("var\(raw: i)"),
              typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax("String"))
            )
          }
        }
      }
    }
    AssertBuildResult(
      myStruct,
      """
      struct MyStruct {
          let var0: String
          let var2: String
          let var4: String
      }
      """
    )
  }
}

final class SwitchCaseLabelSyntaxTests: XCTestCase {
  @available(*, deprecated) func testSwitchCaseLabelSyntax() {
    let testCases: [UInt: (SwitchCaseSyntax, String)] = [
      #line: (
        SwitchCaseSyntax("default:") {
          StmtSyntax("return nil")

        },
        """
        default:
            return nil
        """
      ),
      #line: (
        SwitchCaseSyntax("case .foo:") {
          StmtSyntax("return nil")

        },
        """
        case .foo:
            return nil
        """
      ),
    ]

    for (line, testCase) in testCases {
      let (builder, expected) = testCase
      AssertBuildResult(builder, expected, trimTrailingWhitespace: false, line: line)
    }
  }
}

final class SwitchTests: XCTestCase {
  @available(*, deprecated) func testSwitch() {
    let syntax = SwitchExprSyntax(expression: ExprSyntax("count")) {
      for num in 1..<3 {
        SwitchCaseSyntax("case \(literal: num):") {
          ExprSyntax("print(count)")
        }
      }
      SwitchCaseSyntax("default:") {
        StmtSyntax("break")
      }
    }

    AssertBuildResult(
      syntax,
      """
      switch count {
      case 1:
          print(count)
      case 2:
          print(count)
      default:
          break
      }
      """
    )
  }

  @available(*, deprecated) func testSwitchStmtSyntaxWithStringParsing() throws {
    let syntax = try SwitchExprSyntax("switch count") {
      for num in 1..<3 {
        SwitchCaseSyntax("case \(literal: num):") {
          ExprSyntax("print(count)")
        }
      }
      SwitchCaseSyntax("default:") {
        StmtSyntax("break")
      }
    }

    AssertBuildResult(
      syntax,
      """
      switch count {
      case 1:
          print(count)
      case 2:
          print(count)
      default:
          break
      }
      """
    )
  }
}

final class TernaryExprTests: XCTestCase {
  @available(*, deprecated) func testTernaryExpr() {
    let buildable = ExprSyntax("true ? a : b")
    AssertBuildResult(
      buildable,
      """
      true ? a : b
      """
    )
  }
}

final class TriviaSyntaxTests: XCTestCase {
  @available(*, deprecated) func testLeadingTrivia() {
    let decl = VariableDeclSyntax(
      leadingTrivia: """
        /// A doc comment
        /* An inline comment */ \

        """,
      modifiers: [DeclModifierSyntax(name: .keyword(.static))],
      bindingKeyword: .keyword(.var)
    ) {
      PatternBindingSyntax(
        // TODO: This is meant to be `Pattern`, but it's ambiguous with XCTest
        // Really we should just remove that method in favor of the regular
        // syntax `init`, though that will mean callers have to wrap in
        // `PatternSyntax`. Changing those inits to be generic would be
        // possible, but then still fails here for the same reason.
        pattern: PatternSyntax("test"),
        typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax("String"))
      )
    }

    AssertBuildResult(
      decl,
      """
      /// A doc comment
      /* An inline comment */ static var test: String
      """
    )
  }

  @available(*, deprecated) func testTriviaConcatenation() {
    let x = Trivia.newline
    var y = x
    y += .space
    XCTAssertEqual(y, x + .space)
    XCTAssertEqual(y, [.newlines(1), .spaces(1)])
  }

  @available(*, deprecated) func testAttachedTrivia() {
    let testCases: [UInt: (DeclSyntax, String)] = [
      #line: (
        DeclSyntax("let x: Int").with(\.leadingTrivia, .space),
        " let x: Int"
      ),
      #line: (
        DeclSyntax("let x: Int").with(\.trailingTrivia, .space),
        "let x: Int "
      ),
    ]
    for (line, testCase) in testCases {
      let (builder, expected) = testCase
      AssertBuildResult(builder, expected, line: line)
    }
  }

  @available(*, deprecated) func testAttachedListTrivia() {
    let testCases: [UInt: (AttributeListSyntax, String)] = [
      #line: (
        AttributeListSyntax {
          AttributeSyntax(attributeName: TypeSyntax("Test")).with(\.leadingTrivia, .space)
        },
        " @Test"
      ),
      #line: (
        AttributeListSyntax {
          AttributeSyntax(attributeName: TypeSyntax("A")).with(\.trailingTrivia, .space)
          AttributeSyntax(attributeName: TypeSyntax("B")).with(\.trailingTrivia, .space)
        },
        "@A @B "
      ),
    ]
    for (line, testCase) in testCases {
      let (builder, expected) = testCase
      AssertBuildResult(builder, expected, line: line)
    }
  }
}

final class TupleSyntaxTests: XCTestCase {
  @available(*, deprecated) func testLabeledElementList() {
    let builder = ExprSyntax("(p1: value1, p2: value2, p3: value3)")
    AssertBuildResult(builder, "(p1: value1, p2: value2, p3: value3)")
  }

  @available(*, deprecated) func testMultilineTupleExpr() {
    let builder = ExprSyntax(
      """
      (
      p1: value1,
      p2: value2,
      p3: value3,
      p4: value4,
      p5: value5
      )
      """
    )

    AssertBuildResult(
      builder,
      """
      (
          p1: value1,
          p2: value2,
          p3: value3,
          p4: value4,
          p5: value5
      )
      """
    )
  }

  @available(*, deprecated) func testMultilineTupleType() {
    let builder = TypeSyntax(
      """
      (
      Int,
      p2: Int,
      Int,
      p4: Int,
      Int
      )
      """
    )

    AssertBuildResult(
      builder,
      """
      (
          Int,
          p2: Int,
          Int,
          p4: Int,
          Int
      )
      """
    )
  }
}

final class VariableTests: XCTestCase {
  @available(*, deprecated) func testVariableDecl() {
    let leadingTrivia = Trivia.unexpectedText("␣")

    let buildable = VariableDeclSyntax(leadingTrivia: leadingTrivia, bindingKeyword: .keyword(.let)) {
      PatternBindingSyntax(pattern: PatternSyntax("a"), typeAnnotation: TypeAnnotationSyntax(type: ArrayTypeSyntax(elementType: TypeSyntax("Int"))))
    }

    AssertBuildResult(buildable, "␣let a: [Int]")
  }

  @available(*, deprecated) func testInoutBindingDecl() {
    let leadingTrivia = Trivia.unexpectedText("␣")

    let buildable = VariableDeclSyntax(leadingTrivia: leadingTrivia, bindingKeyword: .keyword(.inout)) {
      PatternBindingSyntax(pattern: PatternSyntax("a"), typeAnnotation: TypeAnnotationSyntax(type: ArrayTypeSyntax(elementType: TypeSyntax("Int"))))
    }

    AssertBuildResult(buildable, "␣inout a: [Int]")
  }

  @available(*, deprecated) func testVariableDeclWithStringParsing() {
    let testCases: [UInt: (DeclSyntax, String)] = [
      #line: (
        DeclSyntax("let content = try? String(contentsOf: url)"),
        "let content = try? String(contentsOf: url)"
      ),
      #line: (
        DeclSyntax("inout content = try? String(contentsOf: url)"),
        "inout content = try? String(contentsOf: url)"
      ),
      #line: (
        DeclSyntax("let content = try! String(contentsOf: url)"),
        "let content = try! String(contentsOf: url)"
      ),
      #line: (
        DeclSyntax("var newLayout: ContiguousArray<RawSyntax?>?"),
        "var newLayout: ContiguousArray<RawSyntax?>?"
      ),
      #line: (
        DeclSyntax("var foo: String { myOptional!.someProperty }"),
        """
        var foo: String {
            myOptional!.someProperty
        }
        """
      ),
      #line: (
        DeclSyntax("inout foo: String { myOptional!.someProperty }"),
        """
        inout foo: String {
            myOptional!.someProperty
        }
        """
      ),
      #line: (
        DeclSyntax("var foo: String? { myOptional?.someProperty }"),
        """
        var foo: String? {
            myOptional?.someProperty
        }
        """
      ),
      #line: (
        DeclSyntax("let absoluteRaw = AbsoluteRawSyntax(raw: raw!, info: info)"),
        """
        let absoluteRaw = AbsoluteRawSyntax(raw: raw!, info: info)
        """
      ),
      #line: (
        DeclSyntax("var foo: String { bar(baz!) }"),
        """
        var foo: String {
            bar(baz!)
        }
        """
      ),
      #line: (
        DeclSyntax(#"var foo: String { bar ?? "" }"#),
        #"""
        var foo: String {
            bar ?? ""
        }
        """#
      ),
      #line: (
        DeclSyntax("let bar = try! (foo())"),
        """
        let bar = try! (foo())
        """
      ),
      #line: (
        DeclSyntax("let bar = try! !functionThatThrows()"),
        """
        let bar = try! !functionThatThrows()
        """
      ),
      #line: (
        DeclSyntax("var bar: Foo { bar.map(Foo.init(raw:)) }"),
        """
        var bar: Foo {
            bar.map(Foo.init(raw:))
        }
        """
      ),
      #line: (
        DeclSyntax("var bar: Foo { bar.map(Foo.init(raw:otherParam:)) }"),
        """
        var bar: Foo {
            bar.map(Foo.init(raw:otherParam:))
        }
        """
      ),
      #line: (
        DeclSyntax("var bar: [String] { bar.map({ $0.description }) }"),
        """
        var bar: [String] {
            bar.map({
                    $0.description
                })
        }
        """
      ),
      #line: (
        DeclSyntax("inout bar: [String] { bar.map({ $0.description }) }"),
        """
        inout bar: [String] {
            bar.map({
                    $0.description
                })
        }
        """
      ),
    ]

    for (line, testCase) in testCases {
      let (builder, expected) = testCase
      AssertBuildResult(builder, expected, line: line)
    }
  }

  @available(*, deprecated) func testVariableDeclWithValue() {
    let leadingTrivia = Trivia.unexpectedText("␣")

    let buildable = VariableDeclSyntax(leadingTrivia: leadingTrivia, bindingKeyword: .keyword(.var)) {
      PatternBindingSyntax(
        pattern: PatternSyntax("d"),
        typeAnnotation: TypeAnnotationSyntax(type: DictionaryTypeSyntax(keyType: TypeSyntax("String"), valueType: TypeSyntax("Int"))),
        initializer: InitializerClauseSyntax(value: DictionaryExprSyntax())
      )
    }

    AssertBuildResult(buildable, "␣var d: [String: Int] = [:]")
  }

  @available(*, deprecated) func testVariableDeclWithExplicitTrailingCommas() {
    let buildable = VariableDeclSyntax(
      bindingKeyword: .keyword(.let),
      bindings: [
        PatternBindingSyntax(
          pattern: PatternSyntax("a"),
          initializer: InitializerClauseSyntax(
            value: ArrayExprSyntax {
              for i in 1...3 {
                ArrayElementSyntax(
                  expression: IntegerLiteralExprSyntax(i),
                  trailingComma: .commaToken().with(\.trailingTrivia, .spaces(3))
                )
              }
            }
          )
        )
      ]
    )
    AssertBuildResult(
      buildable,
      """
      let a = [1,   2,   3,   ]
      """
    )
  }

  @available(*, deprecated) func testMultiPatternVariableDecl() {
    let buildable = VariableDeclSyntax(bindingKeyword: .keyword(.let)) {
      PatternBindingSyntax(
        pattern: PatternSyntax("a"),
        initializer: InitializerClauseSyntax(
          value: ArrayExprSyntax {
            for i in 1...3 {
              ArrayElementSyntax(expression: IntegerLiteralExprSyntax(i))
            }
          }
        )
      )
      PatternBindingSyntax(
        pattern: PatternSyntax("d"),
        initializer: InitializerClauseSyntax(
          value: DictionaryExprSyntax {
            for i in 1...3 {
              DictionaryElementSyntax(keyExpression: StringLiteralExprSyntax(content: "key\(i)"), valueExpression: IntegerLiteralExprSyntax(i))
            }
          }
        )
      )
      PatternBindingSyntax(pattern: PatternSyntax("i"), typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax("Int")))
      PatternBindingSyntax(pattern: PatternSyntax("s"), typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax("String")))
    }
    AssertBuildResult(buildable, #"let a = [1, 2, 3], d = ["key1": 1, "key2": 2, "key3": 3], i: Int, s: String"#)
  }

  @available(*, deprecated) func testClosureTypeVariableDecl() {
    let type = FunctionTypeSyntax(arguments: [TupleTypeElementSyntax(type: TypeSyntax("Int"))], output: ReturnClauseSyntax(returnType: TypeSyntax("Bool")))
    let buildable = VariableDeclSyntax(bindingKeyword: .keyword(.let)) {
      PatternBindingSyntax(pattern: PatternSyntax("c"), typeAnnotation: TypeAnnotationSyntax(type: type))
    }
    AssertBuildResult(buildable, "let c: (Int) -> Bool")
  }

  @available(*, deprecated) func testComputedProperty() throws {
    let testCases: [UInt: (VariableDeclSyntax, String)] = try [
      #line: (
        VariableDeclSyntax("var test: Int") {
          SequenceExprSyntax {
            IntegerLiteralExprSyntax(4)
            BinaryOperatorExprSyntax(text: "+")
            IntegerLiteralExprSyntax(5)
          }
        },
        """
        var test: Int {
            4 + 5
        }
        """
      ),
      #line: (
        try VariableDeclSyntax("var foo: String") {
          StmtSyntax(#"return "hello world""#)
        },
        """
        var foo: String {
            return "hello world"
        }
        """
      ),
    ]

    for (line, testCase) in testCases {
      let (builder, expected) = testCase
      AssertBuildResult(builder, expected, line: line)
    }
  }

  @available(*, deprecated) func testAccessorList() throws {
    let buildable = try VariableDeclSyntax("var test: Int") {
      AccessorDeclSyntax(accessorKind: .keyword(.get)) {
        SequenceExprSyntax {
          IntegerLiteralExprSyntax(4)
          BinaryOperatorExprSyntax(text: "+")
          IntegerLiteralExprSyntax(5)
        }
      }

      AccessorDeclSyntax(accessorKind: .keyword(.willSet)) {}
    }

    AssertBuildResult(
      buildable,
      """
      var test: Int {
          get {
              4 + 5
          }
          willSet {
          }
      }
      """
    )
  }

  @available(*, deprecated) func testAttributedVariables() throws {
    let testCases: [UInt: (VariableDeclSyntax, String)] = try [
      #line: (
        VariableDeclSyntax(
          attributes: AttributeListSyntax { AttributeSyntax(attributeName: TypeSyntax("Test")) },
          .var,
          name: "x",
          type: TypeAnnotationSyntax(type: TypeSyntax("Int"))
        ),
        """
        @Test var x: Int
        """
      ),
      #line: (
        VariableDeclSyntax("@Test var y: String") {
          StringLiteralExprSyntax(content: "Hello world!")
        },
        """
        @Test var y: String {
            "Hello world!"
        }
        """
      ),
      #line: (
        VariableDeclSyntax("@WithArgs(value1, label: value2) var z: Float") {
          FloatLiteralExprSyntax(0.0)
        },
        """
        @WithArgs(value1, label: value2) var z: Float {
            0.0
        }
        """
      ),
      #line: (
        VariableDeclSyntax(
          attributes: AttributeListSyntax {
            AttributeSyntax("WithArgs") {
              TupleExprElementSyntax(expression: ExprSyntax("value"))
            }
          },
          modifiers: [DeclModifierSyntax(name: .keyword(.public))],
          .let,
          name: "z",
          type: TypeAnnotationSyntax(type: TypeSyntax("Float"))
        ),
        """
        @WithArgs(value) public let z: Float
        """
      ),
    ]

    for (line, testCase) in testCases {
      let (builder, expected) = testCase
      AssertBuildResult(builder, expected, line: line)
    }
  }
}
