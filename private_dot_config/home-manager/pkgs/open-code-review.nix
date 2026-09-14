{ lib, buildGoModule, fetchFromGitHub, git }:

# Not in nixpkgs; upstream ships an npm wrapper and release binaries only.
# Bumping the version requires refreshing both hashes below.
buildGoModule (finalAttrs: {
  pname = "open-code-review";
  version = "1.12.0";

  src = fetchFromGitHub {
    owner = "alibaba";
    repo = "open-code-review";
    tag = "v${finalAttrs.version}";
    hash = "sha256-nPi3sTgh3dyJnaEiP6UqCVl6xUUTThl3SLol+NjrPx4=";
  };

  vendorHash = "sha256-f5Ty22wicf1J8+RKnHYcEO7flWn9gkWQODlfunn23EA=";

  subPackages = [ "cmd/opencodereview" ];

  # The CLI tests shell out to git.
  nativeCheckInputs = [ git ];

  ldflags = [
    "-s"
    "-w"
    "-X main.Version=v${finalAttrs.version}"
  ];

  postInstall = ''
    mv $out/bin/opencodereview $out/bin/ocr
  '';

  meta = {
    description = "AI code review agent that reviews Git diffs and emits line-level comments";
    homepage = "https://github.com/alibaba/open-code-review";
    license = lib.licenses.asl20;
    mainProgram = "ocr";
  };
})
