{ pkgs, ... }:

{
  home.packages = with pkgs; [
  ];

  programs.gnome-terminal.enable = true;

  programs.gnome-terminal.profile."b19a5eec-d2dc-43d7-b4e5-c4f8c183fd34" = {
    default = true;
    visibleName = "default";
    customCommand = "${pkgs.zsh}/bin/zsh";
    loginShell = true;
  };
}
