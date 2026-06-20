{ config, lib, pkgs, ... }:

{
  wsl.enable = true;
  wsl.defaultUser = "nixos";
  wsl.wslConf.network.generateResolvConf = false;
  wsl.wslConf.network.generateHosts = false;

  networking.nameservers = [ "8.8.8.8" "8.8.4.4" ];
  networking.extraHosts = ''
    140.82.121.4 github.com-kot149
  '';

  environment.etc."resolv.conf".text = ''
    nameserver 8.8.8.8
    nameserver 8.8.4.4
  '';
}
