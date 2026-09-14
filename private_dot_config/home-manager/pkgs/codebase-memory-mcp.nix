{ lib, stdenv, fetchFromGitHub, gnumake, zlib }:

# Not in nixpkgs. Build phases mirror the flake.nix upstream ships; bumping the
# version requires refreshing the hash below.
stdenv.mkDerivation (finalAttrs: {
  pname = "codebase-memory-mcp";
  version = "0.10.8";

  src = fetchFromGitHub {
    owner = "DeusData";
    repo = "codebase-memory-mcp";
    tag = "v${finalAttrs.version}";
    hash = "sha256-lPuayLN6W31zQ45UTQehP+tmoo/UrQJuRsJzi1wZ9Tg=";
  };

  nativeBuildInputs = [ gnumake ];
  buildInputs = [ zlib ];

  # scripts/build.sh verifies the compiler with `file`, which fails on Nix
  # because CC is a bash wrapper. Call make directly; the stdenv already
  # guarantees the right compiler and target architecture.
  buildPhase = ''
    runHook preBuild
    make -j$NIX_BUILD_CORES -f Makefile.cbm cbm
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 build/c/codebase-memory-mcp $out/bin/codebase-memory-mcp
    runHook postInstall
  '';

  meta = {
    description = "MCP server that builds and queries a semantic graph of your codebase";
    homepage = "https://github.com/DeusData/codebase-memory-mcp";
    license = lib.licenses.mit;
    mainProgram = "codebase-memory-mcp";
  };
})
