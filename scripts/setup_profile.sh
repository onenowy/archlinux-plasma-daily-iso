#!/bin/bash
set -e

# Define Paths
WORK_DIR="/tmp/archlive"
REPO_DIR=$(pwd)

# [OPTION] Set COW Space Size
COW_SPACE_SIZE="4G"

echo ">>> Starting Custom Profile Setup..."

# 1. Copy Releng Profile
echo "-> Copying releng profile to $WORK_DIR..."
cp -r /usr/share/archiso/configs/releng "$WORK_DIR"
chmod -R +w "$WORK_DIR"

# 2. Apply Custom Package List
if [ -f "$REPO_DIR/package_list.x86_64" ]; then
    echo "-> Applying custom package list..."
    sed 's/#.*//;s/[ \t]*$//;/^$/d' "$REPO_DIR/package_list.x86_64" > "$WORK_DIR/packages.x86_64"
else
    echo "::error::package_list.x86_64 not found!"
    exit 1
fi

# 3. [OPTIMIZE] Remove Docs & Locales
echo "-> Configuring pacman to exclude docs and locales..."
NO_EXTRACT_RULE="NoExtract  = usr/share/help/* usr/share/doc/* usr/share/man/* usr/share/locale/* usr/share/i18n/* !usr/share/locale/en* !usr/share/locale/ko*"
sed -i "/^#NoExtract/c\\$NO_EXTRACT_RULE" /etc/pacman.conf
sed -i "/^#NoExtract/c\\$NO_EXTRACT_RULE" "$WORK_DIR/pacman.conf"

# 4. [INITRAMFS] Optimize Size
echo "-> Optimizing Initramfs (archiso.conf)..."
CONF_FILE="$WORK_DIR/airootfs/etc/mkinitcpio.conf.d/archiso.conf"
if [ -f "$CONF_FILE" ]; then
    HOOKS_TO_REMOVE=("kms" "archiso_pxe_common" "archiso_pxe_nbd" "archiso_pxe_http" "archiso_pxe_nfs")
    for HOOK in "${HOOKS_TO_REMOVE[@]}"; do
        if grep -q "$HOOK" "$CONF_FILE"; then
            sed -i -E "s/\b$HOOK\b//g" "$CONF_FILE"
        fi
    done
fi

# 5. [BOOTLOADER] Increase COW Space
echo "-> Setting COW Space to $COW_SPACE_SIZE..."
UEFI_CONFS=$(find "$WORK_DIR/efiboot/loader/entries" -name "*.conf")
for CONF in $UEFI_CONFS; do
    grep -q "^options" "$CONF" && sed -i "/^options/ s/$/ cow_spacesize=$COW_SPACE_SIZE/" "$CONF"
done

SYSLINUX_CONF="$WORK_DIR/syslinux/archiso_sys-linux.cfg"
[ -f "$SYSLINUX_CONF" ] && sed -i "/^APPEND/ s/$/ cow_spacesize=$COW_SPACE_SIZE/" "$SYSLINUX_CONF"

# 6. [NETWORK & DESKTOP] Fix Conflicts
echo "-> Configuring Desktop & Network..."
AIROOTFS_DIR="$WORK_DIR/airootfs"
SYSTEMD_DIR="$AIROOTFS_DIR/etc/systemd/system"
MULTI_USER_DIR="$SYSTEMD_DIR/multi-user.target.wants"

# Mask systemd-networkd & resolved
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

# SDDM Autologin
mkdir -p "$AIROOTFS_DIR/etc/sddm.conf.d"
if [ -f "$REPO_DIR/configs/autologin.conf" ]; then
    cp "$REPO_DIR/configs/autologin.conf" "$AIROOTFS_DIR/etc/sddm.conf.d/autologin.conf"
    chmod 644 "$AIROOTFS_DIR/etc/sddm.conf.d/autologin.conf"
fi

# 7. [USER SETUP] Create 'arch' user with Full Privileges
echo "-> Creating 'arch' user configuration..."

# 7-1. Create User
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

# 7-2. Setup Home Directory
mkdir -p "$AIROOTFS_DIR/home/arch"
cat <<EOF >> "$WORK_DIR/profiledef.sh"
file_permissions+=(["/home/arch"]="1000:1000:755")
EOF

# 7-3. Sudoers (CLI): Allow passwordless sudo for wheel
mkdir -p "$AIROOTFS_DIR/etc/sudoers.d"
echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > "$AIROOTFS_DIR/etc/sudoers.d/00-wheel-nopasswd"
chmod 440 "$AIROOTFS_DIR/etc/sudoers.d/00-wheel-nopasswd"

# 7-4. [CRITICAL FIX] Polkit (GUI): Allow passwordless actions for wheel
# This prevents Dolphin/Plasma from asking for root password for mounting, etc.
mkdir -p "$AIROOTFS_DIR/etc/polkit-1/rules.d"
cat <<EOF > "$AIROOTFS_DIR/etc/polkit-1/rules.d/49-nopasswd_global.rules"
/* Allow members of the wheel group to execute any actions
 * without password authentication, similar to NOPASSWD in sudoers.
 */
polkit.addRule(function(action, subject) {
    if (subject.isInGroup("wheel")) {
        return polkit.Result.YES;
    }
});
EOF

echo ">>> Profile Setup Complete."
