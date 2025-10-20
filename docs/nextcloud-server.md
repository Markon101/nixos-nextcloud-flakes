# NixOS Nextcloud Server Setup Guide

This repository contains a fully reproducible flake-based NixOS configuration for a hardened Nextcloud server.  The provided installer ISO performs an unattended deployment: it partitions the target disk, installs NixOS with Btrfs, generates strong credentials, and reboots into a ready-to-use Nextcloud instance secured with a self-signed certificate.  You only need to boot once from the ISO and grab the generated passwords from `/root/INSTALL-INFO.txt` on the installed system.

## Repository layout

```
.
├── flake.nix
├── flake.lock
├── hosts/
│   └── nextcloud-server/
│       ├── default.nix                # Host-specific configuration (TLS, MariaDB, paths)
│       ├── hardware-configuration.nix # Auto-generated per machine during install
│       └── iso.nix                    # Installer ISO definition + autoinstall service
├── modules/
│   ├── common/
│   │   └── base-system.nix            # Shared base hardening, SSH, packages
│   └── services/
│       └── nextcloud.nix              # Nextcloud service, Redis/MariaDB wiring, secrets
└── docs/
    └── nextcloud-server.md            # This document
```

## What the autonomous installer does

- Wipes the selected disk (`/dev/sda` by default, override with `autoinstall.disk=` kernel parameter or by editing `/etc/nixos/autoinstall-target-disk` on the ISO).
- Creates a GPT layout with a 1 GiB EFI partition and a Btrfs root partition using subvolumes `@` (/) and `@nix` (/nix) with zstd compression.
- Copies this repository into `/etc/nixos`, initialises a `main` branch, and sets the `git@github.com:Markon101/nixos-nextcloud-flakes.git` remote for future pushes.
- Sets the system `admin` user password to the known value `default1234567` (stored hashed at `/var/lib/nextcloud/secrets/admin-password-hash`) and generates a random password for the Nextcloud web admin (default user `ncadmin`, stored plaintext at `/var/lib/nextcloud/secrets/admin-password`).  Both secrets are written to `/root/INSTALL-INFO.txt` together with an installer log so you can rotate them immediately after first boot.
- Installs NixOS via `nixos-install --flake /etc/nixos#nextcloud-server`, then reboots into the new system with SSH enabled and password authentication available for the `admin` user.
- Serves Nextcloud immediately over HTTPS using a self-signed certificate; ACME/Let’s Encrypt can be enabled later once DNS is in place.

Security highlights baked into the host profile include fail2ban, firewall, AppArmor, auditd, automatic system updates, Redis caching, MariaDB (unix-socket auth), and the Nextcloud `notify_push` worker.

## Build the ISO

From a machine with flakes enabled:

```sh
nix --extra-experimental-features 'nix-command flakes' build .#packages.x86_64-linux.nextcloud-installer-iso
```

The image appears at `./result/iso/nextcloud-installer.iso`.  Write it to a USB drive (replace `/dev/sdX` with the correct device!) with:

```sh
sudo dd if=./result/iso/nextcloud-installer.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

### Customising the target disk

The installer defaults to `/dev/sda`.  To override at boot time, add `autoinstall.disk=/dev/nvme0n1` to the kernel command line (press `e` in GRUB, append to the `linux` line, boot).  To persistently bake a different default into the ISO, edit `hosts/nextcloud-server/iso.nix` or create `/etc/nixos/autoinstall-target-disk` on the ISO with the desired device path before booting.

To disable the unattended run (for manual intervention), add `autoinstall.disable=1` to the kernel command line.  The autoinstaller writes verbose logs to `/root/autoinstall.log` in the live environment and copies them into the installed system.

## Boot & first login

1. Boot from the USB stick.  The installer service starts automatically once the system reaches multi-user mode.
2. In 5–10 minutes (depending on network speed and hardware) the machine reboots into the freshly installed system.
3. Log in via SSH (or console) as `admin` using the default password `default1234567` (also recorded in `/root/INSTALL-INFO.txt`).  The file contains the randomly generated Nextcloud web admin password and a pointer to the installer log.
4. Access Nextcloud at `https://<host-or-ip>/` and accept the self-signed certificate warning.  Authenticate with the credentials from `INSTALL-INFO.txt` (`ncadmin` plus the random password).

