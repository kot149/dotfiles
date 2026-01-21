{ pkgs, ... }:

{
  nixpkgs.config.allowUnfree = true;

  home.packages = with pkgs; [
    xcodes
    ghostty-bin
    maccy
    mos
  ];
}
