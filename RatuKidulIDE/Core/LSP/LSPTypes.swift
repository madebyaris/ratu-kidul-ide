import Foundation

// MARK: - Basic Types

/// A position in a text document
struct Position: Codable, Equatable, Hashable {
    /// Line position in a document (zero-based)
    var line: Int
    
    /// Character offset on a line in a document (zero-based)
    var character: Int
    
    init(line: Int, character: Int) {
        self.line = line
        self.character = character
    }
}

/// A range in a text document
struct Range: Codable, Equatable, Hashable {
    /// The range's start position
    var start: Position
    
    /// The range's end position
    var end: Position
    
    init(start: Position, end: Position) {
        self.start = start
        self.end = end
    }
    
    init(startLine: Int, startCharacter: Int, endLine: Int, endCharacter: Int) {
        self.start = Position(line: startLine, character: startCharacter)
        self.end = Position(line: endLine, character: endCharacter)
    }
}

/// Represents a location inside a resource, such as a line inside a text file
struct Location: Codable, Equatable {
    var uri: String
    var range: Range
}

/// Represents a link between a source and a target location
struct LocationLink: Codable, Equatable {
    var originSelectionRange: Range?
    var targetUri: String
    var targetRange: Range
    var targetSelectionRange: Range?
}

// MARK: - Text Document Types

/// Represents a text document identifier
struct TextDocumentIdentifier: Codable, Equatable {
    var uri: String
}

/// Represents a versioned text document identifier
struct VersionedTextDocumentIdentifier: Codable, Equatable {
    var uri: String
    var version: Int
}

/// Represents a text document item
struct TextDocumentItem: Codable {
    var uri: String
    var languageId: String
    var version: Int
    var text: String
}

/// Represents a text document content change event
struct TextDocumentContentChangeEvent: Codable {
    /// The range of the document that changed
    var range: Range?
    
    /// The length of the range that got replaced
    var rangeLength: Int?
    
    /// The new text of the document
    var text: String
}

/// Represents a parameter literal used in requests to pass a text document and a position
struct TextDocumentPositionParams: Codable {
    var textDocument: TextDocumentIdentifier
    var position: Position
}

// MARK: - Diagnostic Types

/// The diagnostic's severity
enum DiagnosticSeverity: Int, Codable {
    case error = 1
    case warning = 2
    case information = 3
    case hint = 4
}

/// Represents a diagnostic, such as a compiler error or warning
struct Diagnostic: Codable, Equatable, Identifiable {
    var id = UUID()
    
    /// The range at which the message applies
    var range: Range
    
    /// The diagnostic's severity
    var severity: DiagnosticSeverity?
    
    /// The diagnostic's code, which might appear in the user interface
    var code: DiagnosticCode?
    
    /// A human-readable string describing the source of this diagnostic
    var source: String?
    
    /// The diagnostic's message
    var message: String
    
    /// Additional metadata about the diagnostic
    var tags: [DiagnosticTag]?
    
    /// An array of related diagnostic information
    var relatedInformation: [DiagnosticRelatedInformation]?
    
    /// A data entry field that is preserved between a `textDocument/publishDiagnostics`
    /// notification and `textDocument/codeAction` request
    var data: AnyCodable?
    
    enum CodingKeys: String, CodingKey {
        case range, severity, code, source, message, tags, relatedInformation, data
    }
}

/// Represents a diagnostic code
enum DiagnosticCode: Codable, Equatable {
    case int(Int)
    case string(String)
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "DiagnosticCode must be Int or String")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        }
    }
}

/// Diagnostic tags
enum DiagnosticTag: Int, Codable {
    case unnecessary = 1
    case deprecated = 2
}

/// Represents a related message and source code location for a diagnostic
struct DiagnosticRelatedInformation: Codable, Equatable {
    var location: Location
    var message: String
}

// MARK: - Completion Types

/// A completion item kind
enum CompletionItemKind: Int, Codable {
    case text = 1
    case method = 2
    case function = 3
    case constructor = 4
    case field = 5
    case variable = 6
    case `class` = 7
    case interface = 8
    case module = 9
    case property = 10
    case unit = 11
    case value = 12
    case `enum` = 13
    case keyword = 14
    case snippet = 15
    case color = 16
    case file = 17
    case reference = 18
    case folder = 19
    case enumMember = 20
    case constant = 21
    case `struct` = 22
    case event = 23
    case `operator` = 24
    case typeParameter = 25
}

/// Defines how the completion was triggered
enum CompletionTriggerKind: Int, Codable {
    case invoked = 1
    case triggerCharacter = 2
    case triggerForIncompleteCompletions = 3
}

/// Additional details about the context in which a completion request is triggered
struct CompletionContext: Codable {
    var triggerKind: CompletionTriggerKind
    var triggerCharacter: String?
}

/// Represents a completion item
struct CompletionItem: Codable, Identifiable {
    var id = UUID()
    
    /// The label of this completion item
    var label: String
    
    /// The kind of this completion item
    var kind: CompletionItemKind?
    