## Post-install adjustments

The configuration lives at `/etc/nixos` with a `main` branch ready for commits.  Typical follow-up steps:

- **Set your hostname & domain**: update `networking.hostName`, `networking.domain`, and `nextcloudServer.fqdn` in `hosts/nextcloud-server/default.nix`.
- **Switch to Let’s Encrypt when DNS is ready**:
  ```nix
  nextcloudServer = {
    fqdn = "cloud.example.com";
    enableACME = true;
    acmeEmail = "admin@example.com";
  };
  ```
  Then run `sudo nixos-rebuild switch --flake /etc/nixos#nextcloud-server`.  Nginx will stop using the self-signed cert once ACME succeeds.
- **Add SSH keys**: extend `users.users.admin.openssh.authorizedKeys.keys` in `modules/common/base-system.nix`.  After verifying key access you can disable password logins via `services.openssh.settings.PasswordAuthentication = false;`.
- **Rotate credentials**:
- Generate a new system password hash with `mkpasswd -m sha-512` and replace `/var/lib/nextcloud/secrets/admin-password-hash` (the default `default1234567` is only meant for the first login).
  - Update the Nextcloud web admin secret by editing `/var/lib/nextcloud/secrets/admin-password` (and ideally record it somewhere safe).
  Restart services with `sudo systemctl restart nextcloud-setup nextcloud-phpfpm`.

## Routine operations

- **Update the system**:
  ```sh
  cd /etc/nixos
  nix flake update
  sudo nixos-rebuild switch --flake .#nextcloud-server
  ```
- **Check services**:
  ```sh
  sudo systemctl status nextcloud-setup nextcloud-phpfpm nextcloud-notify_push mariadb redis-nextcloud
  ```
- **Logs**: use `journalctl -u nextcloud-phpfpm`, `journalctl -u nginx`, and `journalctl -u fail2ban` to inspect runtime issues.
- **Backups**: capture `/var/lib/nextcloud/data`, `/var/lib/mysql`, `/var/lib/nextcloud/secrets`, and `/etc/nixos`.  Enable automated Restic jobs by adding a `services.restic.backups.<name>` entry once storage credentials are available (an example stub lives in `hosts/nextcloud-server/default.nix`).

## Next steps & hardening ideas

1. Replace the self-signed certificate by enabling ACME once DNS is in place.
2. Configure off-site backups (Restic, Borg, etc.).
3. Integrate monitoring (e.g. enable `services.prometheus.exporters.node`).
4. Review Nextcloud’s built-in security warnings after the first login.

## Troubleshooting the autoinstaller

- Check the live log on the ISO: `/root/autoinstall.log`.
- After reboot, consult `/root/autoinstall.log` on the installed system.
- Use `autoinstall.disable=1` to drop into a manual shell without touching disks.
- Ensure the target disk name matches reality (`lsblk` in the live environment helps).  NVMe and eMMC devices require the `autoinstall.disk=` override because the default `/dev/sda` may not exist.

## Manual deployment (optional)

If you ever want to run the process by hand instead of the autonomous service:

1. Boot the ISO with `autoinstall.disable=1`.
2. Partition/format disks to taste (the configuration expects Btrfs on `/`).
3. Mount the target under `/mnt` (with subvolumes if desired) and copy `/etc/nixos` from the ISO.
4. Generate the hardware config:
   ```sh
   nixos-generate-config --root /mnt --show-hardware-config > /mnt/etc/nixos/hosts/nextcloud-server/hardware-configuration.nix
   ```
5. Create `/mnt/var/lib/nextcloud/secrets/admin-password` and `/mnt/var/lib/nextcloud/secrets/admin-password-hash`.
6. Install: `nixos-install --flake /mnt/etc/nixos#nextcloud-server --no-root-passwd`.
7. Reboot and continue with the post-install steps above.

Happy self-hosting!
