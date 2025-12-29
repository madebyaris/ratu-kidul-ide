import Foundation

// MARK: - Text Tool Parser

/// Parses tool calls from text output when models don't use native function calling
@MainActor
final class TextToolParser {
    static let shared = TextToolParser()
    
    private init() {}
    
    /// Parse tool calls from text output
    /// Handles multiple formats:
    /// - XML-style: <tool_call>{"name": "...", "arguments": {...}}</tool_call>
    /// - Markdown-style: 🔧 **tool_name**\n<arguments>
    /// - MiniMax format: 🔧 **tool_name**>\n<parameter>...</parameter>\n</invoke></tool_call>
    /// - JSON in code blocks: ```json\n{"tool": "...", "args": {...}}\n```
    func parse(_ text: String) -> [ToolCall]? {
        print("🔍 [TextToolParser] Attempting to parse tool calls from text (length: \(text.count))")
        print("   Text preview: \(String(text.prefix(200)))...")
        
        var toolCalls: [ToolCall] = []
        
        // Pattern 1: MiniMax-specific format (check this first as it's most specific)
        // 🔧 **file_list_directory**>\n<parameter name="path">...</parameter>\n</invoke></tool_call>
        if let minimaxTools = parseMiniMaxFormat(text) {
            print("✅ [TextToolParser] Found \(minimaxTools.count) tool(s) via MiniMax format parser")
            toolCalls.append(contentsOf: minimaxTools)
        }
        
        // Pattern 2: XML-style tool calls
        // <tool_call>{"name": "read_file", "arguments": {"path": "..."}}</tool_call>
        if let xmlTools = parseXMLStyle(text) {
            toolCalls.append(contentsOf: xmlTools)
        }
        
        // Pattern 3: Markdown-style tool calls
        // 🔧 **file_list_directory**\n/Users/aris/...
        if let markdownTools = parseMarkdownStyle(text) {
            toolCalls.append(contentsOf: markdownTools)
        }
        
        // Pattern 4: JSON in code blocks
        // ```json\n{"tool": "read_file", "args": {"path": "..."}}\n```
        if let jsonTools = parseJSONCodeBlocks(text) {
            toolCalls.append(contentsOf: jsonTools)
        }
        
        if toolCalls.isEmpty {
            print("❌ [TextToolParser] No tool calls found in text")
        } else {
            print("✅ [TextToolParser] Successfully parsed \(toolCalls.count) tool call(s)")
        }
        
        return toolCalls.isEmpty ? nil : toolCalls
    }
    
    // MARK: - MiniMax Format Parser
    
