# firefox-nightly-flake
Nix flake for Firefox nightly from github:mozilla/gecko-dev source mirror

Experimental! Expect it not to build, although it does probably.

## Provides

`packages.x86_64-linux = firefox-nightly-unwrapped | firefox-wayland-nightly | firefox-nightly`

`apps.x86_64-linux = firefox-wayland-nightly | firefox-nightly`

## Usage

```shell
nix shell 'github:calbrecht/firefox-nightly-flake/86.0a1-20210103092941' --command firefox
```
or to run `firefox-nightly` (defaultApp)
```shell
nix run 'github:calbrecht/firefox-nightly-flake'
```
or to run `firefox-wayland-nightly`
```shell
nix run 'github:calbrecht/firefox-nightly-flake#firefox-wayland-nightly'
```
