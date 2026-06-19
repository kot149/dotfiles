{ config, lib, pkgs, ... }:

let
  isWsl = builtins.pathExists <nixos-wsl/modules>;
in
{
  imports = lib.optionals isWsl [
    <nixos-wsl/modules>
    ./wsl.nix
  ];

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };

  networking.firewall.allowedUDPPorts = [ 5353 ];

  programs.zsh.enable = true;
  users.users.nixos.shell = pkgs.zsh;

  system.stateVersion = "25.11";
  programs.nix-ld.enable = true;
}
