#!/bin/bash
set -e

echo ">>> Managing Release..."

# 1. Git Configuration
git config --global --add safe.directory '*'

# 2. Define Variables
REPO="$GITHUB_REPOSITORY"   # Automatically provided by Actions
SHA="$GITHUB_SHA"           # Automatically provided by Actions

# 3. Check & Delete Previous Release
if gh release view daily-build --repo "$REPO" > /dev/null 2>&1; then
    echo "-> Deleting existing 'daily-build' release..."
    gh release delete daily-build --yes --cleanup-tag --repo "$REPO"
else
    echo "-> No existing release found. Creating a new one."
fi

# 4. Log ISO Size
if [ -d "out" ]; then
    cd out
    ISO_FILE=$(ls *.iso | head -n 1)
    if [ -f "$ISO_FILE" ]; then
        FILE_SIZE=$(stat -c%s "$ISO_FILE")
        echo "   Final ISO Size: $(($FILE_SIZE / 1024 / 1024)) MB"
    fi
    cd ..
else
    echo "::error::Output directory 'out' not found! Build might have failed."
    exit 1
fi

# 5. Create Release & Upload
echo "-> Creating release and uploading artifacts..."

# Note: Adjust the --notes content as needed
gh release create daily-build ./out/*.iso ./out_hash/package.hash \
    --repo "$REPO" \
    --title "Arch Plasma Diet Build" \
    --notes "Optimized ~1GB Build. Minimal Plasma + Split Firmware + No KMS in initramfs." \
    --latest \
    --target "$SHA"

echo ">>> Release process completed successfully."