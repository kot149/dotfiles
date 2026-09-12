{ pkgs, ... }:

{
  home.packages = with pkgs; [
    xcodes
    ghostty-bin
    goku
    maccy
    mos
  ];

  localAllowUnfree.packages = [
    "mos"
  ];
}
