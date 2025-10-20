{ lib, ... }:
{
  # Placeholder hardware configuration.
  # Replace this file with the generated version from `nixos-generate-config`
  # after installing onto the target hardware or VM.

  fileSystems."/" = lib.mkDefault {
    device = "/dev/disk/by-uuid/00000000-0000-0000-0000-000000000000";
    fsType = "ext4";
    options = [ "defaults" "noauto" ];
  };
}