    /// Tags for this completion item
    var tags: [CompletionItemTag]?
    
    /// A human-readable string with additional information about this item
    var detail: String?
    
    /// A human-readable string that represents a doc-comment
    var documentation: CompletionDocumentation?
    
    /// Indicates if this item is deprecated
    var deprecated: Bool?
    
    /// Select this item when showing
    var preselect: Bool?
    
    /// A string that should be used when comparing this item with other items
    var sortText: String?
    
    /// A string that should be used when filtering a set of completion items
    var filterText: String?
    
    /// A string that should be inserted into a document when selecting this completion
    var insertText: String?
    
    /// The format of the insert text
    var insertTextFormat: InsertTextFormat?
    
    /// An edit which is applied to a document when selecting this completion
    var textEdit: TextEdit?
    
    /// An optional array of additional text edits that are applied when selecting this completion
    var additionalTextEdits: [TextEdit]?
    
    /// An optional set of characters that when pressed while this completion is active will accept it first
    var commitCharacters: [String]?
    
    /// An optional command that is executed after inserting this completion
    var command: Command?
    
    /// A data entry field that is preserved on a completion item between a completion and a completion resolve request
    var data: AnyCodable?
    
    enum CodingKeys: String, CodingKey {
        case label, kind, tags, detail, documentation, deprecated, preselect
        case sortText, filterText, insertText, insertTextFormat, textEdit
        case additionalTextEdits, commitCharacters, command, data
    }
}

extension CompletionItem: Equatable {
    static func == (lhs: CompletionItem, rhs: CompletionItem) -> Bool {
        lhs.id == rhs.id && lhs.label == rhs.label
    }
}

/// Completion item tags
enum CompletionItemTag: Int, Codable {
    case deprecated = 1
}

/// Defines whether the insert text in a completion item should be interpreted as plain text or a snippet
enum InsertTextFormat: Int, Codable {
    case plainText = 1
    case snippet = 2
}

/// Represents documentation for a completion item
enum CompletionDocumentation: Codable {
    case string(String)
    case markdown(MarkupContent)
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let markup = try? container.decode(MarkupContent.self) {
            self = .markdown(markup)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "CompletionDocumentation must be String or MarkupContent")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .markdown(let value):
            try container.encode(value)
        }
    }
}

/// Represents a list of completion items
struct CompletionList: Codable {
    /// This list is incomplete. Further results should be fetched
    var isIncomplete: Bool
    
    /// The completion items
    var items: [CompletionItem]
    
    enum CodingKeys: String, CodingKey {
        case isIncomplete, items
    }
}

// MARK: - Text Edit Types

/// A text edit applicable to a text document
struct TextEdit: Codable, Equatable {
    var range: Range
    var newText: String
}

/// A workspace edit represents changes to many resources managed in the workspace
struct WorkspaceEdit: Codable {
    var changes: [String: [TextEdit]]?
    var documentChanges: [TextDocumentEdit]?
}

/// A textual edit applicable to a text document
struct TextDocumentEdit: Codable {
    var textDocument: VersionedTextDocumentIdentifier
    var edits: [TextEdit]
}

// MARK: - Hover Types

/// The result of a hover request
struct Hover: Codable {
    /// The hover's content
    var contents: HoverContents
    
    /// An optional range is a range inside a text document that is used to visualize a hover
    var range: Range?
}

/// The contents of a hover
enum HoverContents: Codable {
    case string(String)
    case markup(MarkupContent)
    case array([MarkupContent])
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let markup = try? container.decode(MarkupContent.self) {
            self = .markup(markup)
        } else if let array = try? container.decode([MarkupContent].self) {
            self = .array(array)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "HoverContents must be String, MarkupContent, or [MarkupContent]")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .markup(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        }
    }
}

// MARK: - Signature Help Types

/// Signature help represents the signature of something callable
struct SignatureHelp: Codable {
    /// The signatures
    var signatures: [SignatureInformation]
    
    /// The active signature
    var activeSignature: Int?
    
    /// The active parameter of the active signature
    var activeParameter: Int?
}

/// Represents the signature of something callable
struct SignatureInformation: Codable {
    /// The label of this signature
    var label: String
    
    /// The human-readable doc-comment of this signature
    var documentation: SignatureDocumentation?
    
    /// The parameters of this signature
    var parameters: [ParameterInformation]?
    
    /// The index of the active parameter
    var activeParameter: Int?
}

/// Represents documentation for a signature
enum SignatureDocumentation: Codable {
    case string(String)
    case markdown(MarkupContent)
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let markup = try? container.decode(MarkupContent.self) {
            self = .markdown(markup)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "SignatureDocumentation must be String or MarkupContent")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .markdown(let value):
            try container.encode(value)
        }
    }
}

/// Represents a parameter of a callable-signature
struct ParameterInformation: Codable {
    /// The label of this parameter
    var label: ParameterLabel
    
    /// The human-readable doc-comment of this parameter
    var documentation: SignatureDocumentation?
}

