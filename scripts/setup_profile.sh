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

# 4. [INITRAMFS] Optimize Size (Target: archiso.conf)
# Remove 'kms' and PXE hooks to save space.
echo "-> Optimizing Initramfs (archiso.conf)..."

CONF_FILE=$(find "$WORK_DIR" -name "archiso.conf" | head -n 1)

if [ -n "$CONF_FILE" ]; then
    echo "   Processing config: $CONF_FILE"
    
    # Updated removal list (kms + pxe hooks)
    HOOKS_TO_REMOVE=("kms" "archiso_pxe_common" "archiso_pxe_nbd" "archiso_pxe_http" "archiso_pxe_nfs")
    
    for HOOK in "${HOOKS_TO_REMOVE[@]}"; do
        if grep -q "\<$HOOK\>" "$CONF_FILE"; then
            echo "      - Removing '$HOOK' hook..."
            sed -i "s/\<$HOOK\>//g" "$CONF_FILE"
        fi
    done
else
    echo "::warning::archiso.conf not found! Initramfs optimization skipped."
fi

# 5. Desktop Configuration
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

# Enable Essential Services (SDDM & NetworkManager)
SYSTEMD_DIR="$AIROOTFS_DIR/etc/systemd/system"
mkdir -p "$SYSTEMD_DIR/multi-user.target.wants"
ln -sf /usr/lib/systemd/system/sddm.service "$SYSTEMD_DIR/display-manager.service"
ln -sf /usr/lib/systemd/system/NetworkManager.service "$SYSTEMD_DIR/multi-user.target.wants/NetworkManager.service"

# 6. [USER SETUP] Create 'arch' user for Autologin
echo "-> Creating 'arch' user configuration..."

# 6-1. Use systemd-sysusers to create the user 'arch' with UID 1000
# This creates the user in /etc/passwd at boot/install time correctly.
mkdir -p "$AIROOTFS_DIR/usr/lib/sysusers.d"
cat <<EOF > "$AIROOTFS_DIR/usr/lib/sysusers.d/archiso-user.conf"
u arch 1000 "Arch Live User" /home/arch /bin/bash
m arch wheel
m arch video
m arch audio
m arch storage
m arch optical
m arch network
m arch power
EOF

# 6-2. Create Home Directory
# We must create the directory so permissions can be applied
mkdir -p "$AIROOTFS_DIR/home/arch"

# 6-3. Set Home Directory Permissions in profiledef.sh
# This ensures /home/arch is owned by arch:arch (1000:1000)
cat <<EOF >> "$WORK_DIR/profiledef.sh"
file_permissions+=(["/home/arch"]="1000:1000:755")
EOF

# 6-4. Enable Passwordless Sudo for 'wheel' group
# This allows the 'arch' user to use sudo without a password
mkdir -p "$AIROOTFS_DIR/etc/sudoers.d"
echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > "$AIROOTFS_DIR/etc/sudoers.d/00-wheel-nopasswd"
chmod 440 "$AIROOTFS_DIR/etc/sudoers.d/00-wheel-nopasswd"

echo ">>> Profile Setup Complete."
