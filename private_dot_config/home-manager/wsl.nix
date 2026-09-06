{ config, lib, pkgs, ... }:

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
in
{
  home.packages = [ ghosttyWrapped ];

  home.file.".config/tailscale/tailscaled.service.d/wsl.conf".text = ''
    [Service]
    Environment=PORT=0
    Environment=FLAGS=
  '';

  home.activation.tailscaled = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    service="$(readlink -f "${config.home.profileDirectory}/lib/systemd/system/tailscaled.service")"
    if [ ! -f "$service" ]; then
      exit 0
    fi

    target=/etc/systemd/system/tailscaled.service
    dropin_dir=/etc/systemd/system/tailscaled.service.d
    dropin="$dropin_dir/wsl.conf"
    override="${config.home.homeDirectory}/.config/tailscale/tailscaled.service.d/wsl.conf"
    if ! cmp -s "$override" "$dropin" 2>/dev/null; then
      /usr/bin/sudo /usr/bin/mkdir -p "$dropin_dir"
      /usr/bin/sudo /usr/bin/install -m 0644 "$override" "$dropin"
      /usr/bin/sudo /usr/bin/systemctl daemon-reload
    fi

    current="$(readlink -f "$target" 2>/dev/null || true)"
    if [ "$current" != "$service" ]; then
      if [ -e "$target" ] && [ ! -L "$target" ]; then
        echo "$target already exists and is not a symlink" >&2
        exit 1
      fi
      /usr/bin/sudo /usr/bin/ln -sfn "$service" "$target"
      /usr/bin/sudo /usr/bin/systemctl daemon-reload
      if /usr/bin/systemctl is-active --quiet tailscaled.service; then
        /usr/bin/sudo /usr/bin/systemctl restart tailscaled.service
      fi
    fi

    if ! /usr/bin/systemctl is-enabled --quiet tailscaled.service 2>/dev/null; then
      /usr/bin/sudo /usr/bin/systemctl enable tailscaled.service
    fi
    if ! /usr/bin/systemctl is-active --quiet tailscaled.service; then
      /usr/bin/sudo /usr/bin/systemctl start tailscaled.service
    fi
  '';

  programs.ghostty = {
    enable = true;
    package = ghosttyWrapped;
  };

  localAllowUnfree.packages = [
    # list extra unfree package names here (matched via lib.getName)
  ];
}
