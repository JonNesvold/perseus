{ pkgs, lib, userConfig, ... }:
let
  devTools = userConfig.devTools;
  hasDevTool = tool: builtins.elem tool devTools;
  goPackages = with pkgs; [ go gopls ];
  rustPackages = with pkgs; [ rustc cargo rust-analyzer clippy rustfmt ];
  nodePkgs = with pkgs; [
    nodejs_22
    pnpm
    typescript
    typescript-language-server
    vscode-langservers-extracted
    tailwindcss-language-server
  ];
  androidComposition = pkgs.androidenv.composeAndroidPackages {
    platformVersions = [ "35" "36" ];
    buildToolsVersions = [ "35.0.0" "36.0.0" ];
    includeEmulator = false;
    includeSystemImages = false;
    includeSources = false;
  };
  androidPackages = [
    androidComposition.androidsdk
    pkgs.gradle
    pkgs.jdk17
  ];
in
{
  nixpkgs.config = lib.mkIf (hasDevTool "android") {
    android_sdk.accept_license = true;
  };

  environment.systemPackages =
    (lib.optionals (hasDevTool "go") goPackages) ++
    (lib.optionals (hasDevTool "rust") rustPackages) ++
    (lib.optionals (hasDevTool "node") nodePkgs) ++
    (lib.optionals (hasDevTool "android") androidPackages);
  environment.variables = lib.mkMerge [
    (lib.mkIf (hasDevTool "go") {
      GOPATH = "$HOME/go";
      GOBIN = "$HOME/go/bin";
    })
    (lib.mkIf (hasDevTool "rust") {
      CARGO_HOME = "$HOME/.cargo";
      RUSTUP_HOME = "$HOME/.rustup";
    })
    (lib.mkIf (hasDevTool "node") {
      NODE_OPTIONS = "--max-old-space-size=8192";
      PNPM_HOME = "$HOME/.local/share/pnpm";
    })
    (lib.mkIf (hasDevTool "android") {
      ANDROID_HOME = "${androidComposition.androidsdk}/libexec/android-sdk";
      ANDROID_SDK_ROOT = "${androidComposition.androidsdk}/libexec/android-sdk";
      JAVA_HOME = "${pkgs.jdk17}/lib/openjdk";
    })
  ];
  environment.sessionVariables = lib.mkIf (hasDevTool "node") {
    PATH = [ "$HOME/.local/share/pnpm" ];
  };
}
