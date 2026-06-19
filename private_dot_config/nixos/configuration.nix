{ config, lib, pkgs, ... }:

{
  imports = [
    <nixos-wsl/modules>
  ];

  wsl.enable = true;
  wsl.defaultUser = "nixos";
  wsl.wslConf.network.generateResolvConf = false;
  wsl.wslConf.network.generateHosts = false;

  networking.nameservers = [ "8.8.8.8" "8.8.4.4" ];
  networking.extraHosts = ''
    140.82.121.4 github.com-kot149
  '';

  programs.zsh.enable = true;
  users.users.nixos.shell = pkgs.zsh;

  system.stateVersion = "25.11";
  programs.nix-ld.enable = true;
}
