#!/bin/bash
set -eu

REPO_DIR=$(pwd)
CONFIG_DIR="$REPO_DIR/configs"

echo ">>> Starting Custom Profile Setup..."
echo "-> Working Target: $BUILD_DIR"

# Copy Base Profile (releng)
echo "-> Copying releng profile..."
cp -r /usr/share/archiso/configs/releng "$BUILD_DIR"
chmod -R +w "$BUILD_DIR"

# Apply Custom Packages
if [ -f "$REPO_DIR/package_list.x86_64" ]; then
    echo "-> Applying custom package list..."
    sed 's/#.*//;s/[ \t]*$//;/^$/d' "$REPO_DIR/package_list.x86_64" > "$BUILD_DIR/packages.x86_64"
else
    echo "::error::package_list.x86_64 not found!"
    exit 1
fi

# Pacman Config (Exclude Docs/Locales)
echo "-> Configuring pacman exclusions..."
NO_EXTRACT_RULE="NoExtract  = usr/share/help/* usr/share/doc/* usr/share/man/* usr/share/locale/* usr/share/i18n/* !usr/share/locale/en*"
sed -i "s|^#NoExtract.*|${NO_EXTRACT_RULE}|" /etc/pacman.conf
sed -i "s|^#NoExtract.*|${NO_EXTRACT_RULE}|" "$BUILD_DIR/pacman.conf"

# Remove "with speech" boot entries
echo "-> Removing speech accessibility boot entries..."
rm -f "$BUILD_DIR"/efiboot/loader/entries/*speech*.conf

# Add custom boot entries (cowspace options)
echo "-> Adding custom boot entries..."
cp "$CONFIG_DIR"/efiboot/loader/entries/*.conf "$BUILD_DIR/efiboot/loader/entries/"

# Initramfs Optimization (Remove KMS/PXE hooks)
echo "-> Optimizing Initramfs..."
CONF_FILE="$BUILD_DIR/airootfs/etc/mkinitcpio.conf.d/archiso.conf"
if [ -f "$CONF_FILE" ]; then
    HOOKS_TO_REMOVE=("kms" "archiso_pxe_common" "archiso_pxe_nbd" "archiso_pxe_http" "archiso_pxe_nfs")
    for HOOK in "${HOOKS_TO_REMOVE[@]}"; do
        if grep -q "$HOOK" "$CONF_FILE"; then
            sed -i -E "s/\b$HOOK\b//g" "$CONF_FILE"
        fi
    done
fi

# Network & Desktop Configuration
echo "-> Configuring Network & SDDM..."
AIROOTFS_DIR="$BUILD_DIR/airootfs"
SYSTEMD_DIR="$AIROOTFS_DIR/etc/systemd/system"
MULTI_USER_DIR="$SYSTEMD_DIR/multi-user.target.wants"

# Mask conflicting services
find "$SYSTEMD_DIR" -name "systemd-networkd.service" -delete
find "$SYSTEMD_DIR" -name "systemd-resolved.service" -delete
find "$SYSTEMD_DIR" -name "systemd-networkd.socket" -delete
ln -sf /dev/null "$SYSTEMD_DIR/systemd-networkd.service"
ln -sf /dev/null "$SYSTEMD_DIR/systemd-resolved.service"
ln -sf /dev/null "$SYSTEMD_DIR/systemd-networkd-wait-online.service"
rm -f "$AIROOTFS_DIR/etc/resolv.conf"

# Enable NetworkManager & SDDM
mkdir -p "$MULTI_USER_DIR"
ln -sf /usr/lib/systemd/system/sddm.service "$SYSTEMD_DIR/display-manager.service"
ln -sf /usr/lib/systemd/system/NetworkManager.service "$MULTI_USER_DIR/NetworkManager.service"
ln -sf /usr/lib/systemd/system/bluetooth.service "$MULTI_USER_DIR/bluetooth.service"

# Apply SDDM Autologin
mkdir -p "$AIROOTFS_DIR/etc/sddm.conf.d"
[ -f "$CONFIG_DIR/autologin.conf" ] && cp "$CONFIG_DIR/autologin.conf" "$AIROOTFS_DIR/etc/sddm.conf.d/autologin.conf"

# User Setup (Sysusers, Home, Sudoers, Polkit)
echo "-> Configuring User & Permissions..."
mkdir -p "$AIROOTFS_DIR/usr/lib/sysusers.d"
[ -f "$CONFIG_DIR/archiso-user.conf" ] && cp "$CONFIG_DIR/archiso-user.conf" "$AIROOTFS_DIR/usr/lib/sysusers.d/archiso-user.conf"

mkdir -p "$AIROOTFS_DIR/home/arch"

mkdir -p "$AIROOTFS_DIR/etc/sudoers.d"
[ -f "$CONFIG_DIR/00-wheel-nopasswd" ] && cp "$CONFIG_DIR/00-wheel-nopasswd" "$AIROOTFS_DIR/etc/sudoers.d/00-wheel-nopasswd" && chmod 440 "$AIROOTFS_DIR/etc/sudoers.d/00-wheel-nopasswd"

mkdir -p "$AIROOTFS_DIR/etc/polkit-1/rules.d"
[ -f "$CONFIG_DIR/49-nopasswd_global.rules" ] && cp "$CONFIG_DIR/49-nopasswd_global.rules" "$AIROOTFS_DIR/etc/polkit-1/rules.d/49-nopasswd_global.rules"

# Apply Custom Profile Definition
echo "-> Overwriting profiledef.sh..."
if [ -f "$CONFIG_DIR/profiledef.sh" ]; then
    cp "$CONFIG_DIR/profiledef.sh" "$BUILD_DIR/profiledef.sh"
    chmod +x "$BUILD_DIR/profiledef.sh"
else
    echo "::error::configs/profiledef.sh not found!"
    exit 1
fi

echo ">>> Profile Setup Complete."
