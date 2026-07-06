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
in
{
  home.packages = [ ghosttyWrapped ];

  programs.ghostty = {
    enable = true;
    package = ghosttyWrapped;
  };

  localAllowUnfree.packages = [
    # list extra unfree package names here (matched via lib.getName)
  ];
}
