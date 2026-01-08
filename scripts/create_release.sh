#!/bin/bash
set -e

echo ">>> Managing Release..."

# Define Variables
REPO="$GITHUB_REPOSITORY"   # Automatically provided by Actions
SHA="$GITHUB_SHA"           # Automatically provided by Actions

# Check & Delete Previous Release
if gh release view "$RELEASE_TAG" --repo "$REPO" > /dev/null 2>&1; then
    echo "-> Deleting existing '$RELEASE_TAG' release..."
    gh release delete "$RELEASE_TAG" --yes --cleanup-tag --repo "$REPO"
else
    echo "-> No existing release found. Creating a new one."
fi

# Log ISO Size
if [ -d "$OUT_DIR" ]; then
    cd "$OUT_DIR"
    ISO_FILE=$(ls *.iso | head -n 1)
    if [ -f "$ISO_FILE" ]; then
        FILE_SIZE=$(stat -c%s "$ISO_FILE")
        echo "   Final ISO Size: $(($FILE_SIZE / 1024 / 1024)) MB"
    fi
    cd ..
else
    echo "::error::Output directory '$OUT_DIR' not found! Build might have failed."
    exit 1
fi

# Create Release & Upload
echo "-> Creating release and uploading artifacts..."

# Note: Adjust the --notes content as needed
gh release create "$RELEASE_TAG" "$OUT_DIR"/*.iso \
    --repo "$REPO" \
    --title "Arch Plasma Build" \
    --notes "Arch Linux Plasma ISO" \
    --latest \
    --target "$SHA"

echo ">>> Release process completed successfully."
