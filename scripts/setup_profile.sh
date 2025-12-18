#!/bin/bash
set -e

# Define Paths
WORK_DIR="/tmp/archlive"
REPO_DIR=$(pwd)

echo ">>> Starting Diet Profile Setup..."

# 1. Copy Releng Profile
echo "-> Copying releng profile to $WORK_DIR..."
cp -r /usr/share/archiso/configs/releng "$WORK_DIR"

# 2. Apply Custom Package List
if [ -f "$REPO_DIR/package_list.x86_64" ]; then
    echo "-> Applying custom package list..."
    sed 's/#.*//;s/[ \t]*$//;/^$/d' "$REPO_DIR/package_list.x86_64" > "$WORK_DIR/packages.x86_64"
else
    echo "::error::package_list.x86_64 not found!"
    exit 1
fi

# 3. [DIET] Remove Docs & Locales via pacman.conf
echo "-> Configuring pacman to exclude docs and locales..."
NO_EXTRACT_RULE="NoExtract  = usr/share/help/* usr/share/doc/* usr/share/man/* usr/share/locale/* usr/share/i18n/* !usr/share/locale/en* !usr/share/locale/ko*"
sed -i "/^#NoExtract/c\\$NO_EXTRACT_RULE" /etc/pacman.conf
sed -i "/^#NoExtract/c\\$NO_EXTRACT_RULE" "$WORK_DIR/pacman.conf"

# 4. [COMPRESSION] Maximize XZ Compression (RootFS)
echo "-> Setting XZ compression for RootFS..."
sed -i "s/airootfs_image_tool_options=('-comp' 'zstd'.*)/airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')/" "$WORK_DIR/profiledef.sh"

# 5. [INITRAMFS] Optimize Size (KMS removal & XZ compression)
echo "-> Optimizing Initramfs..."
MKINITCPIO_CONF=$(find "$WORK_DIR" -name "mkinitcpio.conf" -type f | head -n 1)

if [ -n "$MKINITCPIO_CONF" ]; then
    echo "   Found config at: $MKINITCPIO_CONF"
    
    # Remove KMS hook
    sed -i 's/\<kms\>//g' "$MKINITCPIO_CONF"
    
    # Force XZ Compression
    if grep -q "^COMPRESSION=" "$MKINITCPIO_CONF"; then
        sed -i 's/^COMPRESSION=.*/COMPRESSION="xz"/' "$MKINITCPIO_CONF"
    else
        echo 'COMPRESSION="xz"' >> "$MKINITCPIO_CONF"
    fi
    
    # Set Compression Options
    if grep -q "^COMPRESSION_OPTIONS=" "$MKINITCPIO_CONF"; then
        sed -i "s/^COMPRESSION_OPTIONS=.*/COMPRESSION_OPTIONS=('-9e')/" "$MKINITCPIO_CONF"
    else
        echo "COMPRESSION_OPTIONS=('-9e')" >> "$MKINITCPIO_CONF"
    fi
else
    echo "::warning::mkinitcpio.conf not found! Skipping initramfs optimization."
fi

# 6. Desktop Configuration
echo "-> Configuring Desktop Environment..."
AIROOTFS_DIR="$WORK_DIR/airootfs"

# SDDM Autologin
mkdir -p "$AIROOTFS_DIR/etc/sddm.conf.d"
if [ -f "$REPO_DIR/configs/autologin.conf" ]; then
    echo "   Applying autologin config..."
    cp "$REPO_DIR/configs/autologin.conf" "$AIROOTFS_DIR/etc/sddm.conf.d/autologin.conf"
    chmod 644 "$AIROOTFS_DIR/etc/sddm.conf.d/autologin.conf"
else
    echo "::warning::configs/autologin.conf not found!"
fi

# Enable Essential Services
SYSTEMD_DIR="$AIROOTFS_DIR/etc/systemd/system"
mkdir -p "$SYSTEMD_DIR/multi-user.target.wants"
ln -sf /usr/lib/systemd/system/sddm.service "$SYSTEMD_DIR/display-manager.service"
ln -sf /usr/lib/systemd/system/NetworkManager.service "$SYSTEMD_DIR/multi-user.target.wants/NetworkManager.service"

echo ">>> Profile Setup Complete."