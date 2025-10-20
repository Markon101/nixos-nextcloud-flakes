# Testing Handoff Notes

This document captures the current state of the unattended Nextcloud installer ISO so another engineer can continue debugging and refining it.

## Build environment

- Repository root: `/home/anon/git/nixos-nextcloud-flake`
- Primary build command: `nix --extra-experimental-features 'nix-command flakes' build .#packages.x86_64-linux.nextcloud-installer-iso -o result-nextcloud`
- ISO output: `result-nextcloud/iso/nixos-minimal-25.05.20250112.2f9e2f8-x86_64-linux.iso`
- QEMU smoke test (serial console):
  ```sh
  nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#qemu -c \
    qemu-img create -f qcow2 /tmp/nextcloud-test.qcow2 20G

  timeout 900 nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#qemu -c \
    qemu-system-x86_64 \
      -cdrom result-nextcloud/iso/nixos-minimal-25.05.20250112.2f9e2f8-x86_64-linux.iso \
      -drive file=/tmp/nextcloud-test.qcow2,format=qcow2 \
      -m 3072 -serial stdio -display none -boot order=d -no-reboot
  ```

## Current behaviour

- The autoinstall service starts automatically and reaches `nixos-install`, but the run fails with `nixos-install: line 163: nix: command not found` followed by `configuration file  doesn't exist`. The system drops to the live shell afterwards.
- Earlier failures (`swapoff`, `mount`, `mkpasswd`) were fixed by injecting the relevant binaries into `PATH`; the remaining blocker is ensuring `nix` (from `nix` package) is available during the autoinstall service.
- Manual install attempts fail for the same reason if the service is not fixed, because the installer still invokes the script without entering a chroot or providing `nix`.

## Next steps / open items

1. **Ensure `nix` is on PATH:** verify that `${pkgs.nix}/bin` is present when the autoinstall script runs (added via `lib.makeBinPath` but not yet tested due to timeout). Re-run the QEMU test and confirm the service completes, reboots, and produces `/root/INSTALL-INFO.txt` on the target disk.
2. **Shorten install time in testing:** the current QEMU run consumes the entire 15-minute timeout. Consider reducing logs by running `qemu-system-x86_64` outside `timeout` or piping to a file for long installs.
3. **Manual install docs:** once the unattended flow succeeds, document the manual fallback (mainly to reassure that `nixos-install` can be executed inside the live environment using the same script).
4. **Post-install verification:** after the autoinstall finishes, boot the QCOW2 disk and verify:
   - `admin` user password is `default1234567` and forced rotation steps work.
   - Nextcloud service starts with the generated password.
   - `/etc/nixos` contains the repo with `origin` set correctly.
5. **Cleanup:** remove the `nixos` channel warning (symlink failure) if it becomes noisy or causes automation problems.

## Useful log markers

- `autoinstall-nextcloud[...]` entries in the serial console log show each script step.
- Look for the `openssl passwd -6` line to confirm the system password hash is created.
- Successful runs should log `nixos-install --flake ...` followed by a reboot within the service.

## Reference files

- Autoinstall script: `hosts/nextcloud-server/autoinstall.sh`
- ISO configuration: `hosts/nextcloud-server/iso.nix`
- Testing notes (this file) and `notes-for-codex.txt` for agent reminders.

Feel free to append additional observations or pitfalls as you continue debugging.
