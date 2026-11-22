{ nix-jetbrains-plugins, isNixOS }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.intellij;

  baseNixLdLibraries = with pkgs; [
    stdenv.cc.cc.lib
    glibc
    zlib
    systemd
    ncurses5

    # Compression, system, and network utilities
    bzip2
    curl
    expat
    libxml2
    openssl
    util-linux
    e2fsprogs

    # Graphics & hardware rendering (host GPU / Vulkan / Direct Rendering)
    libGL
    libglvnd
    vulkan-loader
    mesa
    libgbm
    libdrm
    libva
    pciutils
    libepoxy

    # Image codecs (prevents emulator QEMU crashes)
    libpng
    libjpeg
    libwebp

    # BSD compatibility
    libbsd

    # Audio output (needed for emulator guest sound)
    alsa-lib
    libpulseaudio

    # X11 Session Management & Core X11 client libraries
    libsm
    libice
    libx11
    libxcb
    libxcomposite
    libxcursor
    libxdamage
    libxext
    libxfixes
    libxi
    libxinerama
    libxrandr
    libxrender
    libxtst
    libxshmfence

    # Qt 6.5+ XCB utility plugins (resolves GUI startup aborts)
    libxcb-cursor
    libxcb-image
    libxcb-keysyms
    libxcb-render-util
    libxcb-wm

    # Keyboard & Wayland handling (needed by Qt and Flutter)
    libxkbcommon
    libxkbfile
    wayland

    # Desktop integration, GTK3 & font rendering (required for Flutter engine)
    gtk3
    glib
    cairo
    pango
    atk
    gdk-pixbuf
    harfbuzz
    fontconfig
    freetype
    nspr
    nss
    dbus
    cups
  ];

  ecosystems = {
    rust = {
      plugins = [
        "com.intellij.nativeDebug"
        "com.jetbrains.rust"
      ];
      packages = [
        pkgs.rustup
        pkgs.stdenv.cc
        pkgs.pkg-config
      ];
      libraries = [ ];
      wrapperArgs = [ ];
    };
    android = {
      plugins = [
        "org.jetbrains.android"
        "com.android.tools.design"
      ];
      packages = [ ];
      libraries = with pkgs; [

      ];
      wrapperArgs = [ ''--set-default QT_XKB_CONFIG_ROOT "${pkgs.xkeyboard_config}/share/X11/xkb"'' ];
    };
    flutter = {
      plugins = [
        "Dart"
        "io.flutter"
      ];
      packages = [ cfg.flutter.package ];
      libraries = [ ];
      wrapperArgs = [ ''--set-default FLUTTER_ROOT "${cfg.flutter.sdkPath}"'' ];
    };
    go = {
      plugins = [
        "org.jetbrains.plugins.go"
        "org.jetbrains.plugins.go-template"
      ];
      packages = [
        pkgs.go
        pkgs.gopls
        pkgs.delve
        pkgs.stdenv.cc
      ];
      libraries = [ ];
      wrapperArgs = [ ''--set-default GOROOT "${pkgs.go}/share/go"'' ];
    };
    python = {
      plugins = [ "PythonCore" ] ++ lib.optionals (cfg.package.pname != "idea-oss") [ "Pythonid" ];
      packages = [
        (pkgs.python3.withPackages (ps: [
          ps.pip
          ps.setuptools
          ps.virtualenv
        ]))
        pkgs.uv
        pkgs.ruff
      ];
      libraries = with pkgs; [
        bzip2
        libffi
        sqlite
        xz
      ];
      wrapperArgs = [ ];
    };
    nix = {
      plugins = [
        "nix-idea"
        "io.github.salatmaster.direnv"
      ];
      packages = [
        pkgs.nix
        pkgs.direnv
        pkgs.nix-direnv
        pkgs.nixd
        pkgs.nil
        pkgs.nixfmt
      ];
      libraries = [ ];
      wrapperArgs = [ ];
    };
    scala = {
      plugins = [ "org.intellij.scala" ];
      packages = [
        pkgs.scala
        pkgs.sbt
      ];
      libraries = [ ];
      wrapperArgs = [ ];
    };
    zig = {
      plugins = [
        "com.redhat.devtools.lsp4ij"
        "com.falsepattern.zigbrains"
      ];
      packages = [
        pkgs.zig
        pkgs.zls
      ];
      libraries = [ ];
      wrapperArgs = [ ];
    };
    nodejs = {
      plugins = lib.optionals (cfg.package.pname != "idea-oss") [ "intellij.javascript.bun" ];
      packages = [
        pkgs.nodejs
        pkgs.bun
        pkgs.pnpm
        pkgs.yarn
      ];
      libraries = [ ];
      wrapperArgs = [ ];
    };
    php = {
      plugins = [ "com.jetbrains.php" ];
      packages = [
        pkgs.php
        pkgs.php.packages.composer
      ];
      libraries = [ ];
      wrapperArgs = [ ];
    };
    ruby = {
      plugins = [ "org.jetbrains.plugins.ruby" ];
      packages = [ pkgs.ruby ];
      libraries = [ ];
      wrapperArgs = [ ];
    };
  };

  enabledEcosystems = lib.filterAttrs (name: _: cfg.${name}.enable) ecosystems;
  collectFrom = field: lib.concatMap (spec: spec.${field}) (lib.attrValues enabledEcosystems);

  pluginIds = lib.unique ((collectFrom "plugins") ++ (builtins.filter builtins.isString cfg.plugins));
  pluginPackages = builtins.filter lib.isDerivation cfg.plugins;

  allPlugins = lib.unique (
    (lib.attrValues (nix-jetbrains-plugins.lib.pluginsForIde pkgs cfg.package pluginIds))
    ++ pluginPackages
  );

  ideWithPlugins =
    if allPlugins == [ ] then cfg.package else pkgs.jetbrains.plugins.addPlugins cfg.package allPlugins;

  runtimePackages = lib.unique ((collectFrom "packages") ++ cfg.extraPackages);
  runtimeLibraries = lib.unique (
    baseNixLdLibraries ++ (collectFrom "libraries") ++ cfg.extraLibraries
  );

  caBundle = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

  # Upstream nixpkgs defaults JAVA_HOME/ANDROID_JAVA_HOME to IDEA's bundled JBR 25 (`25.0.5.0.3`),
  # which crashes Gradle <= 8.14 Kotlin DSL; IDEA itself runs on IDEA_JDK.
  wrapperArgs = [
    ''--set-default SSL_CERT_FILE "${caBundle}"''
    ''--set-default NIX_SSL_CERT_FILE "${caBundle}"''
    ''--set-default JAVA_HOME "${pkgs.jdk21.home}"''
    ''--set-default JDK_HOME "${pkgs.jdk21.home}"''
    ''--set-default ANDROID_JAVA_HOME "${pkgs.jdk21.home}"''
  ]
  ++ (lib.optional (runtimePackages != [ ]) ''--suffix PATH : "${lib.makeBinPath runtimePackages}"'')
  ++ (lib.optional (
    runtimeLibraries != [ ]
  ) ''--suffix NIX_LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibraries}"'')
  ++ (collectFrom "wrapperArgs");

  mainProgram = cfg.package.meta.mainProgram or "idea";

  wrappedIde =
    if wrapperArgs == [ ] then
      ideWithPlugins
    else
      pkgs.symlinkJoin {
        name = "${ideWithPlugins.pname}-${ideWithPlugins.version}";
        paths = [ ideWithPlugins ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          rm -f "$out/bin/${mainProgram}"
          makeWrapper "${ideWithPlugins}/bin/${mainProgram}" "$out/bin/${mainProgram}" \
            ${lib.concatStringsSep " \\\n  " wrapperArgs}
        '';
        inherit (ideWithPlugins) meta passthru;
      };

  # Real directory with top-level symlinks so IDEA canonicalization does not resolve sdkPath back into /nix/store.
  # shortcut: SDK files symlink into /nix/store so `flutter upgrade` cannot mutate them, bump flake inputs instead.
  flutterSdkLinkScript = ''
    mkdir -p ${lib.escapeShellArg cfg.flutter.sdkPath}
    find ${lib.escapeShellArg cfg.flutter.sdkPath} -maxdepth 1 -type l -delete
    ln -sfn ${lib.escapeShellArg "${cfg.flutter.package}"}/* ${lib.escapeShellArg cfg.flutter.sdkPath}/
    if [ -e ${lib.escapeShellArg "${cfg.flutter.package}/.git"} ]; then
      ln -sfn ${lib.escapeShellArg "${cfg.flutter.package}/.git"} ${lib.escapeShellArg "${cfg.flutter.sdkPath}/.git"}
    fi
  '';
in
{
  options.programs.intellij = {
    enable = lib.mkEnableOption "IntelliJ IDEA with nix-jetbrains-plugins and scoped toolchains";

    package = lib.mkPackageOption pkgs [ "jetbrains" "idea" ] {
      extraDescription = "Set to `pkgs.jetbrains.idea-oss` for the pure open-source build.";
    };

    finalPackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      description = "Resulting wrapped IntelliJ IDEA package.";
    };

    plugins = lib.mkOption {
      type = lib.types.listOf (lib.types.either lib.types.str lib.types.package);
      default = [ ];
      example = lib.literalExpression ''[ "IdeaVIM" "com.intellij.plugins.watcher" ]'';
      description = ''
        Extra plugins to install, specified either as JetBrains Marketplace plugin ID strings
        resolved via `nix-jetbrains-plugins` or as plugin derivations compatible with
        `pkgs.jetbrains.plugins.addPlugins`.
      '';
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Additional packages appended to IntelliJ IDEA's runtime PATH.";
    };

    extraLibraries = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Additional dynamic libraries added to nix-ld and IntelliJ IDEA's NIX_LD_LIBRARY_PATH.";
    };
  }
  // lib.mapAttrs (
    name: _:
    {
      enable = lib.mkEnableOption "${name} plugin and runtime support in IntelliJ IDEA";
    }
    // lib.optionalAttrs (name == "flutter") {
      package = lib.mkPackageOption pkgs "flutter" { };
      sdkPath = lib.mkOption {
        type = lib.types.str;
        default = if isNixOS then "/var/lib/flutter-sdk" else "${config.xdg.dataHome}/flutter-sdk";
        defaultText = lib.literalExpression ''if isNixOS then "/var/lib/flutter-sdk" else "''${config.xdg.dataHome}/flutter-sdk"'';
        description = "Stable non-Nix-store directory path containing the Flutter SDK for IntelliJ IDEA.";
      };
    }
  ) ecosystems;

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        programs.intellij.finalPackage = wrappedIde;

        programs.direnv = lib.mkIf cfg.nix.enable {
          enable = lib.mkDefault true;
          nix-direnv.enable = lib.mkDefault true;
        };
      }
      (lib.optionalAttrs isNixOS {
        environment.systemPackages = [ cfg.finalPackage ];

        programs.nix-ld = {
          enable = lib.mkDefault true;
          libraries = runtimeLibraries;
        };

        system.activationScripts.intellij-flutter-sdk = lib.mkIf cfg.flutter.enable {
          text = flutterSdkLinkScript;
        };
      })
      (lib.optionalAttrs (!isNixOS) {
        # shortcut: standalone Home Manager cannot enable system nix-ld shim, enable `programs.nix-ld.enable = true` on host NixOS so NIX_LD_LIBRARY_PATH takes effect.
        home.packages = [ cfg.finalPackage ];

        home.activation.intellij-flutter-sdk = lib.mkIf cfg.flutter.enable (
          (lib.hm or config.lib).dag.entryAfter [ "writeBoundary" ] flutterSdkLinkScript
        );
      })
    ]
  );
}
