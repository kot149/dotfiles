{ lib, buildGoModule, fetchFromGitHub }:

# Not in nixpkgs; upstream ships Docker/binaries only.
# Bumping the version requires refreshing both hashes below.
buildGoModule (finalAttrs: {
  pname = "cli-proxy-api";
  version = "7.2.127";

  src = fetchFromGitHub {
    owner = "router-for-me";
    repo = "CLIProxyAPI";
    tag = "v${finalAttrs.version}";
    hash = "sha256-gVy/bErDmZnKrbp4CwMBjFqIhdLGmqVN34bTF2gqWmQ=";
  };

  vendorHash = "sha256-CrDp7MOr+AwJUhTovklXx3F1yaktQlvD7VYhYSY6VvY=";

  subPackages = [ "cmd/server" ];

  ldflags = [
    "-s"
    "-w"
    "-X main.Version=${finalAttrs.version}"
  ];

  postInstall = ''
    mv $out/bin/server $out/bin/cli-proxy-api
  '';

  meta = {
    description = "OpenAI/Gemini/Claude/Codex compatible API proxy for AI CLI tools";
    homepage = "https://github.com/router-for-me/CLIProxyAPI";
    license = lib.licenses.mit;
    mainProgram = "cli-proxy-api";
  };
})
