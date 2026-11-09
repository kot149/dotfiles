{ pkgs, ... }:

# Resolve .local names: the WSL DNS tunnel does not answer mDNS queries for other hosts.
let
  avahiConf = pkgs.writeText "avahi-daemon.conf" ''
    [server]
    use-ipv4=yes
    use-ipv6=yes
    enable-dbus=no

    [publish]
    # Mirrored networking shares the Windows hostname and addresses, and Windows already answers for them
    disable-publishing=yes
  '';
in
{
  systemd.services.avahi-daemon = {
    description = "Avahi mDNS/DNS-SD Stack";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.avahi}/bin/avahi-daemon --no-rlimits --no-drop-root -f ${avahiConf}";
      RuntimeDirectory = "avahi-daemon";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # Distro glibc loads NSS modules through ld.so.cache, so register nss-mdns there
  environment.etc."ld.so.conf.d/system-manager-nss-mdns.conf".text = ''
    ${pkgs.nssmdns}/lib
  '';

  systemd.services.nss-mdns-ldconfig = {
    description = "Refresh ld.so.cache for nss-mdns";
    wantedBy = [ "multi-user.target" ];
    restartTriggers = [ pkgs.nssmdns ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "/usr/sbin/ldconfig";
    };
  };
}
