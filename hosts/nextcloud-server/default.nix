{ inputs, config, pkgs, lib, ... }:
let
  fqdn = config.nextcloudServer.fqdn;
in
{
  imports = [
    ../../modules/common/base-system.nix
    ../../modules/services/nextcloud.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "nextcloud";
  networking.domain = "lan";

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
    timeout = 3;
  };

  boot.kernel.sysctl = {
    "net.ipv4.tcp_syncookies" = 1;
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.ip_forward" = 0;
  };

  services.nginx.virtualHosts.${fqdn} = lib.mkMerge [
    {
      forceSSL = true;
      http2 = true;
      enableACME = config.nextcloudServer.enableACME;
      acmeRoot = "/var/lib/acme/acme-challenge";
    }
    (lib.mkIf (!config.nextcloudServer.enableACME) (
      let
        selfSignedCert = pkgs.runCommand "nextcloud-selfsigned-cert"
          {
            buildInputs = [ pkgs.openssl pkgs.coreutils ];
          } ''
            mkdir -p $out
            ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 \
              -nodes -subj "/CN=${fqdn}" \
              -keyout key.pem -out cert.pem
            install -Dm600 key.pem $out/key.pem
            install -Dm644 cert.pem $out/cert.pem
          '';
      in
      {
        sslCertificate = "${selfSignedCert}/cert.pem";
        sslCertificateKey = "${selfSignedCert}/key.pem";
      }
    ))
  ];

  services.mysql.package = pkgs.mariadb;
  services.mysql.settings.mysqld = {
    innodb_file_per_table = 1;
    innodb_buffer_pool_size = "1G";
    character-set-server = "utf8mb4";
    collation-server = "utf8mb4_unicode_ci";
  };

  environment.etc."nextcloud/restic-password.example".text = ''
    Store the Restic repository password here when backups are configured.
    Replace this file by copying it to /var/lib/nextcloud/secrets/restic-password
    and tighten its permissions to 600 owned by root.
  '';

  nextcloudServer = {
    fqdn = "cloud.example.com";
    adminUser = "ncadmin";
    adminPassFile = "/var/lib/nextcloud/secrets/admin-password";
    enableACME = false;
    acmeEmail = "admin@example.com";
    trustedProxies = [ ];
  };

  system.stateVersion = "24.05";
}
