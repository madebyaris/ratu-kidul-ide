import Foundation
import SwiftUI
import Markdown

// MARK: - MarkdownRenderer
//
// Uses swift-markdown (cmark-gfm) to parse, then converts a subset of nodes into an AttributedString
// that SwiftUI can render nicely in chat (bold/italic, headings, links, lists, code).
//
// Ref: https://github.com/swiftlang/swift-markdown

@MainActor
final class MarkdownRenderer {
    static let shared = MarkdownRenderer()

    private init() {}

    func render(_ markdown: String, baseFontSize: CGFloat) -> AttributedString {
        let doc = Document(parsing: markdown)
        var out = AttributedString()
        var ctx = RenderContext(baseFontSize: baseFontSize)
        renderChildren(of: doc, into: &out, ctx: &ctx)
        return out
    }

    // MARK: - Rendering

    private func renderChildren(of markup: Markup, into out: inout AttributedString, ctx: inout RenderContext) {
        for child in markup.children {
            renderNode(child, into: &out, ctx: &ctx)
        }
    }

    private func renderNode(_ node: Markup, into out: inout AttributedString, ctx: inout RenderContext) {
        switch node {
        case let t as Markdown.Text:
            var s = AttributedString(t.string)
            applyInlineStyles(to: &s, ctx: ctx)
            out.append(s)

        case let soft as Markdown.SoftBreak:
            out.append(AttributedString("\n"))

        case let br as Markdown.LineBreak:
            _ = br
            out.append(AttributedString("\n"))

        case let para as Markdown.Paragraph:
            renderChildren(of: para, into: &out, ctx: &ctx)
            out.append(AttributedString("\n\n"))

        case let strong as Markdown.Strong:
            let prevBold = ctx.isBold
            ctx.isBold = true
            renderChildren(of: strong, into: &out, ctx: &ctx)
            ctx.isBold = prevBold

        case let emph as Markdown.Emphasis:
            let prevItalic = ctx.isItalic
            ctx.isItalic = true
            renderChildren(of: emph, into: &out, ctx: &ctx)
            ctx.isItalic = prevItalic

        case let code as Markdown.InlineCode:
            var s = AttributedString(code.code)
            s.font = SwiftUI.Font.system(size: ctx.baseFontSize, weight: .regular, design: .monospaced)
            s.backgroundColor = Color(.controlBackgroundColor).opacity(0.6)
            out.append(s)

        case let link as Markdown.Link:
            var inner = AttributedString()
            renderChildren(of: link, into: &inner, ctx: &ctx)
            if let dest = link.destination, let url = URL(string: dest) {
                inner.link = url
                inner.foregroundColor = .accentColor
                inner.underlineStyle = .single
            }
            out.append(inner)

        case let heading as Markdown.Heading:
            // Render heading text on its own line with stronger font
            var inner = AttributedString()
            let prevHeading = ctx.headingLevel
            ctx.headingLevel = heading.level
            renderChildren(of: heading, into: &inner, ctx: &ctx)
            ctx.headingLevel = prevHeading

            // Ensure separation
            out.append(inner)
            out.append(AttributedString("\n\n"))

        case let blockquote as Markdown.BlockQuote:
            // Simple block quote styling: prefix each paragraph line with a bar
            var inner = AttributedString()
            let prevQuote = ctx.isQuote
            ctx.isQuote = true
            renderChildren(of: blockquote, into: &inner, ctx: &ctx)
            ctx.isQuote = prevQuote
            out.append(inner)
            out.append(AttributedString("\n"))

        case let list as Markdown.UnorderedList:
            renderListItems(Array(list.listItems), into: &out, ctx: &ctx, ordered: false)
            out.append(AttributedString("\n"))

        case let list as Markdown.OrderedList:
            renderListItems(Array(list.listItems), into: &out, ctx: &ctx, ordered: true, start: Int(list.startIndex))
            out.append(AttributedString("\n"))

        case let item as Markdown.ListItem:
            // Should be handled by renderListItems, but keep a fallback
            out.append(AttributedString("• "))
            renderChildren(of: item, into: &out, ctx: &ctx)
            out.append(AttributedString("\n"))

        case let codeBlock as Markdown.CodeBlock:
            // Render fenced code block
            let code = codeBlock.code
            var s = AttributedString(code.hasSuffix("\n") ? code : code + "\n")
            s.font = SwiftUI.Font.system(size: ctx.baseFontSize, weight: .regular, design: .monospaced)
            s.foregroundColor = Color.primary
            s.backgroundColor = Color(.textBackgroundColor).opacity(0.45)
            out.append(s)
            out.append(AttributedString("\n"))

        case let thematic as Markdown.ThematicBreak:
            _ = thematic
            var s = AttributedString("──────────")
            s.foregroundColor = .secondary
            out.append(s)
            out.append(AttributedString("\n\n"))

        default:
            // For nodes we don't explicitly handle, recurse to children.
            renderChildren(of: node, into: &out, ctx: &ctx)
        }
    }

    private func renderListItems(
        _ items: [Markdown.ListItem],
        into out: inout AttributedString,
        ctx: inout RenderContext,
        ordered: Bool,
        start: Int? = nil
    ) {
        var index = start ?? 1
        for item in items {
            let prefix = ordered ? "\(index). " : "• "
            var p = AttributedString(prefix)
            p.foregroundColor = .secondary
            p.font = .system(size: ctx.baseFontSize, weight: .regular)
            out.append(p)

            renderChildren(of: item, into: &out, ctx: &ctx)
            out.append(AttributedString("\n"))
            index += 1
        }
    }

    private func applyInlineStyles(to s: inout AttributedString, ctx: RenderContext) {
        let weight: Font.Weight = ctx.isBold ? .semibold : .regular
        let design: Font.Design = .default

        var size = ctx.baseFontSize
        if let level = ctx.headingLevel {
            // Simple heading scaling
            size = ctx.baseFontSize + CGFloat(max(0, 6 - level)) * 2.0
        }

        var font = SwiftUI.Font.system(size: size, weight: weight, design: design)
        if ctx.isItalic { font = font.italic() }
        s.font = font
        if ctx.isQuote {
            s.foregroundColor = .secondary
        }
    }
}

// MARK: - RenderContext

private struct RenderContext {
    let baseFontSize: CGFloat
    var isBold: Bool = false
    var isItalic: Bool = false
    var isQuote: Bool = false
    var headingLevel: Int? = nil
}

// MARK: - MarkdownRenderedText (SwiftUI)

struct MarkdownRenderedText: View {
    let markdown: String

    @AppStorage("chatFontSize") private var chatFontSize: Double = 14

    var body: some View {
        Text(MarkdownRenderer.shared.render(markdown, baseFontSize: CGFloat(chatFontSize)))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}


