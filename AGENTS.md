# AGENTS.md — IDEA-nixos

Architecture reference and invariants for **IDEA-nixos** — a Nix flake providing `programs.intellij` for NixOS (`nixosModules.default`) and Home Manager (`homeModules.default` / `homeManagerModules.default`). Keep `AGENTS.md` `< 16000` B.

## Default Agent Mode: Ponytail (Mandatory)

Agents here **MUST always activate and follow `ponytail` (`full` default)** unless the user asks for `lite`, `ultra`, or opts out (`"stop ponytail"` / `"normal mode"`):

- **Before coding**: Read `~/.gemini/config/plugins/ponytail/skills/ponytail/SKILL.md` if present locally; otherwise apply these rules directly.
- **Smallest complete change**: Solve the whole task with the shortest clear diff. Reuse the table-driven `ecosystems` map in `module.nix`; add zero unrequested abstractions, options, or boilerplate; update `checks` and docs when behavior changes.
- **Mandatory check coverage**: Every wrapper flag, activation script change, or new ecosystem preset MUST be exercised in `checks.<system>.module-eval` (`flake.nix`, including `bash -n` validation on generated shell scripts) and pass `nix flake check`.
- **Shortcuts & closeout**: Mark known-limit shortcuts `# shortcut: <limit>, <when to upgrade>`, and **end replies with 1–2 lines naming what was skipped/not checked and any risk**.

## 1. Repository Layout

```text
IDEA-nixos/
├── flake.nix    # Inputs (nixpkgs, nix-jetbrains-plugins), module exports, checks.<system>.module-eval
├── flake.lock   # Locked GitHub inputs (never commit local path:/nix/store overrides)
├── module.nix   # Parameterized module factory ({ nix-jetbrains-plugins, isNixOS }:)
├── README.md    # User-facing documentation & options reference
└── AGENTS.md    # Architectural invariants & verification checklist
```

## 2. Core Architectural Invariants

1. **Single Module Factory (`module.nix`)**:
   - `isNixOS = true` wires `environment.systemPackages`, `programs.nix-ld.{enable,libraries}`, and `system.activationScripts.intellij-flutter-sdk`.
   - `isNixOS = false` wires `home.packages` and `home.activation.intellij-flutter-sdk` via `(lib.hm or config.lib).dag.entryAfter [ "writeBoundary" ]` (never add `home-manager` to `flake.nix` `inputs`).
   - Toolchains in `ecosystems.<name>.packages` and `extraPackages` MUST stay inside the wrapped IDE (`wrappedIde`), **never** leaking into `environment.systemPackages` or `home.packages`.

2. **Wrapper Precedence & Reproducibility (`wrappedIde`)**:
   - Always use **`--suffix PATH`**, **`--suffix NIX_LD_LIBRARY_PATH`**, and **`--set-default`** for environment variables (`GOROOT`, `FLUTTER_ROOT`, `QT_XKB_CONFIG_ROOT`, `SSL_CERT_FILE`, `NIX_SSL_CERT_FILE`, `JAVA_HOME`, `JDK_HOME`, `ANDROID_JAVA_HOME`). This guarantees per-project `.envrc` devshells loaded by `direnv-everywhere` (`io.github.salatmaster.direnv`) always take priority over fallback IDE toolchains.
   - Keep `SSL_CERT_FILE` and `NIX_SSL_CERT_FILE` defaulted to `${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt` so hermetic CPython/OpenSSL child processes (such as Google Antigravity's `agy_acp_server.par`) succeed when IDEA is launched from a Wayland compositor without `/etc/profile`.
   - Keep `JAVA_HOME`, `JDK_HOME`, and `ANDROID_JAVA_HOME` defaulted to `pkgs.jdk21.home` (leaving `IDEA_JDK` untouched on JBR 25) because upstream `pkgs.jetbrains.idea` defaults them to JBR 25 (`25.0.5.0.3`), which crashes Gradle <= 8.14 Kotlin DSL scripts.

3. **Plugin Resolution & `idea-oss` Gating**:
   - Resolve Marketplace XML IDs via `nix-jetbrains-plugins.lib.pluginsForIde pkgs cfg.package` (preserving upstream overrides like `delve` for Go, `lldb` for `nativeDebug`, and Node wrapper for Copilot), deduplicating both IDs and derivations with `lib.unique` so `pkgs.jetbrains.plugins.addPlugins` never fails on duplicate `ln -s`.
   - Before adding a new preset plugin ID, inspect its `META-INF/plugin.xml` `<dependencies>` / `<depends>` against `pkgs.jetbrains.idea` bundled plugins (e.g. `com.jetbrains.rust` requires `com.intellij.nativeDebug` in 2026.2+; `com.falsepattern.zigbrains` requires `com.redhat.devtools.lsp4ij`).
   - Gate Ultimate-dependent add-on plugins (`Pythonid`, `intellij.javascript.bun`) with `lib.optionals (cfg.package.pname != "idea-oss")` when a preset can still function partially or degrade cleanly on `idea-oss`.
   - Never override `-Didea.plugins.path` so `~/.local/share/JetBrains/...` remains writable for imperative runtime Marketplace installs.

4. **Toolchain Specifics**:
   - **Rust**: Use `pkgs.rustup` (which carries Nixpkgs's dynamic `patchelf` patch and proxy binaries) rather than `/nix/store` `rustLibSrc` symlinks; IntelliJ Rust copies stdlib sources preserving `0444` store modes and fails with `Corrupted standard library` otherwise.
   - **Android**: Only install plugins (`org.jetbrains.android`, `com.android.tools.design`) and `nix-ld` libraries — never bundle `androidenv` SDK/emulator derivations from Nixpkgs.
   - **Flutter**: `flutter.sdkPath` MUST be materialized as a **real outer directory** containing `ln -sfn` symlinks to top-level entries of `cfg.flutter.package` (including `.git`) after pruning stale depth-1 symlinks (`find ... -maxdepth 1 -type l -delete`), preventing IDEA from canonicalizing `sdkPath` back into `/nix/store`.
   - **Checks String Context**: In `flake.nix` `checks`, wrap `buildCommand` / activation script strings in `builtins.unsafeDiscardStringContext` so `nix flake check` validates bash syntax and flags in seconds without downloading multi-gigabyte IDE/SDK closures.

## 3. Verification Checklist

Run before committing or pushing:

```bash
nixfmt --check $(git ls-files '*.nix')
nix flake check --print-build-logs # add `--no-write-lock-file --override-input nixpkgs flake:nixpkgs` if offline/local
git status --short && test "$(wc -c < AGENTS.md)" -lt 16000
```

Use short lowercase commit messages (no Conventional Commits or AI trailers) and keep `flake.lock` pinned to GitHub upstream inputs.
