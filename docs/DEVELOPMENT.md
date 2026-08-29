# Development

These commands target KOReader `v2026.07.1`. Re-check upstream documentation
when updating the baseline because `kodev` options and prerequisites may change.

## Checkout

```sh
git clone https://github.com/ILeggett23/paper-pro-reader.git
cd paper-pro-reader
git remote add upstream https://github.com/koreader/koreader.git
git switch main
git submodule update --init --recursive
```

Verify `origin`, `upstream`, the selected commit, and clean submodule state
before building.

## macOS prerequisites

KOReader requires Bash 4+, GNU Make 4.1+, Python 3.10+, CMake 3.17.5+,
Meson 1.8.3+ on macOS, Ninja, NASM, pkg-config, gettext, autotools, GNU command
variants, a C/C++17 compiler, patch, unzip, and wget. SDL3 3.2.12+ may be built
automatically if it is not installed.

The supported Homebrew setup from KOReader's `doc/Building.md` is:

```sh
brew install autoconf automake bash binutils cmake coreutils findutils \
  gettext gnu-getopt libtool make meson nasm ninja pkgconf sdl3 util-linux

export PATH="$(brew --prefix)/opt/findutils/libexec/gnubin:\
$(brew --prefix)/opt/gnu-getopt/bin:\
$(brew --prefix)/opt/make/libexec/gnubin:\
$(brew --prefix)/opt/util-linux/bin:${PATH}"
```

Optional tools for the full check workflow:

```sh
brew install ccache luacheck p7zip shellcheck shfmt
```

On the Phase 0 host, Homebrew installation required an administrator-password
prompt unavailable to the automated session. See `BASELINE_TESTS.md` for the
result. GitHub Actions built and tested an ARM64 app artifact, which was then
run locally for focused smoke tests; that does not count as a source build from
this checkout. No successful local source build is claimed until the documented
toolchain is installed and the commands below pass.

## Dependencies, build, and run

```sh
./kodev fetch-thirdparty
./kodev build
./kodev run
```

For the Paper Pro-oriented emulator profile, the v2026.07.1 implementation uses
uppercase `-W`, `-H`, and `-D` options:

```sh
EMULATE_READER_FLASH=100 ./kodev run -W 1620 -H 2160 -D 229
```

Open a fixture directly by appending its path:

```sh
EMULATE_READER_FLASH=100 ./kodev run -W 1620 -H 2160 -D 229 \
  spec/front/unit/data/juliet.epub
```

The flash simulation exposes refresh regions and timing mistakes but does not
emulate Gallery 3 waveforms, color-transition cost, ghosting, or Marker latency.

## Tests and checks

```sh
./kodev test base
./kodev test front
./kodev check
```

Focused frontend example:

```sh
./kodev test front readerbookmark_spec.lua
```

## Clean rebuild

```sh
./kodev clean
./kodev build
```

Build outputs belong in KOReader's generated build/install paths and must not be
committed.

## Paper Pro package path

The current target is:

```sh
./kodev release remarkable-aarch64
```

Embedded release instructions assume Linux and the appropriate cross-toolchain.
Do not treat a macOS emulator build as a package build. The generated archive
uses the reMarkable packaging rules in `make/remarkable.mk` and the runtime
files under `platform/remarkable/`.
