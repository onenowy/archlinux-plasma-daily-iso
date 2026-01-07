#!/bin/bash
set -e

echo ">>> Checking for Package Updates..."

# 1. Setup Environment
# [NOTE] Dependencies (git, sed, github-cli) are now installed via build.yml.
# We do not install them here to avoid redundancy.

# 2. Check Package List File
if [ ! -f "package_list.x86_64" ]; then
    echo "::error::package_list.x86_64 not found!"
    exit 1
fi

# 3. Generate Current Hash
echo "-> Generating hash from package_list.x86_64..."
# Clean the list (remove comments/empty lines)
sed 's/#.*//;s/[ \t]*$//;/^$/d' package_list.x86_64 > clean_list.txt

# Resolve URLs -> filenames -> hash (Mirror independent)
# This detects if UPSTREAM packages have updated.
pacman -Sp --noconfirm - < clean_list.txt | sed 's|.*/||' | sort | sha256sum | awk '{print $1}' > current.hash

echo "   Current Hash: $(cat current.hash)"

# 4. Download Previous Hash
echo "-> Downloading previous hash..."
# Downloads 'package.hash' from the 'iso-build' release
gh release download iso-build -p package.hash -R "$GITHUB_REPOSITORY" -O old.hash || touch old.hash

echo "   Old Hash:     $(cat old.hash)"

# 5. Compare & Output
# Prepare artifact folder
mkdir -p hash_artifact
cp current.hash hash_artifact/package.hash

if cmp -s current.hash old.hash; then
    echo "::notice::No updates found."
    echo "should_build=false" >> "$GITHUB_OUTPUT"
else
    echo "::notice::Updates detected!"
    echo "should_build=true" >> "$GITHUB_OUTPUT"
fi