    private func parseMiniMaxFormat(_ text: String) -> [ToolCall]? {
        var tools: [ToolCall] = []
        
        // Debug: Show what we're searching in
        if text.contains("🔧") {
            let toolCallSnippet = text.components(separatedBy: "🔧").last ?? ""
            print("🔍 [TextToolParser] Found 🔧 marker. Snippet: \(String(toolCallSnippet.prefix(300)))")
            print("🔍 [TextToolParser] Full text length: \(text.count), contains </tool_call>: \(text.contains("</tool_call>"))")
        } else {
            print("⚠️ [TextToolParser] No 🔧 marker found in text")
        }
        
        // Pattern 1: Exact format with closing tags
        // 🔧 **tool_name**>\n<parameter>...</parameter>\n</invoke>\n</tool_call>
        // Note: The format can have newlines between elements, so we use .dotMatchesLineSeparators
        let pattern1 = #"🔧\s*\*\*([^*]+)\*\*>\s*[\r\n]+(.*?)</invoke>\s*[\r\n]+\s*</tool_call>"#
        if let regex1 = try? NSRegularExpression(pattern: pattern1, options: [.dotMatchesLineSeparators]) {
            let matches = regex1.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
            print("🔍 [TextToolParser] Pattern 1 (with > and closing tags) found \(matches.count) match(es)")
            
            // Debug: Show what we're trying to match
            if matches.isEmpty {
                // Try to find where the pattern fails
                if let toolStart = text.range(of: "🔧") {
                    let afterTool = String(text[toolStart.upperBound...])
                    print("🔍 [TextToolParser] Debug - Text after 🔧: \(String(afterTool.prefix(200)))")
                }
            }
            
            for match in matches {
                guard let toolNameRange = Range(match.range(at: 1), in: text),
                      let argsRange = Range(match.range(at: 2), in: text) else { continue }
                
                let toolName = String(text[toolNameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                var argsText = String(text[argsRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Remove closing tags
                argsText = argsText.replacingOccurrences(of: "</invoke>", with: "")
                argsText = argsText.replacingOccurrences(of: "</tool_call>", with: "")
                argsText = argsText.trimmingCharacters(in: .whitespacesAndNewlines)
                
                let normalizedToolName = normalizeToolName(toolName)
                
                if let args = parseXMLParameters(argsText) {
                    print("✅ [TextToolParser] Parsed tool (pattern 1): \(normalizedToolName) with \(args.count) parameters")
                    tools.append(ToolCall(
                        id: UUID().uuidString,
                        name: normalizedToolName,
                        arguments: args
                    ))
                } else if let args = parseSimpleArguments(argsText, toolName: normalizedToolName) {
                    print("✅ [TextToolParser] Parsed tool (pattern 1, simple): \(normalizedToolName) with \(args.count) parameters")
                    tools.append(ToolCall(
                        id: UUID().uuidString,
                        name: normalizedToolName,
                        arguments: args
                    ))
                }
            }
            
            if !tools.isEmpty {
                return tools
            }
        }
        
        // Pattern 2: Without > character
        let pattern2 = #"🔧\s*\*\*([^*]+)\*\*\s*\n(.*?)</invoke>\s*</tool_call>"#
        if let regex2 = try? NSRegularExpression(pattern: pattern2, options: [.dotMatchesLineSeparators]) {
            let matches = regex2.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
            print("🔍 [TextToolParser] Pattern 2 (without >, with closing tags) found \(matches.count) match(es)")
            
            for match in matches {
                guard let toolNameRange = Range(match.range(at: 1), in: text),
                      let argsRange = Range(match.range(at: 2), in: text) else { continue }
                
                let toolName = String(text[toolNameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                var argsText = String(text[argsRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                
                argsText = argsText.replacingOccurrences(of: "</invoke>", with: "")
                argsText = argsText.replacingOccurrences(of: "</tool_call>", with: "")
                argsText = argsText.trimmingCharacters(in: .whitespacesAndNewlines)
                
                let normalizedToolName = normalizeToolName(toolName)
                
                if let args = parseXMLParameters(argsText) {
                    print("✅ [TextToolParser] Parsed tool (pattern 2): \(normalizedToolName) with \(args.count) parameters")
                    tools.append(ToolCall(
                        id: UUID().uuidString,
                        name: normalizedToolName,
                        arguments: args
                    ))
                }
            }
            
            if !tools.isEmpty {
                return tools
            }
        }
        
        // Pattern 3: Without closing tags (fallback)
        print("⚠️ [TextToolParser] Trying pattern without closing tags...")
        let pattern3 = #"🔧\s*\*\*([^*]+)\*\*[>]?\s*\n(.*?)(?=🔧|$)"#
        if let regex3 = try? NSRegularExpression(pattern: pattern3, options: [.dotMatchesLineSeparators]) {
            let matches = regex3.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
            print("🔍 [TextToolParser] Pattern 3 (no closing tags) found \(matches.count) match(es)")
            
            for match in matches {
                guard let toolNameRange = Range(match.range(at: 1), in: text),
                      let argsRange = Range(match.range(at: 2), in: text) else { continue }
                
                let toolName = String(text[toolNameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                var argsText = String(text[argsRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Remove closing tags if present
                argsText = argsText.replacingOccurrences(of: "</invoke>", with: "")
                argsText = argsText.replacingOccurrences(of: "</tool_call>", with: "")
                argsText = argsText.trimmingCharacters(in: .whitespacesAndNewlines)
                
                let normalizedToolName = normalizeToolName(toolName)
                
                if let args = parseXMLParameters(argsText) {
                    print("✅ [TextToolParser] Parsed tool (pattern 3): \(normalizedToolName) with \(args.count) parameters")
                    tools.append(ToolCall(
                        id: UUID().uuidString,
                        name: normalizedToolName,
                        arguments: args
                    ))
                } else if let args = parseSimpleArguments(argsText, toolName: normalizedToolName) {
                    print("✅ [TextToolParser] Parsed tool (pattern 3, simple): \(normalizedToolName) with \(args.count) parameters")
                    tools.append(ToolCall(
                        id: UUID().uuidString,
                        name: normalizedToolName,
                        arguments: args
                    ))
                }
            }
            
            if !tools.isEmpty {
                return tools
            }
        }
        
        // Pattern 4: Very simple - just find 🔧 and extract until </tool_call>
        if text.contains("🔧") && text.contains("</tool_call>") {
            print("⚠️ [TextToolParser] Trying simple extraction pattern...")
            if let toolStart = text.range(of: "🔧"),
               let toolEnd = text.range(of: "</tool_call>", range: toolStart.upperBound..<text.endIndex) {
                var toolCallText = String(text[toolStart.upperBound..<toolEnd.lowerBound])
                
                print("🔍 [TextToolParser] Pattern 4 - Extracted tool call text (raw): \(String(toolCallText.prefix(150)))")
                
                // Clean up the text first (remove leading/trailing whitespace)
                toolCallText = toolCallText.trimmingCharacters(in: .whitespacesAndNewlines)
                
                print("🔍 [TextToolParser] Pattern 4 - After trim: \(String(toolCallText.prefix(150)))")
                
                // Extract tool name - handle two formats:
                // Format 1: **tool_name**> (with second **)
                // Format 2: **tool_name"> (no second **, just >)
                var toolName: String?
                var argsTextStart: String.Index?
                
                if let nameStart = toolCallText.range(of: "**") {
                    // Try Format 1: Look for second **
                    let searchStart = toolCallText.index(nameStart.upperBound, offsetBy: 0)
                    let searchRange = searchStart..<toolCallText.endIndex
                    
                    if let nameEnd = toolCallText.range(of: "**", range: searchRange) {
                        // Format 1: **tool_name**>
                        toolName = String(toolCallText[nameStart.upperBound..<nameEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                        argsTextStart = nameEnd.upperBound
                        print("🔍 [TextToolParser] Pattern 4 - Found tool name (format 1): \(toolName!)")
                    } else {
                        // Format 2: **tool_name"> (no second **, has quote before >)
                        // Try to find "> first, then fall back to just >
                        if let quoteGtIndex = toolCallText.range(of: "\">", range: nameStart.upperBound..<toolCallText.endIndex) {
                            toolName = String(toolCallText[nameStart.upperBound..<quoteGtIndex.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                            argsTextStart = toolCallText.index(quoteGtIndex.upperBound, offsetBy: 0)
                            print("🔍 [TextToolParser] Pattern 4 - Found tool name (format 2 with quote): \(toolName!)")
                        } else if let gtIndex = toolCallText.range(of: ">", range: nameStart.upperBound..<toolCallText.endIndex) {
                            toolName = String(toolCallText[nameStart.upperBound..<gtIndex.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                            argsTextStart = toolCallText.index(gtIndex.upperBound, offsetBy: 0)
                            print("🔍 [TextToolParser] Pattern 4 - Found tool name (format 2 without quote): \(toolName!)")
                        }
                    }
                }
                
                if let toolName = toolName, let argsStart = argsTextStart {
                    // Get everything after the tool name marker
                    var argsText = String(toolCallText[argsStart...])
                    
                    // Remove closing tags
                    argsText = argsText
                        .replacingOccurrences(of: "</invoke>", with: "")
                        .replacingOccurrences(of: "</tool_call>", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        
                    print("🔍 [TextToolParser] Pattern 4 - Tool: \(toolName), Args: \(String(argsText.prefix(100)))")
                    
                    let normalizedToolName = normalizeToolName(toolName)
                    
                    if let args = parseXMLParameters(argsText) {
                        print("✅ [TextToolParser] Parsed tool (simple extraction): \(normalizedToolName) with \(args.count) parameters")
                        tools.append(ToolCall(
                            id: UUID().uuidString,
                            name: normalizedToolName,
                            arguments: args
                        ))
                        return tools
                    } else {
                        // Try simple argument parsing
                        if let args = parseSimpleArguments(argsText, toolName: normalizedToolName) {
                            print("✅ [TextToolParser] Parsed tool (simple extraction, simple args): \(normalizedToolName) with \(args.count) parameters")
                            tools.append(ToolCall(
                                id: UUID().uuidString,
                                name: normalizedToolName,
                                arguments: args
                            ))
                            return tools
                        } else {
                            print("⚠️ [TextToolParser] Pattern 4 - Failed to parse args for \(toolName)")
                            print("   Args text: \(argsText)")
                        }
                    }
                } else {
                    print("⚠️ [TextToolParser] Pattern 4 - Could not extract tool name")
                    print("   Text: \(String(toolCallText.prefix(100)))")
                }
            }
        }
        
        // If still no matches, try a very simple pattern that just finds 🔧 markers
        if tools.isEmpty {
            print("⚠️ [TextToolParser] Trying simple 🔧 marker search...")
            let simplePattern = #"🔧\s*\*\*([^*]+)\*\*"#
            if let simpleRegex = try? NSRegularExpression(pattern: simplePattern, options: []) {
                let simpleMatches = simpleRegex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
                print("🔍 [TextToolParser] Simple pattern found \(simpleMatches.count) 🔧 marker(s)")
                
                for match in simpleMatches {
                    guard let toolNameRange = Range(match.range(at: 1), in: text) else { continue }
                    let toolName = String(text[toolNameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // Find the text after this match until </tool_call> or next 🔧 or end
                    let matchEnd = match.range.upperBound
                    let startIndex = text.index(text.startIndex, offsetBy: matchEnd)
                    let remainingRange = startIndex..<text.endIndex
                    let remainingText = String(text[remainingRange])
                    
                    // Try to extract parameters from the remaining text
                    if let args = parseXMLParameters(remainingText) {
                        let normalizedToolName = normalizeToolName(toolName)
                        print("✅ [TextToolParser] Parsed tool via simple pattern: \(normalizedToolName) with \(args.count) parameters")
                        tools.append(ToolCall(
                            id: UUID().uuidString,
                            name: normalizedToolName,
                            arguments: args
                        ))
                    } else {
                        // Debug: show what we're trying to parse
                        print("⚠️ [TextToolParser] Failed to parse args for \(toolName)")
                        print("   Remaining text preview: \(String(remainingText.prefix(200)))")
                    }
                }
            }
        }
        
        // Final fallback: Direct string search with improved parsing
        if tools.isEmpty && text.contains("🔧") && text.contains("<parameter") {
            print("⚠️ [TextToolParser] Trying direct string extraction...")
            // Find all 🔧 markers
            var searchRange = text.startIndex..<text.endIndex
            while let toolMarkerRange = text.range(of: "🔧", range: searchRange) {
                // Find the tool name between ** markers
                let afterMarker = text.index(toolMarkerRange.upperBound, offsetBy: 0)
                let remainingAfterMarker = String(text[afterMarker...])
                
                if let nameStart = remainingAfterMarker.range(of: "**"),
                   let nameEnd = remainingAfterMarker.range(of: "**", range: nameStart.upperBound..<remainingAfterMarker.endIndex) {
                    let toolName = String(remainingAfterMarker[nameStart.upperBound..<nameEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // Find parameters after the tool name (skip the > character and any whitespace)
                    let afterNameEnd = remainingAfterMarker.index(nameEnd.upperBound, offsetBy: 0)
                    var paramsText = String(remainingAfterMarker[afterNameEnd...])
                    
                    // Skip past the > character if present
                    if let gtIndex = paramsText.firstIndex(of: ">") {
                        paramsText = String(paramsText[paramsText.index(after: gtIndex)...])
                    }
                    
                    // Extract until </tool_call> if present
                    let finalParamsText: String
                    if let toolCallEnd = paramsText.range(of: "</tool_call>") {
                        finalParamsText = String(paramsText[..<toolCallEnd.lowerBound])
                    } else if let invokeEnd = paramsText.range(of: "</invoke>") {
                        // Sometimes </invoke> comes before </tool_call>
                        finalParamsText = String(paramsText[..<invokeEnd.lowerBound])
                    } else {
                        finalParamsText = paramsText
                    }
                    
                    // Clean up the params text
                    let cleanedParams = finalParamsText
                        .replacingOccurrences(of: "</invoke>", with: "")
                        .replacingOccurrences(of: "</tool_call>", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    print("🔍 [TextToolParser] Direct extraction - Tool: \(toolName), Params text: \(String(cleanedParams.prefix(100)))")
                    
                    if let args = parseXMLParameters(cleanedParams) {
                        let normalizedToolName = normalizeToolName(toolName)
                        print("✅ [TextToolParser] Parsed tool via direct extraction: \(normalizedToolName) with \(args.count) parameters")
                        tools.append(ToolCall(
                            id: UUID().uuidString,
                            name: normalizedToolName,
                            arguments: args
                        ))
                    } else {
                        // Try simple argument parsing as fallback
                        if let args = parseSimpleArguments(cleanedParams, toolName: toolName) {
                            let normalizedToolName = normalizeToolName(toolName)
                            print("✅ [TextToolParser] Parsed tool via direct extraction (simple): \(normalizedToolName) with \(args.count) parameters")
                            tools.append(ToolCall(
                                id: UUID().uuidString,
                                name: normalizedToolName,
                                arguments: args
                            ))
                        }
                    }
                }
                
                // Move search range forward
                searchRange = text.index(toolMarkerRange.upperBound, offsetBy: 1)..<text.endIndex
            }
        }
        
        return tools.isEmpty ? nil : tools
    }
    
    // MARK: - XML Style Parser
    
    private func parseXMLStyle(_ text: String) -> [ToolCall]? {
        var tools: [ToolCall] = []
        
        // Pattern: <tool_call>...</tool_call>
        let xmlPattern = #"<tool_call[^>]*>(.*?)</tool_call>"#
        let regex = try? NSRegularExpression(pattern: xmlPattern, options: [.dotMatchesLineSeparators])
        
        guard let regex = regex else { return nil }
        
        let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        
        for match in matches {
            guard let range = Range(match.range(at: 1), in: text) else { continue }
            let jsonContent = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let toolCall = parseJSONToolCall(jsonContent) {
                tools.append(toolCall)
            }
        }
        
        return tools.isEmpty ? nil : tools
    }
    
    // MARK: - Markdown Style Parser
    
    private func parseMarkdownStyle(_ text: String) -> [ToolCall]? {
        var tools: [ToolCall] = []
        
        // Pattern: 🔧 **tool_name**\n<parameter>value</parameter>
        // Or: 🔧 **tool_name**\n/path/to/file
        let markdownPattern = #"🔧\s*\*\*([^*]+)\*\*[^\n]*\n(.*?)(?=🔧|$)"#
        let regex = try? NSRegularExpression(pattern: markdownPattern, options: [.dotMatchesLineSeparators])
        
        guard let regex = regex else { return nil }
        
        let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        
        for match in matches {
            guard let toolNameRange = Range(match.range(at: 1), in: text),
                  let argsRange = Range(match.range(at: 2), in: text) else { continue }
            
            let toolName = String(text[toolNameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let argsText = String(text[argsRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Try to parse as XML parameters first
            if let args = parseXMLParameters(argsText) {
                tools.append(ToolCall(
                    id: UUID().uuidString,
                    name: toolName,
                    arguments: args
                ))
            } else {
                // Try to parse as simple path/value
                if let args = parseSimpleArguments(argsText, toolName: toolName) {
                    tools.append(ToolCall(
                        id: UUID().uuidString,
                        name: toolName,
                        arguments: args
                    ))
                }
            }
        }
        
        return tools.isEmpty ? nil : tools
    }
    
    // MARK: - JSON Code Block Parser
    
    private func parseJSONCodeBlocks(_ text: String) -> [ToolCall]? {
        var tools: [ToolCall] = []
        
        // Pattern: ```json\n{...}\n```
        let codeBlockPattern = #"```(?:json)?\s*\n(.*?)\n```"#
        let regex = try? NSRegularExpression(pattern: codeBlockPattern, options: [.dotMatchesLineSeparators])
        
        guard let regex = regex else { return nil }
        
        let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        
        for match in matches {
            guard let range = Range(match.range(at: 1), in: text) else { continue }
            let jsonContent = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let toolCall = parseJSONToolCall(jsonContent) {
                tools.append(toolCall)
            }
        }
        
        return tools.isEmpty ? nil : tools
    }
    
    // MARK: - JSON Parsing Helpers
    
    private func parseJSONToolCall(_ jsonString: String) -> ToolCall? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        
        // Try standard format: {"name": "...", "arguments": {...}}
        if let standard = try? JSONDecoder().decode(StandardToolCall.self, from: data) {
            return ToolCall(
                id: UUID().uuidString,
                name: standard.name,
                arguments: standard.arguments.mapValues { AnyCodable($0) }
            )
        }
        
        // Try alternative format: {"tool": "...", "args": {...}}
        if let alt = try? JSONDecoder().decode(AlternativeToolCall.self, from: data) {
            return ToolCall(
                id: UUID().uuidString,
                name: alt.tool,
                arguments: alt.args.mapValues { AnyCodable($0) }
            )
        }
        
        // Try parsing as generic dictionary
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let name = dict["name"] as? String ?? dict["tool"] as? String {
                let argsDict = (dict["arguments"] as? [String: Any]) ?? (dict["args"] as? [String: Any]) ?? [:]
                return ToolCall(
                    id: UUID().uuidString,
                    name: name,
                    arguments: argsDict.mapValues { AnyCodable($0) }
                )
            }
        }
        
        return nil
    }
    
    private func parseXMLParameters(_ text: String) -> [String: AnyCodable]? {
        // Wrap the text in a root element to make it valid XML
        // This handles cases where we have multiple <parameter> tags
        let xmlText: String
        if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") {
            // Already looks like XML, wrap it
            xmlText = "<root>\(text)</root>"
        } else {
            // Try to extract XML-like structures
            xmlText = "<root>\(text)</root>"
        }
        
        guard let xmlData = xmlText.data(using: .utf8) else {
            return nil
        }
        
        let parser = XMLParser(data: xmlData)
        let delegate = ParameterXMLDelegate()
        parser.delegate = delegate
        
        if parser.parse() {
            return delegate.parameters.isEmpty ? nil : delegate.parameters
        } else {
            // XMLParser failed, fall back to regex for malformed XML
            return parseXMLParametersRegex(text)
        }
    }
    
    /// Fallback regex-based parser for malformed XML
    private func parseXMLParametersRegex(_ text: String) -> [String: AnyCodable]? {
        var args: [String: AnyCodable] = [:]
        
        // Pattern: <parameter name="key">value</parameter>
        let paramPattern = #"<parameter\s+name="([^"]+)">(.*?)</parameter>"#
        let regex = try? NSRegularExpression(pattern: paramPattern, options: [.dotMatchesLineSeparators])
        
        guard let regex = regex else { return nil }
        
        let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        
        for match in matches {
            guard let nameRange = Range(match.range(at: 1), in: text),
                  let valueRange = Range(match.range(at: 2), in: text) else { continue }
            
            let name = String(text[nameRange])
            let value = String(text[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            args[name] = AnyCodable(value)
        }
        
        return args.isEmpty ? nil : args
    }
    
    private func parseSimpleArguments(_ text: String, toolName: String) -> [String: AnyCodable]? {
        // For simple cases like a path, try to infer the parameter name
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.isEmpty {
            return nil
        }
        
        // Common parameter names based on tool name
        var paramName = "path"
        
        if toolName.contains("command") || toolName.contains("run") {
            paramName = "command"
        } else if toolName.contains("pattern") || toolName.contains("search") {
            paramName = "pattern"
        } else if toolName.contains("file") || toolName.contains("directory") {
            paramName = "path"
        }
        
        return [paramName: AnyCodable(trimmed)]
    }
    
    /// Normalize tool name to match registry format
    /// Handles variations like "file_list_directory" -> "file_list_directory" or "list_directory"
    private func normalizeToolName(_ name: String) -> String {
        // Tool names in registry can be either namespaced (file_list_directory) or non-namespaced (list_directory)
        // The ToolExecutor handles both, so we can return as-is
        // But we should handle common variations
        
        // Remove any leading/trailing whitespace
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // The tool name should match what's in the registry
        // Since ToolExecutor normalizes names, we can return the name as-is
        return trimmed
    }
}

// MARK: - Helper Types

private struct StandardToolCall: Codable {
    let name: String
    let arguments: [String: AnyCodable]
}

private struct AlternativeToolCall: Codable {
    let tool: String
    let args: [String: AnyCodable]
}

// MARK: - XML Parser Delegate

private class ParameterXMLDelegate: NSObject, XMLParserDelegate {
    var parameters: [String: AnyCodable] = [:]
    private var currentElement: String?
    private var currentParameterName: String?
    private var currentValue: String = ""
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        
        if elementName == "parameter" {
            // Extract the name attribute
            currentParameterName = attributeDict["name"]
            currentValue = ""
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentElement == "parameter" {
            currentValue += string
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "parameter", let name = currentParameterName {
            let trimmedValue = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedValue.isEmpty {
                parameters[name] = AnyCodable(trimmedValue)
            }
            currentParameterName = nil
            currentValue = ""
        }
        currentElement = nil
    }
    
    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        // Silently handle parse errors - we'll fall back to regex
    }
}

