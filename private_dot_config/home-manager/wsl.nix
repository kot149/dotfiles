{ pkgs, ... }:

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
  dockerCompat = pkgs.writeShellScriptBin "docker" ''
    if [ -z "$CONTAINER_HOST" ]; then
      if [ -S /mnt/wsl/podman-sockets/podman-machine-default/podman-root.sock ]; then
        export CONTAINER_HOST="unix:///mnt/wsl/podman-sockets/podman-machine-default/podman-root.sock"
      elif [ -S /mnt/wsl/podman-sockets/podman-machine-default/podman-user.sock ]; then
        export CONTAINER_HOST="unix:///mnt/wsl/podman-sockets/podman-machine-default/podman-user.sock"
      fi
    fi
    args=()
    for arg in "$@"; do
      args+=("''${arg//\/home\//\/mnt\/wsl\/home\/}")
    done
    exec ${pkgs.podman}/bin/podman "''${args[@]}"
  '';

  podmanCompat = pkgs.writeShellScriptBin "podman" ''
    if [ -z "$CONTAINER_HOST" ]; then
      if [ -S /mnt/wsl/podman-sockets/podman-machine-default/podman-root.sock ]; then
        export CONTAINER_HOST="unix:///mnt/wsl/podman-sockets/podman-machine-default/podman-root.sock"
      elif [ -S /mnt/wsl/podman-sockets/podman-machine-default/podman-user.sock ]; then
        export CONTAINER_HOST="unix:///mnt/wsl/podman-sockets/podman-machine-default/podman-user.sock"
      fi
    fi
    args=()
    for arg in "$@"; do
      args+=("''${arg//\/home\//\/mnt\/wsl\/home\/}")
    done
    exec ${pkgs.podman}/bin/podman "''${args[@]}"
  '';
in
{
  home.packages = [ ghosttyWrapped dockerCompat podmanCompat ];

  programs.ghostty = {
    enable = true;
    package = ghosttyWrapped;
  };
}
