{ config, lib, modulesPath, pkgs, ... }:
let
  autoinstallScript =
    let
      scriptTemplate = builtins.readFile ./autoinstall.sh;
      scriptContents = lib.replaceStrings
        [ "@PATH@" "@SGDISK@" "@MKFS_FAT@" "@MKFS_BTRFS@" "@BTRFS@" "@OPENSSL@" ]
        [
          (lib.makeBinPath [
            pkgs.coreutils
            pkgs.util-linux
            pkgs.git
            pkgs.nixos-install-tools
            pkgs.nix
          ])
          "${pkgs.gptfdisk}/bin/sgdisk"
          "${pkgs.dosfstools}/bin/mkfs.fat"
          "${pkgs.btrfs-progs}/bin/mkfs.btrfs"
          "${pkgs.btrfs-progs}/bin/btrfs"
          "${pkgs.openssl}/bin/openssl"
        ]
        scriptTemplate;
    in
    pkgs.writeShellScript "autoinstall-nextcloud" scriptContents;
in
{
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
    ../../modules/common/base-system.nix
  ];

  networking.hostName = "nextcloud-installer";

  boot.kernelParams = [
    "console=tty0"
    "console=ttyS0,115200n8"
  ];

  users.users.root = {
    password = lib.mkForce "nixos";
    hashedPassword = lib.mkForce null;
  };

  services.openssh.settings.PermitRootLogin = lib.mkForce "yes";

  services.nextcloud.enable = lib.mkForce false;

  environment.systemPackages = with pkgs; [
    git
    tmux
    vim
    gptfdisk
    btrfs-progs
    dosfstools
    util-linux
    openssl
    whois
  ];

  environment.etc."nixos/flake.nix".source = ../../flake.nix;
  environment.etc."nixos/hosts/nextcloud-server/default.nix".source =
    ../../hosts/nextcloud-server/default.nix;
  environment.etc."nixos/hosts/nextcloud-server/hardware-configuration.nix".source =
    ../../hosts/nextcloud-server/hardware-configuration.nix;
  environment.etc."nixos/modules/common/base-system.nix".source =
    ../../modules/common/base-system.nix;
  environment.etc."nixos/modules/services/nextcloud.nix".source =
    ../../modules/services/nextcloud.nix;

  systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];

  systemd.services.autoinstall-nextcloud = {
    description = "Autonomous Nextcloud server installation";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = autoinstallScript;
      StandardOutput = "journal+console";
      StandardError = "journal+console";
    };
  };

  documentation.nixos.enable = false;
}
