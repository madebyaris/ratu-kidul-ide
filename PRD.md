# Product Requirements Document (PRD)

## Ratu Kidul IDE — Native macOS AI IDE

**Version:** 1.0  
**Date:** December 16, 2025  
**Status:** Draft  
**Author:** Development Team

---

## 1. Executive Summary

Ratu Kidul IDE is a native macOS AI-powered development environment that enables developers to bring their own API tokens and interact with multiple AI models simultaneously. Built with SwiftUI for optimal native performance, it provides a beautiful, modern interface inspired by the Chorus design language.

The name "Ratu Kidul" references the legendary Queen of the Southern Sea in Javanese mythology — a powerful, mystical figure symbolizing depth, intelligence, and command over vast resources. Similarly, this IDE commands multiple AI models to serve the developer.

---

## 2. Vision & Goals

### 2.1 Vision Statement
Create the most performant, native macOS AI IDE that empowers developers with:
- **True native performance** via SwiftUI/AppKit
- **Complete token sovereignty** — users own their API keys
- **Git-optional workflow** — works with or without version control
- **Multi-model intelligence** — query multiple AIs simultaneously

### 2.2 Primary Goals

| Goal | Description | Success Metric |
|------|-------------|----------------|
| **Native Performance** | Cold start < 500ms, 60fps animations | Benchmarks vs Electron apps |
| **BYOK First** | 100% user-owned API keys | No backend token proxy |
| **Git Optional** | Full functionality without git | Feature parity for non-git users |
| **Multi-Model Chat** | Simultaneous responses from 2+ models | User can compare AI outputs |
| **Beautiful UX** | Chorus-inspired design aesthetic | User satisfaction surveys |

### 2.3 Non-Goals (v1.0)
- Cross-platform support (Windows/Linux) — macOS only
- Backend/cloud services — fully local-first
- Collaborative editing — single-user focus
- Plugin marketplace — built-in tools only

---

## 3. User Personas

### 3.1 Indie Developer — "Aris"
- **Background:** Solo developer, builds side projects
- **Pain Points:** Paying for multiple AI subscriptions, slow Electron apps
- **Goals:** Use existing API keys, fast IDE, minimal setup
- **Git Usage:** Sometimes uses git, sometimes just hacks

### 3.2 Enterprise Engineer — "Sarah"
- **Background:** Works at a company with security policies
- **Pain Points:** Cannot use cloud AI tools due to data policies
- **Goals:** Local-first AI with company-approved API keys
- **Git Usage:** Always uses git, strict workflow

### 3.3 AI Explorer — "Marco"
- **Background:** Evaluates and compares AI models
- **Pain Points:** Switching between different AI chat interfaces
- **Goals:** Query multiple models simultaneously, compare outputs
- **Git Usage:** Varies by project

---

## 4. Core Features

### 4.1 Multi-Model Chat System

**Description:** Send a single prompt and receive responses from multiple AI models simultaneously.

**Requirements:**
| ID | Requirement | Priority |
|----|-------------|----------|
| MC-1 | Support at least 8 AI providers (OpenAI, Anthropic, Google, etc.) | P0 |
| MC-2 | Streaming responses with real-time token display | P0 |
| MC-3 | Model comparison view (side-by-side) | P0 |
| MC-4 | Single response view with AI reviews | P0 |
| MC-5 | Automatic context management (token limits) | P1 |
| MC-6 | Conversation branching and threading | P1 |

**Supported Providers:**
1. **Anthropic** — Claude 3.5/4 family
2. **OpenAI** — GPT-4, o1, o3 family
3. **Google** — Gemini Pro/Ultra
4. **xAI** — Grok
5. **OpenRouter** — 100+ models
6. **Perplexity** — Search-enhanced models
7. **Ollama** — Local models
8. **LM Studio** — Local models

### 4.2 Bring Your Own Key (BYOK)

**Description:** Users provide their own API keys for all providers. No backend proxy, no token resale.

**Requirements:**
| ID | Requirement | Priority |
|----|-------------|----------|
| BK-1 | Secure keychain storage for API keys | P0 |
| BK-2 | Per-provider API key configuration | P0 |
| BK-3 | API key validation and health checks | P1 |
| BK-4 | Usage tracking per provider (local only) | P2 |
| BK-5 | Key rotation reminders | P3 |

### 4.3 Quick Chat (Ambient Chat)

