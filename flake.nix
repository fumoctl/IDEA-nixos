{
  description = "Declarative IntelliJ IDEA module for NixOS and Home Manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-jetbrains-plugins = {
      url = "github:nix-community/nix-jetbrains-plugins";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-jetbrains-plugins,
    }:
    let
      nixosModule = import ./module.nix {
        inherit nix-jetbrains-plugins;
        isNixOS = true;
      };
      hmModule = import ./module.nix {
        inherit nix-jetbrains-plugins;
        isNixOS = false;
      };
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    in
    {
      nixosModules = {
        default = nixosModule;
        intellij = nixosModule;
      };

      homeModules = {
        default = hmModule;
        intellij = hmModule;
      };

      homeManagerModules = self.homeModules;

      checks = nixpkgs.lib.genAttrs systems (
        system:
        let
          lib = nixpkgs.lib;
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };

          nixosEval = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              {
                boot.isContainer = true;
                system.stateVersion = "25.11";
                nixpkgs.config.allowUnfree = true;
                programs.intellij = {
                  enable = true;
                  rust.enable = true;
                  android.enable = true;
                  flutter.enable = true;
                  go.enable = true;
                  python.enable = true;
                  nix.enable = true;
                  nodejs.enable = true;
                  plugins = [
                    "IdeaVIM"
                    nix-jetbrains-plugins.plugins.${system}.idea.${pkgs.jetbrains.idea.version}."com.intellij.plugins.watcher"
                  ];
                  extraPackages = [ pkgs.jq ];
                  extraLibraries = [ pkgs.curl ];
                };
              }
            ];
          };

          hmEval = lib.evalModules {
            modules = [
              self.homeManagerModules.default
              {
                options = {
                  home.packages = lib.mkOption {
                    type = lib.types.listOf lib.types.package;
                    default = [ ];
                  };
                  home.activation = lib.mkOption {
                    type = lib.types.attrsOf lib.types.anything;
                    default = { };
                  };
                  xdg.dataHome = lib.mkOption {
                    type = lib.types.str;
                    default = "/home/tester/.local/share";
                  };
                  programs.direnv = {
                    enable = lib.mkEnableOption "direnv";
                    nix-direnv.enable = lib.mkEnableOption "nix-direnv";
                  };
                  lib.dag.entryAfter = lib.mkOption {
                    type = lib.types.anything;
                    default = deps: data: { inherit deps data; };
                  };
                };
                config = {
                  _module.args = { inherit pkgs; };
                  programs.intellij = {
                    enable = true;
                    flutter.enable = true;
                    nix.enable = true;
                    rust.enable = true;
                    extraLibraries = [ pkgs.libarchive ];
                  };
                };
              }
            ];
          };
        in
        {
          module-eval =
            assert builtins.elem nixosEval.config.programs.intellij.finalPackage
              nixosEval.config.environment.systemPackages;
            assert !(builtins.elem pkgs.cargo nixosEval.config.environment.systemPackages);
            assert !(builtins.elem pkgs.go nixosEval.config.environment.systemPackages);
            assert nixosEval.config.programs.nix-ld.enable;
            assert builtins.elem pkgs.vulkan-loader nixosEval.config.programs.nix-ld.libraries;
            assert builtins.elem pkgs.curl nixosEval.config.programs.nix-ld.libraries;
            assert nixosEval.config.programs.intellij.flutter.sdkPath == "/var/lib/flutter-sdk";
            assert !(lib.hasPrefix "/nix/store" nixosEval.config.programs.intellij.flutter.sdkPath);
            assert nixosEval.config.system.activationScripts ? intellij-flutter-sdk;
            assert nixosEval.config.programs.direnv.enable;
            assert nixosEval.config.programs.direnv.nix-direnv.enable;
            assert builtins.elem hmEval.config.programs.intellij.finalPackage hmEval.config.home.packages;
            assert hmEval.config.programs.intellij.flutter.sdkPath == "/home/tester/.local/share/flutter-sdk";
            assert hmEval.config.home.activation ? intellij-flutter-sdk;
            assert builtins.isString nixosEval.config.programs.intellij.finalPackage.drvPath;
            assert builtins.isString hmEval.config.programs.intellij.finalPackage.drvPath;
            pkgs.runCommand "intellij-module-check"
              {
                wrapperScript = builtins.unsafeDiscardStringContext nixosEval.config.programs.intellij.finalPackage.buildCommand;
                hmWrapperScript = builtins.unsafeDiscardStringContext hmEval.config.programs.intellij.finalPackage.buildCommand;
                flutterNixOSScript = builtins.unsafeDiscardStringContext nixosEval.config.system.activationScripts.intellij-flutter-sdk.text;
                flutterHmScript = builtins.unsafeDiscardStringContext hmEval.config.home.activation.intellij-flutter-sdk.data;
              }
              ''
                printf '%s\n' "$wrapperScript" | ${pkgs.bash}/bin/bash -n
                printf '%s\n' "$hmWrapperScript" | ${pkgs.bash}/bin/bash -n
                printf '%s\n' "$flutterNixOSScript" | ${pkgs.bash}/bin/bash -n
                printf '%s\n' "$flutterHmScript" | ${pkgs.bash}/bin/bash -n
                grep -q 'rustup' <<<"$wrapperScript"
                grep -q 'SSL_CERT_FILE' <<<"$wrapperScript"
                grep -q 'ANDROID_JAVA_HOME' <<<"$wrapperScript"
                grep -q 'FLUTTER_ROOT' <<<"$wrapperScript"
                grep -q 'GOROOT' <<<"$wrapperScript"
                grep -q 'NIX_LD_LIBRARY_PATH' <<<"$wrapperScript"
                grep -q 'NIX_LD_LIBRARY_PATH' <<<"$hmWrapperScript"
                grep -q 'libarchive' <<<"$hmWrapperScript"
                touch "$out"
              '';
        }
      );
    };
}
