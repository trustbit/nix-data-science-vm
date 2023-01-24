#!/bin/bash -xe

OS=`cat /etc/os-release | grep ID`
if [[ $OS == *"nixos"* ]]; then
  exit 0
fi
cat /tmp/metadata-scrip*/*  > /tmp/derscripten.sh
mkdir -p /etc/nixos /etc/profiles

cat <<'EOT' > /etc/nixos/nginx.nix
{ config, lib, pkgs, modulesPath, ... }:
{
  security.acme.acceptTerms = true;
  security.acme.defaults.email = "krasina15@gmail.com";
  networking.firewall.allowedTCPPorts = [ 22 80 443 ];
  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    virtualHosts."${domain_name}" =  {
      basicAuth = {
        user = "!changeme";
      };
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:3000";
        proxyWebsockets = true;
      };
    };
  };
}
EOT

cat <<'EOT' > /etc/nixos/workspace.nix
{ config, lib, pkgs, modulesPath, ... }:
let
  home-manager = builtins.fetchTarball "https://github.com/nix-community/home-manager/archive/master.tar.gz";
in
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  imports = [
    (import "$${home-manager}/nixos")
    ./nginx.nix
    ./google.nix
  ];
#  services.openssh.enable = true;
  services.openssh.enable = true;
#  services.openssh.settings.PermitRootLogin = "prohibit-password";
#  services.openssh.settings.PasswordAuthentication = false;
  virtualisation.docker.enable = true;
  environment.systemPackages = with pkgs; [
    openvscode-server
    direnv
    nix-direnv
    home-manager
    google-cloud-sdk
    neovim
    git
  ];
  users.users.openvscode = {
    group = "openvscode";
    isNormalUser  = true;
    home  = "/data";
    description  = "openvscode default user";
    extraGroups  = [ "wheel" "docker" ];
  };
  users.groups.openvscode = { };
  home-manager.users.openvscode = {
    home.stateVersion = "22.11";
    home.homeDirectory = "/data";
    programs.home-manager.enable = true;
    programs.direnv = {
      enable = true;
      enableBashIntegration = true;
      nix-direnv.enable = true;
    };
    programs.bash = {
      enable = true;
      shellOptions = [];
      historyControl = [ "ignoredups" "ignorespace" ];
      initExtra = builtins.readFile ./bashrc;
      shellAliases = {
        vim = "nvim";
      };
    };
  };
  security.sudo.extraRules= [
    {  users = [ "openvscode" ];
      commands = [
         { command = "ALL" ;
           options= [ "NOPASSWD" ];
        }
      ];
    }
  ];
  systemd.services.code-server = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      ExecStart = "$${pkgs.openvscode-server}/bin/openvscode-server --host 127.0.0.1 --port 3000 --without-connection-token";
      Restart = "always";
      User = "openvscode";
      Group = "openvscode";
    };
  };
}
EOT

cat <<'EOT' > /etc/nixos/google.nix
{ config, lib, pkgs, ... }:
with lib;
{
  imports = [
    ./headless.nix
    ./qemu-guest.nix
  ];

#  fileSystems."/" = {
#    fsType = "ext4";
#    device = "/dev/disk/by-label/nixos";
#    autoResize = true;
#  };

  boot.growPartition = true;
  boot.kernelParams = [ "console=ttyS0" "panic=1" "boot.panic_on_fail" ];
  boot.initrd.kernelModules = [ "virtio_scsi" ];
  boot.kernelModules = [ "virtio_pci" "virtio_net" ];

  # Generate a GRUB menu.
#  boot.loader.grub.device = "/dev/sda";
  boot.loader.timeout = 0;

  # Don't put old configurations in the GRUB menu.  The user has no
  # way to select them anyway.
  boot.loader.grub.configurationLimit = 0;

  # Allow root logins only using SSH keys
  # and disable password authentication in general
#  services.openssh.enable = true;
#  services.openssh.settings.PermitRootLogin = "prohibit-password";
#  services.openssh.settings.PasswordAuthentication = false;

  # enable OS Login. This also requires setting enable-oslogin=TRUE metadata on
  # instance or project level
  security.googleOsLogin.enable = true;

  # Use GCE udev rules for dynamic disk volumes
  services.udev.packages = [ pkgs.google-guest-configs ];
  services.udev.path = [ pkgs.google-guest-configs ];

  # Force getting the hostname from Google Compute.
  # networking.hostName = "";

  # Always include cryptsetup so that NixOps can use it.
  environment.systemPackages = [ pkgs.cryptsetup ];

  # Rely on GCP's firewall instead
  networking.firewall.enable = false;

  # Configure default metadata hostnames
  networking.extraHosts = ''
    169.254.169.254 metadata.google.internal metadata
  '';

  networking.timeServers = [ "metadata.google.internal" ];

  networking.usePredictableInterfaceNames = false;

  # GC has 1460 MTU
  networking.interfaces.eth0.mtu = 1460;

  systemd.packages = [ pkgs.google-guest-agent ];
  systemd.services.google-guest-agent = {
    wantedBy = [ "multi-user.target" ];
    restartTriggers = [ config.environment.etc."default/instance_configs.cfg".source ];
    path = lib.optional config.users.mutableUsers pkgs.shadow;
  };
  systemd.services.google-startup-scripts.wantedBy = [ "multi-user.target" ];
  systemd.services.google-shutdown-scripts.wantedBy = [ "multi-user.target" ];

  security.sudo.extraRules = mkIf config.users.mutableUsers [
    { groups = [ "google-sudoers" ]; commands = [ { command = "ALL"; options = [ "NOPASSWD" ]; } ]; }
  ];

  users.groups.google-sudoers = mkIf config.users.mutableUsers { };

  boot.extraModprobeConfig = lib.readFile "$${pkgs.google-guest-configs}/etc/modprobe.d/gce-blacklist.conf";

  environment.etc."sysctl.d/60-gce-network-security.conf".source = "$${pkgs.google-guest-configs}/etc/sysctl.d/60-gce-network-security.conf";

  environment.etc."default/instance_configs.cfg".text = ''
    [Accounts]
    useradd_cmd = useradd -m -s /run/current-system/sw/bin/bash -p * {user}
    [Daemons]
    accounts_daemon = $${boolToString config.users.mutableUsers}
    [InstanceSetup]
    # Make sure GCE image does not replace host key that NixOps sets.
    set_host_keys = false
    [MetadataScripts]
    default_shell = $${pkgs.stdenv.shell}
    [NetworkInterfaces]
    dhclient_script = $${pkgs.google-guest-configs}/bin/google-dhclient-script
    # We set up network interfaces declaratively.
    setup = false
  '';
}
EOT



curl https://raw.githubusercontent.com/mitchellh/nixos-config/main/users/mitchellh/bashrc -o /etc/nixos/bashrc
curl https://raw.githubusercontent.com/NixOS/nixpkgs/master/nixos/modules/profiles/headless.nix -o /etc/nixos/headless.nix
curl https://raw.githubusercontent.com/NixOS/nixpkgs/master/nixos/modules/profiles/qemu-guest.nix -o /etc/nixos/qemu-guest.nix

chmod 0644 /etc/nixos/*.nix
curl https://raw.githubusercontent.com/elitak/nixos-infect/master/nixos-infect | NIXOS_IMPORT=./workspace.nix NIX_CHANNEL=nixos-22.11 bash 2>&1 | tee /tmp/infect.log