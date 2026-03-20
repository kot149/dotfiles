{ pkgs, ... }:

{
  fonts.fontconfig.enable = true;

  home.packages = with pkgs; [
    nerd-fonts.inconsolata
  ];

  programs.gnome-terminal.enable = true;

  programs.gnome-terminal.profile."b19a5eec-d2dc-43d7-b4e5-c4f8c183fd34" = {
    default = true;
    visibleName = "default";
    customCommand = "${pkgs.zsh}/bin/zsh";
    loginShell = true;
    font = "Inconsolata Nerd Font Mono 13";
  };

  dconf.settings = {
    "org/gnome/terminal/legacy/profiles:/:b19a5eec-d2dc-43d7-b4e5-c4f8c183fd34" = {
      default-size-columns = 120;
      default-size-rows = 30;
    };
  };
}
