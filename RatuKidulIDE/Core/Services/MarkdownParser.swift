import Foundation

// MARK: - Markdown Parser

/// Parses markdown files and extracts structured information
actor MarkdownParser {
    static let shared = MarkdownParser()
    
    private init() {}
    
    // MARK: - Parse Markdown
    
    /// Parse a markdown file and return structured content
    func parse(_ content: String) -> ParsedMarkdown {
        var sections: [MarkdownSection] = []
        var codeBlocks: [CodeBlock] = []
        var links: [Link] = []
        var images: [MarkdownImage] = []
        
        let lines = content.components(separatedBy: .newlines)
        var currentSection: MarkdownSection?
        var currentCodeBlock: CodeBlock?
        var inCodeBlock = false
        var codeBlockLanguage: String?
        var codeBlockContent: [String] = []
        var codeBlockStartLine = 0
        
        for (index, line) in lines.enumerated() {
            let lineNumber = index + 1
            
            // Check for code block start/end
            if line.hasPrefix("```") {
                if inCodeBlock {
                    // End of code block
                    if let language = codeBlockLanguage {
                        codeBlocks.append(CodeBlock(
                            language: language,
                            content: codeBlockContent.joined(separator: "\n"),
                            startLine: codeBlockStartLine,
                            endLine: lineNumber
                        ))
                    }
                    codeBlockContent = []
                    codeBlockLanguage = nil
                    inCodeBlock = false
                } else {
                    // Start of code block
                    inCodeBlock = true
                    codeBlockStartLine = lineNumber
                    let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    codeBlockLanguage = language.isEmpty ? nil : language
                }
                continue
            }
            
            if inCodeBlock {
                codeBlockContent.append(line)
                continue
            }
            
            // Parse headings
            if line.hasPrefix("#") {
                // Save previous section
                if let section = currentSection {
                    sections.append(section)
                }
                
                let level = line.prefix(while: { $0 == "#" }).count
                let title = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                
                currentSection = MarkdownSection(
                    level: level,
                    title: title,
                    content: [],
                    startLine: lineNumber
                )
                continue
            }
            
            // Parse links [text](url)
            let linkPattern = #"\[([^\]]+)\]\(([^\)]+)\)"#
            if let regex = try? NSRegularExpression(pattern: linkPattern) {
                let range = NSRange(line.startIndex..., in: line)
                let matches = regex.matches(in: line, range: range)
                for match in matches {
                    if match.numberOfRanges >= 3,
                       let textRange = Range(match.range(at: 1), in: line),
                       let urlRange = Range(match.range(at: 2), in: line) {
                        links.append(Link(
                            text: String(line[textRange]),
                            url: String(line[urlRange]),
                            line: lineNumber
                        ))
                    }
                }
            }
            
            // Parse images ![alt](url)
            let imagePattern = #"!\[([^\]]*)\]\(([^\)]+)\)"#
            if let regex = try? NSRegularExpression(pattern: imagePattern) {
                let range = NSRange(line.startIndex..., in: line)
                let matches = regex.matches(in: line, range: range)
                for match in matches {
                    if match.numberOfRanges >= 3,
                       let altRange = Range(match.range(at: 1), in: line),
                       let urlRange = Range(match.range(at: 2), in: line) {
                        images.append(MarkdownImage(
                            alt: String(line[altRange]),
                            url: String(line[urlRange]),
                            line: lineNumber
                        ))
                    }
                }
            }
            
            // Add line to current section or create default section
            if currentSection == nil {
                currentSection = MarkdownSection(
                    level: 0,
                    title: "Content",
                    content: [],
                    startLine: 1
                )
            }
            
            if var section = currentSection {
                section.content.append(line)
                currentSection = section
            }
        }
        
        // Save last section
        if let section = currentSection {
            sections.append(section)
        }
        
        return ParsedMarkdown(
            sections: sections,
            codeBlocks: codeBlocks,
            links: links,
            images: images,
            totalLines: lines.count
        )
    }
    
    /// Extract code blocks from markdown
    func extractCodeBlocks(_ content: String) -> [CodeBlock] {
        return parse(content).codeBlocks
    }
    
    /// Extract headings structure
    func extractHeadings(_ content: String) -> [MarkdownSection] {
        return parse(content).sections.filter { $0.level > 0 }
    }
    
    /// Get section by title (case-insensitive, partial match)
    func findSection(_ content: String, title: String) -> MarkdownSection? {
        let parsed = parse(content)
        let searchTitle = title.lowercased()
        
        return parsed.sections.first { section in
            section.title.lowercased().contains(searchTitle) ||
            searchTitle.contains(section.title.lowercased())
        }
    }
    
    /// Get code blocks by language
    func getCodeBlocks(_ content: String, language: String) -> [CodeBlock] {
        return parse(content).codeBlocks.filter { $0.language?.lowercased() == language.lowercased() }
    }
}

// MARK: - Data Structures

struct ParsedMarkdown {
    let sections: [MarkdownSection]
    let codeBlocks: [CodeBlock]
    let links: [Link]
    let images: [MarkdownImage]
    let totalLines: Int
    
    /// Get a summary of the markdown structure
    var summary: String {
        var summary = "Markdown Document Summary:\n"
        summary += "- Total lines: \(totalLines)\n"
        summary += "- Sections: \(sections.count)\n"
        summary += "- Code blocks: \(codeBlocks.count)\n"
        summary += "- Links: \(links.count)\n"
        summary += "- Images: \(images.count)\n\n"
        
        if !sections.isEmpty {
            summary += "Sections:\n"
            for section in sections where section.level > 0 {
                let indent = String(repeating: "  ", count: section.level - 1)
                summary += "\(indent)- \(section.title) (line \(section.startLine))\n"
            }
        }
        
        if !codeBlocks.isEmpty {
            summary += "\nCode Blocks:\n"
            for block in codeBlocks {
                let lang = block.language ?? "plain"
                summary += "- \(lang) (lines \(block.startLine)-\(block.endLine))\n"
            }
        }
        
        return summary
    }
}

struct MarkdownSection {
    let level: Int // 1-6 for headings, 0 for content without heading
    let title: String
    var content: [String]
    let startLine: Int
    
    var contentText: String {
        content.joined(separator: "\n")
    }
    
    var isEmpty: Bool {
        content.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

struct CodeBlock {
    let language: String?
    let content: String
    let startLine: Int
    let endLine: Int
    
    var lines: [String] {
        content.components(separatedBy: .newlines)
    }
}

struct Link {
    let text: String
    let url: String
    let line: Int
}

struct MarkdownImage {
    let alt: String
    let url: String
    let line: Int
}


