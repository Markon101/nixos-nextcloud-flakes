{ config, pkgs, lib, ... }:
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    keyMap = "us";
    useXkbConfig = false;
  };

  programs.git.enable = true;
  programs.htop.enable = true;
  programs.mtr.enable = true;

  environment.systemPackages = with pkgs; [
    curl
    dig
    htop
    iperf3
    jq
    nano
    pciutils
    tmux
    vim
  ];

  networking.useDHCP = lib.mkDefault true;
  services.timesyncd.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
      KbdInteractiveAuthentication = false;
      X11Forwarding = false;
      LogLevel = "VERBOSE";
    };
    hostKeys = [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
      {
        path = "/etc/ssh/ssh_host_rsa_key";
        type = "rsa";
        bits = 4096;
      }
    ];
  };

  users.mutableUsers = false;
  users.users = {
    admin = {
      isNormalUser = true;
      description = "Nextcloud administrator";
      extraGroups = [ "wheel" ];
      hashedPasswordFile = "/var/lib/nextcloud/secrets/admin-password-hash";
      openssh.authorizedKeys.keys = [ ];
      shell = pkgs.bashInteractive;
    };
  };

  security.sudo = {
    enable = true;
    wheelNeedsPassword = true;
  };
  security.pam.services.sudo = { };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 80 443 ];
    logRefusedConnections = true;
  };

  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1h";
    ignoreIP = [ "127.0.0.0/8" "::1" ];
  };

  system.autoUpgrade = {
    enable = true;
    allowReboot = false;
    dates = "04:00";
    randomizedDelaySec = "45min";
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  security.acme.defaults.server = "https://acme-v02.api.letsencrypt.org/directory";
  security.auditd.enable = true;
  security.apparmor.enable = true;
}
