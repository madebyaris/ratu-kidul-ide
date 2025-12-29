# MiniMax API Endpoints Comparison

## Overview

MiniMax provides two API compatibility layers:
1. **Anthropic-Compatible API** (`https://api.minimax.io/anthropic`) - **Currently Used**
2. **OpenAI-Compatible API** (`https://api.minimax.io/v1`) - Alternative option

## Detailed Comparison

### 1. Base URLs & Endpoints

| Aspect | Anthropic-Compatible | OpenAI-Compatible |
|--------|---------------------|-------------------|
| **Base URL** | `https://api.minimax.io/anthropic` | `https://api.minimax.io/v1` |
| **Full Endpoint** | `/v1/messages` | `/chat/completions` |
| **Full URL** | `https://api.minimax.io/anthropic/v1/messages` | `https://api.minimax.io/v1/chat/completions` |

### 2. Authentication

| Aspect | Anthropic-Compatible | OpenAI-Compatible |
|--------|---------------------|-------------------|
| **Header Name** | `x-api-key` | `Authorization` |
| **Header Format** | `x-api-key: <API_KEY>` | `Authorization: Bearer <API_KEY>` |
| **Version Header** | `anthropic-version: 2023-06-01` | Not required |

### 3. Request Format

#### Anthropic-Compatible API
```json
{
  "model": "MiniMax-M2",
  "messages": [
    {
      "role": "user",
      "content": [
        {
          "type": "text",
          "text": "Hello!"
        }
      ]
    }
  ],
  "max_tokens": 4096,
  "stream": true,
  "system": "You are a helpful assistant.",
  "tools": [...]
}
```

**Key Features:**
- `content` is an **array** of content blocks
- Supports `type: "text"`, `type: "tool_use"`, `type: "tool_result"`, `type: "thinking"`
- Native support for thinking/reasoning content

#### OpenAI-Compatible API
```json
{
  "model": "MiniMax-M2",
  "messages": [
    {
      "role": "system",
      "content": "You are a helpful assistant."
    },
    {
      "role": "user",
      "content": "Hello!"
    }
  ],
  "max_tokens": 4096,
  "stream": true,
  "tools": [...],
  "extra_body": {
    "reasoning_split": true  // Separate thinking content
  }
}
```

**Key Features:**
- `content` is a **string** (standard OpenAI format)
- Uses `reasoning_details` field for thinking content (when `reasoning_split=True`)
- Standard OpenAI message format

### 4. Response Format

#### Anthropic-Compatible Streaming
```
data: {"type": "content_block_start", "index": 0, "content_block": {"type": "text"}}
data: {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "Hello"}}
data: {"type": "content_block_delta", "index": 0, "delta": {"type": "thinking_delta", "thinking": "..."}}
data: {"type": "content_block_stop", "index": 0}
data: {"type": "message_stop"}
```

#### OpenAI-Compatible Streaming
```
data: {"id": "...", "object": "chat.completion.chunk", "choices": [{"delta": {"content": "Hello"}}]}
data: {"id": "...", "object": "chat.completion.chunk", "choices": [{"delta": {"reasoning_details": [...]}}]}
data: {"id": "...", "object": "chat.completion.chunk", "choices": [{"delta": {}, "finish_reason": "stop"}]}
data: [DONE]
```

### 5. Tool Calling Support

| Feature | Anthropic-Compatible | OpenAI-Compatible |
|--------|---------------------|-------------------|
| **Tool Format** | Native `tool_use` blocks in content array | Standard OpenAI `function_call` / `tool_calls` |
| **Tool Results** | `type: "tool_result"` in content array | Standard OpenAI format |
| **Streaming Tool Args** | `input_json_delta` with `partial_json` | Standard OpenAI streaming |

### 6. Supported Models

Both APIs support:
- `MiniMax-M2`
- `MiniMax-M2-Stable`

### 7. Supported Content Types

| Content Type | Anthropic-Compatible | OpenAI-Compatible |
|-------------|---------------------|-------------------|
| `text` | ✅ Native | ✅ Standard |
| `tool_use` | ✅ Native | ✅ Standard |
| `tool_result` | ✅ Native | ✅ Standard |
| `thinking` | ✅ Native | ✅ Via `reasoning_details` |
| `image` | ❌ Not supported | ❌ Not supported |
| `document` | ❌ Not supported | ❌ Not supported |

### 8. Parameter Support

#### Anthropic-Compatible
- ✅ `model`, `messages`, `max_tokens`, `stream`, `system`, `temperature`, `top_p`, `tools`, `tool_choice`, `metadata`
- ❌ `top_k`, `stop_sequences`, `service_tier`, `mcp_servers`, `context_management`, `container` (ignored)

#### OpenAI-Compatible
- ✅ `model`, `messages`, `max_tokens`, `stream`, `temperature`, `top_p`, `tools`, `tool_choice`
- ✅ `extra_body.reasoning_split` (MiniMax-specific)
- ❌ `presence_penalty`, `frequency_penalty`, `logit_bias` (ignored)
- ❌ `n` (only supports 1)
- ❌ `function_call` (deprecated, use `tools`)

### 9. Current Implementation Status

**Current Setup:**
- ✅ **MiniMaxProvider** uses Anthropic-Compatible API (`https://api.minimax.io/anthropic/v1/messages`)
- ✅ Properly handles content blocks, tool calling, and streaming
- ✅ Supports tool results in multi-turn conversations

**Alternative Option:**
- Could use OpenAI-Compatible API via `OpenAIProvider` with custom URL `https://api.minimax.io/v1`
- Would require different message format conversion
- Would need to handle `reasoning_details` separately

## Recommendations

### Why Anthropic-Compatible is Better for This Project:

1. **Native Tool Calling**: Better support for tool_use blocks with streaming arguments
2. **Thinking Content**: Native support for reasoning/thinking content
3. **Content Blocks**: More flexible message structure
4. **Already Implemented**: Current implementation is working with this format
5. **MiniMax Recommendation**: MiniMax officially recommends Anthropic-compatible API

### When to Consider OpenAI-Compatible:

1. If you need to integrate with existing OpenAI SDK code
2. If you prefer OpenAI's message format (simpler string content)
3. If you need `reasoning_split` feature for separate thinking content

## Testing Both Endpoints

To test the OpenAI-compatible endpoint, you could:

1. Add a new model config with `openai-compatible/MiniMax-M2`
2. Set custom base URL to `https://api.minimax.io/v1`
3. Use `OpenAIProvider` which already supports custom URLs

However, the current Anthropic-compatible implementation is more robust for tool calling and is the recommended approach by MiniMax.

