{ pkgs, ... }:

{
  fonts.fontconfig.enable = true;

  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      addons = with pkgs; [ fcitx5-mozc ];
      waylandFrontend = true;
      settings.globalOptions = {
        "Hotkey/TriggerKeys"."0" = "Control+space";
        "Hotkey/ActivateKeys"."0" = "Hangul";
        "Hotkey/DeactivateKeys"."0" = "Hanja";
      };
      settings.inputMethod = {
        GroupOrder."0" = "Default";
        "Groups/0" = {
          Name = "Default";
          "Default Layout" = "us";
          DefaultIM = "mozc";
        };
        "Groups/0/Items/0".Name = "keyboard-us";
        "Groups/0/Items/1".Name = "mozc";
      };
    };
  };

  gtk.enable = true;

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
