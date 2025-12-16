#!/bin/bash

# Setup script for Ratu Kidul IDE
# This script helps set up the Xcode project

echo "Setting up Ratu Kidul IDE..."

# Check if Xcode is installed
if ! command -v xcodebuild &> /dev/null; then
    echo "Error: Xcode is not installed. Please install Xcode from the App Store."
    exit 1
fi

# Create Xcode project from Package.swift
echo "Generating Xcode project..."
swift package generate-xcodeproj 2>/dev/null || {
    echo "Note: generate-xcodeproj is deprecated. Creating project manually..."
    echo "Please open Package.swift in Xcode:"
    echo "  open Package.swift"
    echo ""
    echo "Or create a new Xcode project and add the source files."
}

echo "Setup complete!"
echo ""
echo "To build and run:"
echo "  1. Open Package.swift in Xcode"
echo "  2. Select the RatuKidulIDE scheme"
echo "  3. Build and run (⌘R)"

