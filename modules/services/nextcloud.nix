{ config, lib, pkgs, ... }:
let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.nextcloudServer;
in
{
  options.nextcloudServer = {
    fqdn = mkOption {
      type = types.str;
      default = "cloud.example.com";
      example = "nextcloud.your-domain.tld";
      description = ''
        Fully-qualified domain name that clients use to reach the Nextcloud instance.
        Update this before deploying to production.
      '';
    };

    adminUser = mkOption {
      type = types.str;
      default = "ncadmin";
      description = "Name of the Nextcloud administrator account.";
    };

    adminPassFile = mkOption {
      type = types.path;
      default = "/var/lib/nextcloud/secrets/admin-password";
      description = ''
        Path to a file containing the Nextcloud administrator password.
        The file must exist on the target system with mode 600 and be owned by root.
      '';
    };

    defaultPhoneRegion = mkOption {
      type = types.str;
      default = "US";
      example = "DE";
      description = ''
        Default country code that Nextcloud should assume when users enter phone numbers
        without an explicit international prefix.
      '';
    };

    enableACME = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Request certificates from Let’s Encrypt using the built-in ACME client.
        Requires public DNS for the configured fqdn.
      '';
    };

    acmeEmail = mkOption {
      type = types.str;
      default = "admin@example.com";
      description = "Contact email address for ACME certificate registration.";
    };

    trustedProxies = mkOption {
      type = types.listOf types.str;
      default = [];
      example = [ "10.0.0.0/24" ];
      description = ''
        Optional CIDR blocks or addresses that should be trusted reverse proxies.
        Useful when placing the service behind a load balancer.
      '';
    };
  };

  config = {
    assertions = [
      {
        assertion = cfg.enableACME -> cfg.fqdn != "cloud.example.com";
        message = "Set nextcloudServer.fqdn to your domain before enabling ACME.";
      }
    ];

    services.nextcloud = {
      enable = true;
      package = pkgs.nextcloud29;
      hostName = cfg.fqdn;
      https = true;
      maxUploadSize = "32G";
      config = {
        adminuser = cfg.adminUser;
        adminpassFile = cfg.adminPassFile;
        dbtype = "mysql";
      };
      autoUpdateApps.enable = true;
      autoUpdateApps.startAt = "04:30";
      caching = {
        apcu = true;
        redis = true;
      };
      notify_push = {
        enable = true;
        bendDomainToLocalhost = true;
      };
      database = {
        createLocally = true;
      };
      settings = lib.mkMerge [
        {
          default_phone_region = cfg.defaultPhoneRegion;
          redis = {
            host = "/run/redis-nextcloud/redis.sock";
            port = 0;
            timeout = 1.5;
          };
          trusted_domains = [ cfg.fqdn ];
          overwriteprotocol = "https";
        }
        (mkIf (cfg.trustedProxies != []) { trusted_proxies = cfg.trustedProxies; })
      ];
      phpOptions = {
        "opcache.enable" = "1";
        "opcache.enable_cli" = "1";
        "opcache.interned_strings_buffer" = "16";
        "opcache.max_accelerated_files" = "10000";
        "opcache.memory_consumption" = "192";
        "opcache.save_comments" = "1";
        "opcache.revalidate_freq" = "2";
        "pm.max_children" = "32";
        "upload_max_filesize" = "32G";
        "post_max_size" = "32G";
      };
    };

    services.nginx = {
      enable = true;
      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;
    };

    security.acme = {
      acceptTerms = true;
      defaults.email = cfg.acmeEmail;
    };

    services.redis.servers.nextcloud = {
      enable = true;
      user = "nextcloud";
      unixSocket = "/run/redis-nextcloud/redis.sock";
      unixSocketPerm = 770;
    };

    systemd.services."redis-nextcloud".after = [ "network.target" ];

    systemd.tmpfiles.rules = [
      "d /var/lib/nextcloud 0750 nextcloud nextcloud -"
      "d /var/lib/nextcloud/secrets 0700 root root -"
      "d /var/lib/nextcloud/data 0750 nextcloud nextcloud -"
    ];

    environment.etc."nextcloud/admin-password.example".text = ''
      Replace this file by copying it to ${cfg.adminPassFile} on the target system,
      then write a secure password into the new file and restrict its permissions:

        sudo install -m 600 -o root -g root /etc/nextcloud/admin-password.example ${cfg.adminPassFile}
        sudo nano ${cfg.adminPassFile}

      Remove the example file afterwards.
    '';

    environment.etc."nextcloud/admin-password-hash.example".text = ''
      Copy this file to /var/lib/nextcloud/secrets/admin-password-hash and replace its
      contents with a SHA-512 password hash for the `admin` system account:

        sudo install -m 600 -o root -g root /etc/nextcloud/admin-password-hash.example /var/lib/nextcloud/secrets/admin-password-hash
        mkpasswd -m sha-512

      Paste the generated hash into the new file and save. The unattended ISO run populates
      this hash automatically and drops the cleartext password into /root/INSTALL-INFO.txt.
    '';

  };
}
