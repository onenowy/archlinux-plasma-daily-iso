#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="archlinux"
iso_label="ARCH_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Arch Linux <https://archlinux.org>"
iso_application="Arch Linux Live/Rescue DVD"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=('uefi.systemd-boot')
pacman_conf="pacman.conf"

# [EROFS Configuration]
# -zlzma,6: LZMA compression level 6 (Max compression)
# -C 1048576: 1MB Pcluster size
# -E ...: Enable ztailpacking, merge all fragments, inode-based deduplication
airootfs_image_type="erofs"
airootfs_image_tool_options=('-zlzma,6' '-C' '1048576' '-E' 'ztailpacking,all-fragments,fragdedupe=inode')

# Bootstrap compression settings
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')

# File Permissions (Merged /home/arch here)
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/root/.gnupg"]="0:0:700"
  ["/usr/local/bin/choose-mirror"]="0:0:755"
  ["/usr/local/bin/Installation_guide"]="0:0:755"
  ["/usr/local/bin/livecd-sound"]="0:0:755"
  ["/home/arch"]="1000:1000:755"
)
