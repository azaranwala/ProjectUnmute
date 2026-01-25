#!/bin/sh

# Xcode Cloud post-clone script
# Installs CocoaPods dependencies

echo "Installing CocoaPods..."

# Install CocoaPods if not available
if ! command -v pod &> /dev/null; then
    echo "CocoaPods not found, installing..."
    brew install cocoapods
fi

# Navigate to repository root and install pods
cd "$CI_PRIMARY_REPOSITORY_PATH"
pod install

echo "CocoaPods installation complete!"
