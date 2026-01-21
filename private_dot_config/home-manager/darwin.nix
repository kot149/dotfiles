{ pkgs, ... }:

{
  home.packages = with pkgs; [
    xcodes
    ghostty
    mos
  ];
}
