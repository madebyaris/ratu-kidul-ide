#!/usr/bin/env python3
"""
Script to add LSP files to the Xcode project.
"""

import os
import uuid
import re

def generate_uuid():
    """Generate a 24-character UUID for Xcode."""
    return uuid.uuid4().hex[:24].upper()

def read_file(path):
    with open(path, 'r', encoding='utf-8') as f:
        return f.read()

def write_file(path, content):
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)

# Define LSP files to add
lsp_files = [
    ("DocumentVersionManager.swift", "DocumentVersionManager.swift"),
    ("JSONRPCTransport.swift", "JSONRPCTransport.swift"),
    ("LanguageServerConfig.swift", "LanguageServerConfig.swift"),
    ("LSPCache.swift", "LSPCache.swift"),
    ("LSPDebouncer.swift", "LSPDebouncer.swift"),
    ("LSPError.swift", "LSPError.swift"),
    ("LSPLogger.swift", "LSPLogger.swift"),
    ("LSPManager.swift", "LSPManager.swift"),
    ("LSPServerPool.swift", "LSPServerPool.swift"),
    ("LSPSession.swift", "LSPSession.swift"),
    ("LSPTypes.swift", "LSPTypes.swift"),
]

# Editor integration files
editor_files = [
    ("EditorViewModel.swift", "EditorViewModel.swift"),
    ("CompletionPopupView.swift", "CompletionPopupView.swift"),
    ("DiagnosticsGutterView.swift", "DiagnosticsGutterView.swift"),
    ("HoverPopoverView.swift", "HoverPopoverView.swift"),
]

project_path = "RatuKidulIDE.xcodeproj/project.pbxproj"

# Read the project file
content = read_file(project_path)

# Generate UUIDs for new files
new_file_refs = {}
new_build_files = {}

for filename, _ in lsp_files + editor_files:
    new_file_refs[filename] = generate_uuid()
    new_build_files[filename] = generate_uuid()

# Find positions to insert

# 1. Add PBXFileReference entries (after the last one before "/* End PBXFileReference section */")
file_ref_pattern = r'(/\* End PBXFileReference section \*/)'
file_ref_match = re.search(file_ref_pattern, content)

if file_ref_match:
    file_refs_to_add = ""
    for filename, _ in lsp_files:
        file_refs_to_add += f'\t\t{new_file_refs[filename]} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = "<group>"; }};\n'
    for filename, _ in editor_files:
        file_refs_to_add += f'\t\t{new_file_refs[filename]} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = "<group>"; }};\n'
    
    content = content[:file_ref_match.start()] + file_refs_to_add + content[file_ref_match.start():]

# 2. Add PBXBuildFile entries (after the last one before "/* End PBXBuildFile section */")
build_file_pattern = r'(/\* End PBXBuildFile section \*/)'
build_file_match = re.search(build_file_pattern, content)

if build_file_match:
    build_files_to_add = ""
    for filename, _ in lsp_files + editor_files:
        build_files_to_add += f'\t\t{new_build_files[filename]} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {new_file_refs[filename]} /* {filename} */; }};\n'
    
    content = content[:build_file_match.start()] + build_files_to_add + content[build_file_match.start():]

# 3. Find the Core group and add LSP group
# Find the Core group pattern
core_group_pattern = r'(27227F0FD6A5149D4BE7CAE7 /\* Core \*/ = \{\s*isa = PBXGroup;\s*children = \()'
core_group_match = re.search(core_group_pattern, content)

# Generate UUID for LSP group
lsp_group_uuid = generate_uuid()

if core_group_match:
    # Add reference to LSP group in Core group
    insert_pos = core_group_match.end()
    content = content[:insert_pos] + f'\n\t\t\t\t{lsp_group_uuid} /* LSP */,' + content[insert_pos:]

# 4. Add LSP group definition
# Find position to add new group (before "/* End PBXGroup section */")
group_end_pattern = r'(/\* End PBXGroup section \*/)'
group_end_match = re.search(group_end_pattern, content)

if group_end_match:
    lsp_group = f'\t\t{lsp_group_uuid} /* LSP */ = {{\n'
    lsp_group += '\t\t\tisa = PBXGroup;\n'
    lsp_group += '\t\t\tchildren = (\n'
    for filename, _ in lsp_files:
        lsp_group += f'\t\t\t\t{new_file_refs[filename]} /* {filename} */,\n'
    lsp_group += '\t\t\t);\n'
    lsp_group += '\t\t\tpath = LSP;\n'
    lsp_group += '\t\t\tsourceTree = "<group>";\n'
    lsp_group += '\t\t};\n'
    
    content = content[:group_end_match.start()] + lsp_group + content[group_end_match.start():]

# 5. Add editor view files to the Views group (Editor/Views)
# Find the Editor Views group (contains CodeEditorView.swift, etc)
# First, let's find the Views group under Editor that contains CodeEditorView.swift

# Look for the group containing CodeEditorView.swift
views_pattern = r'([A-F0-9]{24}) /\* Views \*/ = \{\s*isa = PBXGroup;\s*children = \('
views_matches = list(re.finditer(views_pattern, content))

# We need to find the Editor Views group, let's search more specifically
editor_views_files = ["EditorContentView.swift", "CodeEditorView.swift", "TabBarView.swift"]
for match in views_matches:
    group_start = match.start()
    group_end = content.find(');', group_start)
    group_content = content[group_start:group_end]
    # Check if this is the Editor Views group (contains CodeEditorView.swift reference)
    if "CodeEditorView.swift" in group_content or "24BD76EBF4769E00E6925E4B" in group_content:
        # Found the Editor Views group, add new files here
        insert_pos = match.end()
        files_to_add = ""
        for filename, _ in editor_files:
            files_to_add += f'\n\t\t\t\t{new_file_refs[filename]} /* {filename} */,'
        content = content[:insert_pos] + files_to_add + content[insert_pos:]
        break

# 6. Add to Sources build phase
# Find the sources build phase for the main target
sources_pattern = r'(files = \(\s*(?:[^)]+,\s*)*)(02181615CA1D2290DC0F8FE9)'
sources_match = re.search(sources_pattern, content)

if sources_match:
    sources_to_add = ""
    for filename, _ in lsp_files + editor_files:
        sources_to_add += f'{new_build_files[filename]} /* {filename} in Sources */,\n\t\t\t\t'
    
    content = content[:sources_match.start(1)] + content[sources_match.start(1):sources_match.end(1)] + sources_to_add + content[sources_match.end(1):]

# Write the updated project file
write_file(project_path, content)

print("✅ Added LSP files to project:")
for filename, _ in lsp_files:
    print(f"  - Core/LSP/{filename}")
for filename, _ in editor_files:
    print(f"  - Features/Editor/{filename}")
print("\nPlease rebuild the project.")
