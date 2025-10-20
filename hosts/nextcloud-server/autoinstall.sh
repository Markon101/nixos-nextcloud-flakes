set -euo pipefail

exec > >(tee -a /root/autoinstall.log) 2>&1

SGDISK="@SGDISK@"
MKFS_FAT="@MKFS_FAT@"
MKFS_BTRFS="@MKFS_BTRFS@"
BTRFS="@BTRFS@"
OPENSSL="@OPENSSL@"
MKPASSWD="@MKPASSWD@"

if grep -q 'autoinstall.disable=1' /proc/cmdline; then
  echo "Autoinstall disabled via kernel cmdline."
  exit 0
fi

if [ -e /root/.autoinstall-done ]; then
  echo "Autoinstall already completed, skipping."
  exit 0
fi

touch /root/.autoinstall-done

TARGET_DISK=""
if grep -q 'autoinstall.disk=' /proc/cmdline; then
  TARGET_DISK="$(sed -n 's/.*autoinstall.disk=\([^ ]*\).*/\1/p' /proc/cmdline)"
fi
if [ -z "$TARGET_DISK" ] && [ -f /etc/nixos/autoinstall-target-disk ]; then
  TARGET_DISK="$(sed -n '1p' /etc/nixos/autoinstall-target-disk)"
fi
if [ -z "$TARGET_DISK" ]; then
  TARGET_DISK="/dev/sda"
fi

if [ ! -b "$TARGET_DISK" ]; then
  echo "Target disk $TARGET_DISK not found; aborting."
  exit 1
fi

case "$TARGET_DISK" in
  *[0-9]) PART_PREFIX="${TARGET_DISK}p" ;;
  *) PART_PREFIX="$TARGET_DISK" ;;
esac

EFI_PART="${PART_PREFIX}1"
ROOT_PART="${PART_PREFIX}2"

echo "Provisioning disk $TARGET_DISK (EFI=$EFI_PART root=$ROOT_PART)"

swapoff -a || true
umount -R /mnt 2>/dev/null || true

$SGDISK --zap-all "$TARGET_DISK"
$SGDISK -n1:0:+1G -t1:ef00 "$TARGET_DISK"
$SGDISK -n2:0:0 -t2:8300 "$TARGET_DISK"

wipefs -a "$EFI_PART" 2>/dev/null || true
wipefs -a "$ROOT_PART" 2>/dev/null || true

$MKFS_FAT -F32 -n EFI "$EFI_PART"
$MKFS_BTRFS -f -L nixos "$ROOT_PART"

mount "$ROOT_PART" /mnt
$BTRFS subvolume create /mnt/@
$BTRFS subvolume create /mnt/@nix
umount /mnt

mount -o compress=zstd,subvol=@ "$ROOT_PART" /mnt
mkdir -p /mnt/{boot,nix}
mount -o compress=zstd,subvol=@nix "$ROOT_PART" /mnt/nix
mount "$EFI_PART" /mnt/boot

mkdir -p /mnt/etc/nixos
cp -a /etc/nixos/. /mnt/etc/nixos/
chmod -R u+w /mnt/etc/nixos

nixos-generate-config --root /mnt --show-hardware-config > /mnt/etc/nixos/hosts/nextcloud-server/hardware-configuration.nix

install -d -m 700 -o root -g root /mnt/var/lib/nextcloud/secrets

NEXTCLOUD_PASS="$($OPENSSL rand -base64 24)"
ADMIN_PASS="default1234567"

printf '%s\n' "$NEXTCLOUD_PASS" > /mnt/var/lib/nextcloud/secrets/admin-password
chmod 600 /mnt/var/lib/nextcloud/secrets/admin-password

HASHED="$($MKPASSWD -m sha-512 "$ADMIN_PASS")"
printf '%s\n' "$HASHED" > /mnt/var/lib/nextcloud/secrets/admin-password-hash
chmod 600 /mnt/var/lib/nextcloud/secrets/admin-password-hash

git -C /mnt/etc/nixos init
git -C /mnt/etc/nixos branch -M main
git -C /mnt/etc/nixos config user.name "Markon101"
git -C /mnt/etc/nixos config user.email "markon101@users.noreply.github.com"
git -C /mnt/etc/nixos add .
git -C /mnt/etc/nixos commit -m "Autoinstall bootstrap" || true
git -C /mnt/etc/nixos remote remove origin 2>/dev/null || true
git -C /mnt/etc/nixos remote add origin git@github.com:Markon101/nixos-nextcloud-flakes.git || true

nixos-install --flake /mnt/etc/nixos#nextcloud-server --root /mnt --no-root-passwd

cat <<EOF > /mnt/root/INSTALL-INFO.txt
Autonomous installation complete.

System user 'admin' password: $ADMIN_PASS
Nextcloud web admin (see nextcloudServer.adminUser, default 'ncadmin') password: $NEXTCLOUD_PASS

Configuration repository: /etc/nixos
Log file: /root/autoinstall.log
