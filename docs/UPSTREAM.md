# Upstream maintenance

## Remotes and branches

```text
origin    https://github.com/ILeggett23/paper-pro-reader.git
upstream  https://github.com/koreader/koreader.git

origin/master  read-only mirror of upstream development
origin/main    Paper Pro Reader product branch
```

`main` began at KOReader `v2026.07.1` commit
`9192014d8bd82a91dc1012473be0f238dedfdb54`. Product commits never land on
`master`. Do not repeatedly copy KOReader release directories into this
repository and do not rewrite shared history.

## Update workflow

Use a released KOReader tag unless a specific unreleased fix has been justified.

```sh
git fetch upstream --tags
git switch main
git pull --ff-only origin main
git switch -c update/koreader-vYYYY.MM
git merge --no-ff vYYYY.MM
git submodule sync --recursive
git submodule update --init --recursive
```

Resolve conflicts on the update branch, run the regression gates below, push
the branch, and merge it to `main` through a reviewed pull request. Never
force-push `main` to reconcile upstream history.

Update `master` only as a fast-forward mirror:

```sh
git switch master
git merge --ff-only upstream/master
git push origin master
```

## Conflict policy

- A-class engine changes should normally be accepted from upstream unchanged.
- B-class adapter conflicts are signals to re-evaluate whether the product hook
  can become smaller or move into product code.
- C/D product files should rarely conflict with upstream; recurring conflicts
  indicate a poor boundary.
- Review every submodule pointer update. Do not float a submodule to its own
  latest branch independently of the selected KOReader tag.
- Preserve new upstream license, attribution, migration, and packaging files.

## Regression gates

After every upstream update:

1. initialize exact submodule commits and verify a clean status;
2. build the emulator from a clean build directory;
3. run base and frontend tests plus repository checks;
4. exercise EPUB and PDF open/render/navigation/selection/highlight flows;
5. verify dictionary, vocabulary, annotations, settings, and position restore;
6. test product overlays at 1620 x 2160 / 229 DPI with simulated flashes;
7. build `remarkable-aarch64` in the supported Linux toolchain;
8. test QTFB, touch, Marker, color, refresh, launch, and exit on physical Paper
   Pro hardware before a device release.

Record failures and skipped gates explicitly. A passing emulator or macOS CI
job is not a Paper Pro release qualification.
