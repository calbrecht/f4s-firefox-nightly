# f4s-firefox-nightly
Nix flake for Firefox nightly from github:mozilla/gecko-dev source mirror

Experimental! Expect it not to build, although it does probably.

## Provides

`overlay = firefox-nightly-unwrapped | firefox-wayland-nightly | firefox-nightly`

`packages.x86_64-linux = firefox-nightly-unwrapped | firefox-wayland-nightly | firefox-nightly`

## Usage

hahah, `zsh: bad pattern: ./#firefox-wayland-nightly` or `unsetopt extended_glob`

```shell
nix shell github:calbrecht/f4s-firefox-nightly/86.0a1-20210103092941 --command firefox
```
or to run `firefox-nightly` (defaultApp)
```shell
nix run github:calbrecht/f4s-firefox-nightly
```
or to run `firefox-wayland-nightly`
```shell
nix run github:calbrecht/f4s-firefox-nightly#firefox-wayland-nightly
```
or from `86.0a1-20210103213448` onward, also able to run the tagged apps
```shell
nix run github:calbrecht/f4s-firefox-nightly/86.0a1-20210103213448#firefox-wayland-nightly
```
