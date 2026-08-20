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
  version = "0.1.13";

  sources = {
    aarch64-darwin = {
      platform = "darwin-arm64";
      hash = "sha256-n9BGqsOYFqE4S+BFKmTofPPTqqLp00jsddvzdbDtd7s=";
    };
    aarch64-linux = {
      platform = "linux-arm64";
      hash = "sha256-cbyY6Ul7XzA9spHFcRf82BEktefMW/YbCwzMn2geROs=";
    };
    x86_64-linux = {
      platform = "linux-x64";
      hash = "sha256-zMKgw6nCV/xCztd+bxtM5SugzBxFKaYB9lV6Uku00XM=";
    };
  };

  source = sources.${stdenv.hostPlatform.system}
    or (throw "tode: unsupported platform ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation {
  pname = "tode";
  inherit version;

  src = fetchurl {
    url = "https://github.com/zenbu-labs/terminal-code/releases/download/v${version}/tode-${source.platform}.tar.gz";
    inherit (source) hash;
  };

  sourceRoot = "tode";

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
    cp -R . "$out/lib/tode"

    browser="$out/lib/tode/vendor/terminal-browser"
    install -m 0755 ${./tode-launcher.sh} "$browser/bin/terminal-browser"

    makeWrapper "$out/lib/tode/bin/tode" "$out/bin/tode" \
      --set TODE_INSTALL_ROOT "$out/lib/tode" \
      --set TODE_TERMINAL_BROWSER_BIN "$browser/bin/terminal-browser"

    runHook postInstall
  '';

  meta = {
    description = "VS Code in the terminal";
    homepage = "https://github.com/zenbu-labs/terminal-code";
    license = lib.licenses.mit;
    mainProgram = "tode";
    platforms = builtins.attrNames sources;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