/// Represents the label of a parameter
enum ParameterLabel: Codable {
    case string(String)
    case tuple(start: Int, end: Int)
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([Int].self), array.count == 2 {
            self = .tuple(start: array[0], end: array[1])
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "ParameterLabel must be String or [Int, Int]")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .tuple(let start, let end):
            try container.encode([start, end])
        }
    }
}

// MARK: - Markup Content

/// A `MarkupContent` literal represents a string value which content is interpreted based on its kind flag
struct MarkupContent: Codable, Equatable {
    /// The type of the Markup
    var kind: MarkupKind
    
    /// The content itself
    var value: String
}

/// Describes the content type that a client supports in various result literals
enum MarkupKind: String, Codable {
    case plaintext = "plaintext"
    case markdown = "markdown"
}

// MARK: - Command Types

/// Represents a reference to a command
struct Command: Codable {
    /// Title of the command, like `save`
    var title: String
    
    /// The identifier of the actual command handler
    var command: String
    
    /// Arguments that the command handler should be invoked with
    var arguments: [AnyCodable]?
}

extension Command: Equatable {
    static func == (lhs: Command, rhs: Command) -> Bool {
        lhs.title == rhs.title && 
        lhs.command == rhs.command &&
        lhs.arguments == rhs.arguments
    }
}

// MARK: - Code Action Types

/// A code action represents a change that can be performed in code
struct CodeAction: Codable, Identifiable {
    var id = UUID()
    
    /// A short, human-readable, title for this code action
    var title: String
    
    /// The kind of the code action
    var kind: CodeActionKind?
    
    /// The diagnostics that this code action resolves
    var diagnostics: [Diagnostic]?
    
    /// Marks this as a preferred action
    var isPreferred: Bool?
    
    /// Marks that the code action cannot be applied a second time
    var disabled: CodeActionDisabled?
    
    /// The workspace edit this code action performs
    var edit: WorkspaceEdit?
    
    /// A command this code action executes
    var command: Command?
    
    /// A data entry field that is preserved on a code action between a `textDocument/codeAction` and a `codeAction/resolve` request
    var data: AnyCodable?
    
    enum CodingKeys: String, CodingKey {
        case title, kind, diagnostics, isPreferred, disabled, edit, command, data
    }
}

extension CodeAction: Equatable {
    static func == (lhs: CodeAction, rhs: CodeAction) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title
    }
}

/// The kind of a code action
enum CodeActionKind: String, Codable {
    case empty = ""
    case quickFix = "quickfix"
    case refactor = "refactor"
    case refactorExtract = "refactor.extract"
    case refactorInline = "refactor.inline"
    case refactorRewrite = "refactor.rewrite"
    case source = "source"
    case sourceOrganizeImports = "source.organizeImports"
    case sourceFixAll = "source.fixAll"
}

/// Marks that the code action cannot be applied a second time
struct CodeActionDisabled: Codable {
    var reason: String
}

// MARK: - Symbol Types

/// A symbol kind
enum SymbolKind: Int, Codable {
    case file = 1
    case module = 2
    case namespace = 3
    case package = 4
    case `class` = 5
    case method = 6
    case property = 7
    case field = 8
    case constructor = 9
    case `enum` = 10
    case interface = 11
    case function = 12
    case variable = 13
    case constant = 14
    case string = 15
    case number = 16
    case boolean = 17
    case array = 18
    case object = 19
    case key = 20
    case null = 21
    case enumMember = 22
    case `struct` = 23
    case event = 24
    case `operator` = 25
    case typeParameter = 26
}

/// Represents information about programming constructs like variables, classes, interfaces etc
struct DocumentSymbol: Codable, Equatable, Identifiable {
    var id = UUID()
    
    /// The name of this symbol
    var name: String
    
    /// More detail for this symbol
    var detail: String?
    
    /// The kind of this symbol
    var kind: SymbolKind
    
    /// Tags for this symbol
    var tags: [SymbolTag]?
    
    /// Indicates if this symbol is deprecated
    var deprecated: Bool?
    
    /// The range enclosing this symbol not including leading/trailing whitespace
    var range: Range
    
    /// The range that should be selected and revealed when this symbol is being picked
    var selectionRange: Range
    
    /// Children of this symbol
    var children: [DocumentSymbol]?
}

/// Symbol tags
enum SymbolTag: Int, Codable {
    case deprecated = 1
}

// MARK: - Formatting Types

/// Value-object describing what options formatting should use
struct FormattingOptions: Codable {
    /// Size of a tab in spaces
    var tabSize: Int
    
    /// Prefer spaces over tabs
    var insertSpaces: Bool
    
    /// Trim trailing whitespace on a line
    var trimTrailingWhitespace: Bool?
    
    /// Insert a newline character at the end of the file if one does not exist
    var insertFinalNewline: Bool?
    
    /// Trim all newlines after the final newline at the end of the file
    var trimFinalNewlines: Bool?
}

// Note: AnyCodable is defined in AIProvider.swift
