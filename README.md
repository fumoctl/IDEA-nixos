# IDEA-nixos

Declarative **IntelliJ IDEA** module (`programs.intellij`) for **NixOS** and **Home Manager**, powered by [`nix-jetbrains-plugins`](https://github.com/nix-community/nix-jetbrains-plugins).

Solves the classic JetBrains-on-NixOS friction points without polluting your global system or user `PATH`:
- **No launching from `nix develop`**: Pairs `nix-idea` with [`direnv Everywhere`](https://plugins.jetbrains.com/plugin/33482-direnv-everywhere) so Run/Debug/Test configurations, Gradle/Maven, and terminals automatically load each project's `.envrc` (`use flake`) environment.
- **Scoped fallback toolchains**: Language `<name>.enable` toggles inject compilers and SDKs *only* into IDEA's wrapper (`--suffix PATH`), letting you create and run new projects directly from IDEA's wizard while keeping `.envrc` devshells higher-priority.
- **General `nix-ld` runtime**: Merges base C/TLS libraries, per-ecosystem native libraries (such as the 40+ X11/Wayland/Vulkan/GL/PulseAudio libraries needed by the Android Emulator and CPython wheel libraries), and `extraLibraries` into `programs.nix-ld` (NixOS) and `NIX_LD_LIBRARY_PATH` (IDEA wrapper).
- **Non-`/nix/store` Flutter SDK folder**: Materializes a real outer directory (`flutter.sdkPath`) of top-level symlinks so IDEA's SDK picker never canonicalizes back into a transient `/nix/store/<hash>` path.
- **Declarative + imperative plugins**: Installs declarative plugins into `$IDE_HOME/plugins` while keeping `~/.local/share/JetBrains/...` writable for installing plugins from the Marketplace UI at runtime.

---

## Quickstart

Add the flake input:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    idea-nixos.url = "github:fumoctl/IDEA-nixos";
  };
}
```

Ensure unfree packages are permitted if using the default unified `pkgs.jetbrains.idea` distribution (`nixpkgs.config.allowUnfree = true;`), then import either **`inputs.idea-nixos.nixosModules.default`** (NixOS) or **`inputs.idea-nixos.homeModules.default`** (Home Manager):

```nix
{ pkgs, inputs, ... }:
{
  imports = [
    inputs.idea-nixos.homeModules.default # or inputs.idea-nixos.nixosModules.default
  ];

  programs.intellij = {
    enable = true;
    package = pkgs.jetbrains.idea;
    nix.enable = true;
    rust.enable = true;
    android.enable = true;
    flutter.enable = true;
    go.enable = true;
    python.enable = true;
    nodejs.enable = true;

    plugins = [
      "IdeaVIM"
      "com.plsft.tokyonight"
      "com.github.catppuccin.jetbrains_icons"
    ];

    extraPackages = [ pkgs.just ];
    extraLibraries = [ ];
  };
}
```

---

## Options Reference

### Core Options (`programs.intellij.*`)

| Option | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `enable` | `bool` | `false` | Enables IntelliJ IDEA with configured plugins, runtime `PATH`, and `nix-ld` libraries. |
| `package` | `package` | `pkgs.jetbrains.idea` | Base IDE package (`pkgs.jetbrains.idea` unified/Ultimate or `pkgs.jetbrains.idea-oss`). |
| `finalPackage` | `package` *(read-only)* | *wrapped IDE* | Resulting wrapped IntelliJ IDEA derivation installed into `systemPackages` / `home.packages`. |
| `plugins` | `listOf (either str package)` | `[ ]` | Marketplace plugin XML IDs resolved via `nix-jetbrains-plugins` or pre-built plugin derivations. |
| `extraPackages` | `listOf package` | `[ ]` | Extra CLI tools appended (`--suffix`) to IDEA's runtime `PATH`. |
| `extraLibraries` | `listOf package` | `[ ]` | Extra dynamic libraries added to `programs.nix-ld.libraries` (NixOS) and IDEA's `NIX_LD_LIBRARY_PATH`. |

### Ecosystem Presets (`programs.intellij.<name>.enable`)

| Preset | Marketplace Plugins | Scoped Runtime Packages (`PATH`) | Extra Wiring |
| :--- | :--- | :--- | :--- |
| **`nix`** | `nix-idea`, `io.github.salatmaster.direnv` | `nix`, `direnv`, `nix-direnv`, `nixd`, `nil`, `nixfmt` | Enables `programs.direnv` + `nix-direnv` (`mkDefault`). |
| **`rust`** | `com.intellij.nativeDebug`, `com.jetbrains.rust` | `rustup` *(Nixpkgs auto-patchelf)*, `stdenv.cc`, `pkg-config` | Writable `~/.rustup` toolchains & stdlib (`rustup default stable`). |
| **`android`** | `org.jetbrains.android`, `com.android.tools.design` | *(IDE manages SDK & emulator)* | Adds X11/Wayland/GL/Vulkan/Qt/Audio `nix-ld` libs + `QT_XKB_CONFIG_ROOT`. |
| **`flutter`** | `Dart`, `io.flutter` | `flutter.package` (`pkgs.flutter`) | Populates non-store `flutter.sdkPath` (`/var/lib/flutter-sdk` on NixOS, `~/.local/share/flutter-sdk` on HM) + `FLUTTER_ROOT`. |
| **`go`** | `org.jetbrains.plugins.go`, `org.jetbrains.plugins.go-template` | `go`, `gopls`, `delve`, `stdenv.cc` | Defaults `GOROOT` to `${pkgs.go}/share/go`. |
| **`python`** | `PythonCore`, `Pythonid` *(skipped on `idea-oss`)* | `python3` (`pip`, `setuptools`, `virtualenv`), `uv`, `ruff` | Adds `bzip2`, `libffi`, `sqlite`, `xz` to `nix-ld` for binary wheels. |
| **`nodejs`** | `intellij.javascript.bun` *(skipped on `idea-oss`)* | `nodejs`, `bun`, `pnpm`, `yarn` | Bundled `JavaScript`/`NodeJS` + JetBrains Bun debugger. |
| **`scala`** | `org.intellij.scala` | `scala`, `sbt` | — |
| **`zig`** | `com.redhat.devtools.lsp4ij`, `com.falsepattern.zigbrains` | `zig`, `zls` | — |
| **`php`** | `com.jetbrains.php` | `php`, `php.packages.composer` | — |
| **`ruby`** | `org.jetbrains.plugins.ruby` | `ruby` | — |

---

## Notes & Tips

- **Standalone Home Manager & `nix-ld`**: Home Manager cannot install the `/lib64/ld-linux` system shim on its own; enable `programs.nix-ld.enable = true;` in your host NixOS config so IDEA's `NIX_LD_LIBRARY_PATH` takes effect for the Android Emulator and unpatched plugin binaries.
- **Gradle & JDK 21**: Upstream Nixpkgs runs IDEA 2026.2 on JBR 25 (`25.0.5.0.3`), which crashes Gradle <= 8.14 Kotlin DSL scripts. `IDEA-nixos` defaults `JAVA_HOME`, `JDK_HOME`, and `ANDROID_JAVA_HOME` to `pkgs.jdk21.home` while keeping `IDEA_JDK` on JBR 25. If the Flutter plugin overrides `JAVA_HOME` with IDEA's Project SDK, either set the Project SDK / `org.gradle.java.home` to JDK 21 or expose `JAVA_HOME` in your project's `.envrc` flake.
- **Ephemeral Root (`impermanence`)**: Persist `~/.config/JetBrains`, `~/.local/share/JetBrains`, `~/.cache/JetBrains`, `~/.android`, `~/.config/.android`, `~/.gradle`, `~/.m2`, `~/.cargo`, `~/.rustup`, `~/.pub-cache`, and your chosen Android SDK folder (e.g. `~/Android` or `~/.local/share/Android`).