**Description:** System-wide floating chat panel activated via global hotkey.

**Requirements:**
| ID | Requirement | Priority |
|----|-------------|----------|
| QC-1 | Global hotkey activation (default: ⌥Space) | P0 |
| QC-2 | Floating panel with blur/vibrancy | P0 |
| QC-3 | Quick model switching | P0 |
| QC-4 | Convert to full chat | P1 |
| QC-5 | Screenshot capture and attachment | P1 |

### 4.4 Projects & Organization

**Description:** Organize chats into projects with optional git integration.

**Requirements:**
| ID | Requirement | Priority |
|----|-------------|----------|
| PJ-1 | Create/manage projects | P0 |
| PJ-2 | Project-level context (system prompt, files) | P0 |
| PJ-3 | Chat categorization within projects | P0 |
| PJ-4 | Git-optional: works without repository | P0 |
| PJ-5 | Git-aware: detect repo, show branch info | P1 |
| PJ-6 | Project templates | P2 |

### 4.5 Tool Connections (MCP)

**Description:** Model Context Protocol (MCP) support for tool integrations.

**Built-in Toolsets:**
| Toolset | Description | Git Required |
|---------|-------------|--------------|
| **Files** | Read/write local files | No |
| **Terminal** | Execute shell commands | No |
| **Web** | Search and fetch web content | No |
| **GitHub** | Issues, PRs, code search | Yes (token) |
| **Coder** | Code generation, refactoring | No |
| **Images** | Image generation/manipulation | No |
| **Slack** | Channel/message integration | No (token) |
| **Messages** | iMessage integration | No |
| **Mac** | macOS system controls | No |

**Requirements:**
| ID | Requirement | Priority |
|----|-------------|----------|
| TC-1 | Built-in MCP toolsets | P0 |
| TC-2 | Custom MCP server support | P0 |
| TC-3 | Tool permission management | P0 |
| TC-4 | Tool execution logging | P1 |
| TC-5 | Per-chat tool configuration | P2 |

### 4.6 Attachments System

**Description:** Attach files, images, PDFs, and web pages to conversations.

**Supported Types:**
| Type | Extensions | Models Supporting |
|------|------------|-------------------|
| Images | png, jpg, jpeg, gif, webp | Claude, GPT-4V, Gemini |
| PDFs | pdf | Claude, GPT-4V |
| Text | txt, md, code files (50+ extensions) | All models |
| Webpages | URLs | All models (converted to text) |

**Requirements:**
| ID | Requirement | Priority |
|----|-------------|----------|
| AT-1 | Drag-and-drop file attachment | P0 |
| AT-2 | Image attachment with preview | P0 |
| AT-3 | PDF parsing and extraction | P1 |
| AT-4 | URL fetch and content extraction | P1 |
| AT-5 | Clipboard image paste | P1 |
| AT-6 | Screenshot capture attachment | P1 |

---

## 5. Git-Optional Philosophy

A core differentiator: **Ratu Kidul IDE works fully without git**.

### 5.1 Non-Git Mode
- All features work without a git repository
- No git commands or operations
- Projects are simply organizational containers
- Files are referenced by absolute path

### 5.2 Git-Aware Mode (Optional)
When a project folder is a git repository:
- Show current branch in UI
- Display git status indicators
- GitHub toolset becomes available
- Optional: commit message suggestions

### 5.3 Comparison

| Feature | Without Git | With Git |
|---------|-------------|----------|
| Multi-model chat | ✅ | ✅ |
| BYOK | ✅ | ✅ |
| Quick Chat | ✅ | ✅ |
| Projects | ✅ | ✅ |
| File tools | ✅ | ✅ |
| Terminal tools | ✅ | ✅ |
| GitHub integration | ❌ | ✅ |
| Branch display | ❌ | ✅ |

---

## 6. User Interface

### 6.1 Design Principles
- **Native Feel:** Use SF Symbols, native controls, system colors
- **Dark/Light:** Full support for both modes + system preference
- **Vibrancy:** macOS blur effects where appropriate
- **Typography:** SF Pro for UI, SF Mono for code
- **Animations:** Smooth, purposeful, 60fps

### 6.2 Main Layouts

#### Sidebar (Left)
- Project list with collapse/expand
- Chat list per project
- Pinned chats section
- Search across all chats

