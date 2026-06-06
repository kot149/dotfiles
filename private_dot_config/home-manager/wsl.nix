{ lib, pkgs, username, ... }:

let
  nixGlSrc = pkgs.fetchFromGitHub {
    owner = "nix-community";
    repo = "nixGL";
    rev = "b6105297e6f0cd041670c3e8628394d4ee247ed5";
    sha256 = "sha256-fbRQzIGPkjZa83MowjbD2ALaJf9y6KMDdJBQMKFeY/8=";
  };
  nixGl = import nixGlSrc {
    pkgs = pkgs;
    enable32bits = false;
    enableIntelX86Extensions = pkgs.stdenv.isLinux && pkgs.stdenv.isx86_64;
  };
  ghosttyWrapped = pkgs.writeShellScriptBin "ghostty" ''
    exec ${nixGl.nixGLIntel}/bin/nixGLIntel ${pkgs.ghostty}/bin/ghostty "$@"
  '';
  nssLibDir = "/usr/lib/x86_64-linux-gnu";
  avahiConf = pkgs.writeText "avahi-daemon.conf" ''
    [server]
    use-ipv4=yes
    use-ipv6=yes
    allow-interfaces=eth0
    deny-interfaces=
    ratelimit-interval-usec=1000000
    ratelimit-burst=1000

    [wide-area]
    enable-wide-area=yes

    [publish]
    publish-hinfo=no
    publish-workstation=no

    [reflector]

    [rlimits]
  '';
  avahiDbusConf = pkgs.writeText "avahi-dbus.conf" ''
    <!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
      "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
    <busconfig>
      <policy user="avahi">
        <allow own="org.freedesktop.Avahi"/>
        <allow send_destination="org.freedesktop.Avahi"/>
        <allow receive_sender="org.freedesktop.Avahi"/>
      </policy>
      <policy context="default">
        <allow send_destination="org.freedesktop.Avahi"/>
        <allow receive_sender="org.freedesktop.Avahi"/>
      </policy>
    </busconfig>
  '';
  avahiServiceUnit = pkgs.writeText "avahi-daemon.service" ''
    [Unit]
    Description=Avahi mDNS/DNS-SD Stack
    After=network.target

    [Service]
    ExecStart=${pkgs.avahi}/bin/avahi-daemon --no-rlimits -s -f ${avahiConf}
    Restart=on-failure
    RestartSec=5

    [Install]
    WantedBy=multi-user.target
  '';
in
{
  home.packages = [
    ghosttyWrapped
    pkgs.avahi
    pkgs.nssmdns
  ];

  programs.ghostty = {
    enable = true;
    package = ghosttyWrapped;
  };

  home.activation.setupMdns = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if ! /usr/bin/getent group avahi >/dev/null 2>&1; then
      $DRY_RUN_CMD /usr/bin/sudo groupadd --system avahi
    fi
    if ! /usr/bin/id -u avahi >/dev/null 2>&1; then
      $DRY_RUN_CMD /usr/bin/sudo useradd --system --no-create-home --shell /usr/sbin/nologin -g avahi avahi
    fi
    $DRY_RUN_CMD /usr/bin/sudo cp -f ${avahiDbusConf} /etc/dbus-1/system.d/avahi-dbus.conf
    $DRY_RUN_CMD /usr/bin/sudo systemctl reload dbus 2>/dev/null || true
    $DRY_RUN_CMD /usr/bin/sudo cp -f ${avahiServiceUnit} /etc/systemd/system/avahi-daemon.service
    $DRY_RUN_CMD /usr/bin/sudo systemctl daemon-reload
    $DRY_RUN_CMD /usr/bin/sudo systemctl enable --now avahi-daemon
    for f in ${pkgs.nssmdns}/lib/libnss_mdns*.so.2; do
      name=$(/usr/bin/basename "$f")
      if [ ! -L "${nssLibDir}/$name" ] || [ "$(/usr/bin/readlink -f "${nssLibDir}/$name")" != "$(/usr/bin/readlink -f "$f")" ]; then
        $DRY_RUN_CMD /usr/bin/sudo ln -sf "$f" "${nssLibDir}/$name"
      fi
    done
    if ! /usr/bin/grep -q 'mdns_minimal' /etc/nsswitch.conf 2>/dev/null; then
      $DRY_RUN_CMD /usr/bin/sudo sed -i 's/^hosts:.*/hosts:          files mdns_minimal [NOTFOUND=return] dns/' /etc/nsswitch.conf
    fi
  '';

  # .wslconfig (Windows側) に以下の設定が必要:
  #   [wsl2]
  #   dnsTunneling=false
  #   networkingMode=mirrored
}
