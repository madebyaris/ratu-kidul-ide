# MiniMax API Endpoints - Test Results

## Test Date
December 17, 2025

## Test Summary

Both APIs work correctly, but show significant differences in response format and structure.

---

## 1. Non-Streaming Response Comparison

### Anthropic-Compatible API Response
```json
{
    "id": "05912f99ee6e45cd2e673058992203dd",
    "type": "message",
    "role": "assistant",
    "model": "MiniMax-M2",
    "content": [
        {
            "thinking": "The user asks: \"Say hello in one sentence\"...",
            "signature": "41f983e4474f2b9d894aa739a45fd28c4304aa3a76f066fd66608c1928b011ab",
            "type": "thinking"
        }
    ],
    "usage": {
        "input_tokens": 46,
        "output_tokens": 100
    },
    "stop_reason": "max_tokens"
}
```

**Key Observations:**
- ✅ Thinking content is a **separate content block** with `type: "thinking"`
- ✅ Clean separation between thinking and text content
- ✅ Content is an **array** of blocks
- ⚠️ In this test, only thinking was returned (hit max_tokens)

### OpenAI-Compatible API Response
```json
{
    "id": "05912f9b26c8def35d3d15fd66510315",
    "choices": [{
        "message": {
            "content": "<think>\nThe user is asking for a simple greeting...\n</think>\n\nHello! Nice to meet you!",
            "role": "assistant"
        }
    }],
    "usage": {
        "total_tokens": 93,
        "completion_tokens_details": {
            "reasoning_tokens": 38
        }
    }
}
```

**Key Observations:**
- ✅ Thinking content is **embedded** in the content string as `<think>...</think>`
- ✅ Standard OpenAI format with `choices` array
- ✅ Includes both thinking AND actual response in one field
- ✅ Token usage shows `reasoning_tokens` separately

---

## 2. Streaming Response Comparison

### Anthropic-Compatible Streaming Events
```
event: message_start
data: {"type":"message_start","message":{"id":"...","role":"assistant","content":[]}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"..."}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}
```

**Key Observations:**
- ✅ Uses **SSE format** with `event:` and `data:` lines
- ✅ **Structured events**: `message_start`, `content_block_start`, `content_block_delta`, `content_block_stop`
- ✅ Each content block has an **index** for tracking
- ✅ Thinking content has dedicated `thinking_delta` events
- ✅ Clear separation between different content types

### OpenAI-Compatible Streaming Events
```
data: {"id":"...","choices":[{"delta":{"content":"<think>\nHmm,","role":"assistant"}}]}

data: {"id":"...","choices":[{"delta":{"content":" the user just asked...","role":"assistant"}}]}

data: {"id":"...","choices":[{"finish_reason":"length","delta":{"content":" clearly testing..."}}]}
```

**Key Observations:**
- ✅ Uses **SSE format** but simpler (just `data:` lines)
- ✅ Standard OpenAI streaming format
- ✅ Thinking content is **embedded** in the content string
- ✅ All content comes through `delta.content` field
- ✅ Simpler structure but less granular control

---

## 3. Key Differences Summary

| Aspect | Anthropic-Compatible | OpenAI-Compatible |
|--------|---------------------|-------------------|
| **Response Structure** | Content blocks array | Standard OpenAI format |
| **Thinking Content** | Separate `type: "thinking"` block | Embedded `<think>` tags |
| **Streaming Events** | Structured: `content_block_start/delta/stop` | Simple: `delta.content` |
| **Content Tracking** | Index-based per block | Single content stream |
| **Tool Calling** | Native `tool_use` blocks | Standard OpenAI `tool_calls` |
| **Parsing Complexity** | More complex (multiple event types) | Simpler (single delta format) |
| **Flexibility** | High (multiple content types) | Medium (string-based) |

---

## 4. Recommendations for Ratu Kidul IDE

### ✅ **Keep Using Anthropic-Compatible API** (`https://api.minimax.io/anthropic`)

**Reasons:**
1. **Better Tool Calling**: Native `tool_use` blocks with streaming `input_json_delta` - already implemented
2. **Cleaner Thinking Content**: Separate content blocks instead of parsing HTML-like tags
3. **More Granular Control**: Can track different content types separately
4. **Better for Multi-turn**: Native `tool_result` blocks work better for tool conversations
5. **Already Working**: Current implementation is functional and tested

### ⚠️ **Consider OpenAI-Compatible API Only If:**
- You need to integrate with existing OpenAI SDK code
- You prefer simpler string-based content handling
- You want to use `reasoning_split=True` to separate thinking content

---

## 5. Test Commands Used

### Anthropic-Compatible Test
```bash
curl -X POST "https://api.minimax.io/anthropic/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -d '{"model": "MiniMax-M2", "messages": [...], "max_tokens": 100, "stream": false}'
```

### OpenAI-Compatible Test
```bash
curl -X POST "https://api.minimax.io/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"model": "MiniMax-M2", "messages": [...], "max_tokens": 100, "stream": false}'
```

---

## Conclusion

Both APIs work correctly, but the **Anthropic-Compatible API** is better suited for this IDE project because:
- ✅ Better tool calling support (already implemented)
- ✅ Cleaner content structure
- ✅ More flexible for complex interactions
- ✅ Recommended by MiniMax for agentic use cases

The current implementation choice is correct! 🎯
