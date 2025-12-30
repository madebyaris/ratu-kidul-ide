# LSP Debugging Guide - SourceKit-LSP Integration

## Current Status

✅ **All fixes have been applied** to resolve the LSP initialization errors.  
🔍 **Debug logging has been added** to help diagnose any remaining issues.

## What Was Fixed

### 1. AnyCodable Encoding (Critical Fix)
- **Problem**: Nested `AnyCodable` values couldn't be encoded
- **Solution**: Enhanced `AnyCodable.encode()` to unwrap nested values and handle all types
- **File**: `RatuKidulIDE/Core/Providers/AIProvider.swift`

### 2. LSP Initialization Parameters
- **Problem**: Double-wrapped `AnyCodable` structures
- **Solution**: Build params as plain dictionaries, wrap once at transport
- **File**: `RatuKidulIDE/Core/LSP/LSPSession.swift`

### 3. FileHandle Write API
- **Problem**: `write(contentsOf:)` fails with pipes on some macOS versions
- **Solution**: Use the older, more reliable `write(_:)` method
- **File**: `RatuKidulIDE/Core/LSP/JSONRPCTransport.swift`

### 4. Debug Logging
- **Added**: Detailed logging for JSON encoding and transmission
- **Purpose**: See exactly what's being sent to sourcekit-lsp
- **Output**: Console shows JSON preview and success/error messages

## How to Test

### 1. Run from Xcode
```bash
# Build and run
⌘R in Xcode
```

### 2. Watch the Console
You should see these messages:

**✅ Success Pattern:**
```
✅ Found sourcekit-lsp at: /Applications/Xcode.app/.../sourcekit-lsp
Server [swift]: Starting
Server [swift]: Process launched (PID: xxxxx)
📤 Sending JSON-RPC: {"jsonrpc":"2.0","id":1,"method":"initialize",...}
✅ Successfully wrote XXXX bytes to stdin
Server [swift]: Initialized
```

**❌ Error Pattern (if still occurring):**
```
Server [swift]: Starting
Server [swift]: Process launched (PID: xxxxx)
❌ JSON Encoding Error: ...
   Invalid value: ...
   Context: ...
   Coding path: ...
Server [swift]: Initialization failed
```

### 3. Open a Swift File
1. Open any `.swift` file in your project
2. Check console for:
   ```
   📤 Sending JSON-RPC: {"jsonrpc":"2.0","method":"textDocument/didOpen",...}
   ✅ Successfully wrote XXXX bytes to stdin
   ```

## Interpreting Debug Output

### JSON Encoding Error
If you see:
```
❌ JSON Encoding Error: invalidValue(...)
   Invalid value: <some value>
   Coding path: params -> clientInfo -> name
```

This means:
- **What**: A value at the specified path couldn't be encoded
- **Where**: The coding path shows the exact location in the JSON structure
- **Why**: The value type isn't supported by `AnyCodable`

**Action**: Check the value type and ensure it's one of: String, Int, Double, Bool, Array, Dictionary, or nil

### Write Error
If you see:
```
❌ Write Error: The data couldn't be written...
```

This means:
- **What**: The pipe write operation failed
- **Why**: Process may have crashed or pipe is broken
- **Check**: Look for stderr output from sourcekit-lsp above this error

### Success Messages
If you see:
```
📤 Sending JSON-RPC: {"jsonrpc":"2.0",...}
✅ Successfully wrote 1234 bytes to stdin
```

This means:
- **Encoding worked**: JSON was successfully created
- **Write worked**: Data was written to the pipe
- **Next**: Wait for response from sourcekit-lsp

## Common Issues and Solutions

### Issue 1: "AnyCodable value cannot be encoded"

**Symptoms:**
- Error during JSON encoding
- Coding path shows nested structure

**Solution:**
- Check for nested `AnyCodable(AnyCodable(...))` wrapping
- Build dictionaries as `[String: Any]` first
- Wrap in `AnyCodable` only at the final transport call

**Example Fix:**
```swift
// ❌ Bad: Nested AnyCodable
let params: [String: AnyCodable] = [
    "info": AnyCodable([
        "name": AnyCodable("My App")  // Double-wrapped!
    ])
]

// ✅ Good: Plain dictionary
let info: [String: Any] = [
    "name": "My App"
]
let params: [String: Any] = [
    "info": info
]
// Wrap once at transport
transport.send(params: AnyCodable(params))
```

### Issue 2: "The data couldn't be written..."

**Symptoms:**
- Write succeeds but error still occurs
- Process launches but crashes immediately

**Possible Causes:**
1. **sourcekit-lsp crashed**: Check stderr output
2. **Invalid JSON sent**: Check the JSON preview in console
3. **Pipe broken**: Process terminated before write completed

**Solution:**
1. Check stderr logs for sourcekit-lsp crash info
2. Verify JSON structure matches LSP specification
3. Ensure process is still running when writing

### Issue 3: Process Launches but No Response

**Symptoms:**
- Process starts (PID shown)
- JSON sent successfully
- No response from server

**Possible Causes:**
1. sourcekit-lsp waiting for more data
2. Invalid JSON-RPC format
3. Missing Content-Length header

**Solution:**
1. Check JSON preview - ensure it's valid JSON
2. Verify Content-Length matches actual JSON byte count
3. Ensure header ends with `\r\n\r\n`

## LSP Protocol Requirements

### JSON-RPC Message Format

**Request:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": { ... }
}
```

**Notification (no response expected):**
```json
{
  "jsonrpc": "2.0",
  "method": "initialized",
  "params": null
}
```

### Transport Format

```
Content-Length: 123\r\n
\r\n
{"jsonrpc":"2.0",...}
```

**Requirements:**
- Header must be `Content-Length: <bytes>\r\n\r\n`
- Byte count must match JSON data exactly
- No extra whitespace or newlines
- Use UTF-8 encoding

## Next Steps

### If Still Failing

1. **Capture Full Console Output**:
   - Copy all console messages
   - Look for stderr output from sourcekit-lsp
   - Check for crash logs

2. **Test sourcekit-lsp Manually**:
   ```bash
   # Test if sourcekit-lsp works standalone
   /Applications/Xcode.app/.../sourcekit-lsp
   # Then type (with proper Content-Length):
   Content-Length: 50
   
   {"jsonrpc":"2.0","id":1,"method":"initialize"}
   ```

3. **Check System Logs**:
   ```bash
   # Check for crash logs
   log show --predicate 'process == "sourcekit-lsp"' --last 1h
   ```

### If Working

1. **Remove Debug Logging** (for production):
   - Comment out the `print()` statements in `JSONRPCTransport.swift`
   - Keep error logging for troubleshooting

2. **Test LSP Features**:
   - Code completion (type and wait for suggestions)
   - Hover (hover over symbols)
   - Diagnostics (introduce syntax errors)
   - Go to definition (Cmd+Click on symbols)

3. **Monitor Performance**:
   - Check CPU usage of sourcekit-lsp
   - Monitor memory consumption
   - Watch for response times

## Additional Resources

- **SourceKit-LSP GitHub**: https://github.com/swiftlang/sourcekit-lsp
- **LSP Specification**: https://microsoft.github.io/language-server-protocol/
- **JSON-RPC 2.0**: https://www.jsonrpc.org/specification

---

**Last Updated**: December 30, 2025  
**Status**: 🔍 Debug logging enabled, awaiting test results