#### Main Content (Center)
- Chat view with message bubbles
- Model indicators per message
- Streaming animation
- Code blocks with syntax highlighting

#### Input Area (Bottom)
- Multi-line text input
- Attachment pills
- Model selector pills
- Tool indicator badges

#### Settings (Sheet/Window)
- API Keys management
- Model configuration
- Tool permissions
- Appearance settings
- Keyboard shortcuts

### 6.3 Quick Chat Panel
- Floating NSPanel
- Vibrancy background
- Compact single-column layout
- Model selector dropdown
- "Open in Main Window" action

---

## 7. Data Model

### 7.1 Core Entities

```
┌─────────────┐     ┌─────────────┐
│   Project   │────<│    Chat     │
└─────────────┘     └─────────────┘
                          │
                          │
                    ┌─────▼─────┐
                    │ MessageSet │
                    └─────┬─────┘
                          │
                    ┌─────▼─────┐
                    │  Message   │
                    └─────┬─────┘
                          │
              ┌───────────┼───────────┐
              ▼           ▼           ▼
        ┌──────────┐ ┌──────────┐ ┌──────────┐
        │Attachment│ │ToolCall  │ │ToolResult│
        └──────────┘ └──────────┘ └──────────┘
```

### 7.2 Key Tables
- `projects` — Organizational containers
- `chats` — Conversation threads
- `messages` — Individual AI responses
- `message_sets` — Groups of parallel responses
- `attachments` — Files attached to messages
- `models` — Available AI models
- `model_configs` — User model configurations
- `toolsets_config` — Tool settings
- `tool_permissions` — Per-tool permissions

---

## 8. Success Metrics

### 8.1 Performance Metrics
| Metric | Target | Measurement |
|--------|--------|-------------|
| Cold start time | < 500ms | App launch to interactive |
| Chat message render | < 16ms | First token to display |
| Memory usage | < 200MB | Typical usage |
| Animation frame rate | 60fps | Core Animations |

### 8.2 User Metrics
| Metric | Target | Measurement |
|--------|--------|-------------|
| Daily active usage | — | Local analytics (opt-in) |
| Chats per session | > 5 | Database queries |
| Models used per chat | > 1.5 avg | Validate multi-model value |

---

## 9. Risks & Mitigations

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| SwiftUI limitations for complex UIs | Medium | High | Hybrid SwiftUI + AppKit |
| API provider changes break integration | Medium | Medium | Provider abstraction layer |
| MCP protocol evolution | Low | Medium | Version negotiation |
| Large file attachment performance | Medium | Low | Streaming, chunking |

---

## 10. Timeline (Proposed)

### Phase 1: Foundation (Weeks 1-4)
- Swift project setup
- Core data model (SwiftData)
- Basic UI shell
- Single provider integration (OpenAI)

### Phase 2: Multi-Model (Weeks 5-8)
- All 8 providers
- Streaming implementation
- Model configuration UI
- BYOK key management

### Phase 3: Tools & MCP (Weeks 9-12)
- MCP client in Swift
- Built-in toolsets
- Tool permission system
- Custom toolset support

### Phase 4: Polish (Weeks 13-16)
- Quick Chat panel
- Attachments system
- Git-aware features
- Performance optimization
- Beta testing

---

## 11. Open Questions

1. **Data Migration:** How to migrate existing Chorus SQLite data?
2. **Keychain Strategy:** Shared keychain or app-specific?
3. **MCP Binary Distribution:** Bundle vs download on demand?
4. **Update Mechanism:** Sparkle vs App Store?

---

## 12. Appendix

### A. Competitor Analysis

| App | Native | BYOK | Multi-Model | Git-Optional |
|-----|--------|------|-------------|--------------|
| Cursor | ❌ (Electron) | ❌ | ❌ | ❌ |
| Chorus (current) | ⚠️ (Tauri) | ✅ | ✅ | ✅ |
| ChatGPT Desktop | ⚠️ (Electron) | ❌ | ❌ | N/A |
| Claude Desktop | ⚠️ (Electron) | ❌ | ❌ | N/A |
| **Ratu Kidul IDE** | ✅ (SwiftUI) | ✅ | ✅ | ✅ |

### B. Glossary

- **BYOK:** Bring Your Own Key
- **MCP:** Model Context Protocol
- **LLM:** Large Language Model
- **Toolset:** Collection of tools for a specific domain
- **Quick Chat:** System-wide floating chat panel

