{ lib
, stdenv
, fetchurl
, makeWrapper
, autoPatchelfHook
, alsa-lib
, at-spi2-atk
, at-spi2-core
, atk
, cairo
, cups
, dbus
, expat
, glib
, gtk3
, libdrm
, libgbm
, libxkbcommon
, nspr
, nss
, pango
, systemd
, xorg
}:

# Not in nixpkgs; upstream ships prebuilt tarballs only (Electron runtime is
# vendored inside, so a source build is not practical).
# Bumping the version requires refreshing every hash below.
let
  version = "0.5.8";

  sources = {
    aarch64-darwin = {
      platform = "darwin-arm64";
      hash = "sha256-e/cKG6NyxBU905qHdvsOyy12YKnNgk9v27jlU1gApyw=";
    };
    aarch64-linux = {
      platform = "linux-arm64";
      hash = "sha256-n/5/wfKjCe0L5IwvNfulNPOBY9ZMIsDH3FOZSdTxnnE=";
    };
    x86_64-linux = {
      platform = "linux-x64";
      hash = "sha256-wzC+M0Hvb2yxBuT7MsHWB1Sgjhp2QRQ6empNnpRI9hc=";
    };
  };

  source = sources.${stdenv.hostPlatform.system}
    or (throw "terminal-browser: unsupported platform ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation {
  pname = "terminal-browser";
  inherit version;

  src = fetchurl {
    url = "https://github.com/zenbu-labs/terminal-browser/releases/download/v${version}/terminal-browser-${source.platform}.tar.gz";
    inherit (source) hash;
  };

  sourceRoot = "terminal-browser";

  nativeBuildInputs = [ makeWrapper ] ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    glib
    gtk3
    libdrm
    libgbm
    libxkbcommon
    nspr
    nss
    pango
    (lib.getLib systemd)
    xorg.libX11
    xorg.libXcomposite
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXrandr
    xorg.libxcb
  ];

  # The vendored Electron keeps its own rpath-less layout; patching the ELF
  # interpreter is enough, and stripping breaks the ASAR-adjacent binaries.
  dontStrip = true;
  autoPatchelfIgnoreMissingDeps = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp -R . "$out/lib/terminal-browser"

    # The shipped launcher resolves its dist root from $0, so it has to be
    # invoked through its real path rather than a symlink from $out/bin.
    makeWrapper "$out/lib/terminal-browser/bin/terminal-browser" "$out/bin/terminal-browser"

    runHook postInstall
  '';

  meta = {
    description = "A browser that runs directly inside your existing terminal";
    homepage = "https://github.com/zenbu-labs/terminal-browser";
    license = lib.licenses.mit;
    mainProgram = "terminal-browser";
    platforms = builtins.attrNames sources;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
