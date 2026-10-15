---
name: update-software
description: Audit and update the version-pinned software this dotfiles repo manages. Use when the user asks what software is outdated, wants to check for updates, or wants to bump a pinned version (Nix flake inputs, the treehouse package, pinned npm globals, podman/intellij Homebrew pins, or declared Homebrew brews/casks). Runs a read-only audit first, then updates only the items the user picks, following each pin's specific bump procedure.
user-invocable: true
---

# update-software

This machine deliberately pins most of its software to specific versions
rather than tracking latest - so updates are a reviewed, explicit act, not
something that drifts on its own. This skill does two things, in order:

1. **Audit** - list every pinned item, its current version, and the latest
   available upstream, so the user can see what's updatable.
2. **Update** - bump only the items the user picks, each by its own correct
   procedure, then validate the build. The user applies the switch.

Never update anything the user did not explicitly pick. Never run the switch
(`./rebuild.sh` / `darwin-rebuild switch`) yourself - that's the user's call;
you validate and hand back.

## Step 1: Audit

Run the audit script and show the user its table verbatim:

```sh
./home/skills/update-software/audit.sh
```

It's read-only - it reads the pins out of this repo's own files and queries
npm / GitHub / Homebrew for the latest versions. Rows marked `*` have a newer
upstream version. A `?` in the latest column means the upstream lookup failed
(network, or a pin whose "latest" isn't a simple version - e.g. the flake
inputs); treat it as "unknown", not "up to date".

Then ask the user which items they want to update. Do not proceed to any bump
until they answer.

## Step 2: Update the picked items

Each pin has its own bump procedure. Only touch the ones the user chose. After
all picked bumps, validate once (see "Validate" below) and tell the user it's
ready to apply.

All version numbers below are read fresh from the repo by the audit - the
examples just show the shape of the edit.

### Nix flake inputs (nixpkgs, nix-darwin, home-manager)

Pinned to the **26.05 release branches** in `flake.nix`, locked to exact revs
in `flake.lock`. Do NOT change the branch in `flake.nix` - these three stay on
26.05 on purpose (the comment in `flake.nix` explains why; moving off it has a
hard platform consequence on this machine). "Updating" means pulling newer
commits on the same branch:

```sh
nix flake update                 # all three
nix flake update nixpkgs         # or just one input
```

That rewrites `flake.lock` only. Validate, then the user applies.

### treehouse (`pkgs/treehouse.nix`)

A pinned `buildGoModule` derivation. Bump in three edits:

1. Set `version` to the new tag (without the leading `v`).
2. Refresh `hash`: `nix-prefetch-url --unpack https://github.com/kunchenguid/treehouse/archive/refs/tags/vX.Y.Z.tar.gz` and put the printed SRI hash in `src.hash`. (Or blank `hash` and let the build report the expected value.)
3. Refresh `vendorHash`: set it to `""`, run the build once, and copy the
   "got: sha256-..." value the build reports into `vendorHash`.

Check the tag jump: if upstream moved a major version, read its release notes
for breaking changes before bumping.

### Pinned npm globals: opencode-ai, acpx (`home.nix`)

Each is a one-line version string in a `home.activation` block
(`installOpencode`, `installAcpx`). Edit the version after the `@`:

```nix
"${pkgs.nodejs}/bin/npm" install -g opencode-ai@<new-version>
```

The block is idempotent - it reinstalls only when the installed version
doesn't match the pin, so the next switch picks it up.

### axi-family npm globals (`home/skills/install-axi-family.sh`)

`gh-axi`, `chrome-devtools-axi`, `lavish-axi`, `tasks-axi`, `quota-axi` - each
is one `installAxiPkg <pkg> <version> <skill>` line. Edit the version field.
The same script also regenerates each tool's SKILL.md on the next switch, so
the binary and its skill update together - no manual re-copy.

### podman (`home/skills/install-podman.sh`) - usually leave frozen

`PODMAN_VERSION` is pinned to the last Intel-compatible release on purpose;
newer podman is arm64-only and will NOT run on this machine (the script header
explains the hard architecture wall). The audit shows podman's "latest" with
an `(arm64-only)` note for information only. Only bump `PODMAN_VERSION` (and
`PODMAN_FORMULA_COMMIT` to a homebrew-core commit carrying an Intel bottle for
that version) if you've confirmed an Intel bottle still exists. When in doubt,
leave it and tell the user why.

### intellij-idea / intellij-idea-ce (`home/skills/install-intellij-pin.sh`) - usually leave frozen

Pinned to pre-`command_wrapper` cask recipes because the current recipes break
this machine's pinned Homebrew engine (script header has the detail). The real
fix is upstream (nix-homebrew's brew engine catching up), not a version bump
here. To move the pin anyway: update `IDEA_VERSION`/`IDEA_CE_VERSION` and the
matching `*_FORMULA_COMMIT` to a homebrew-cask commit whose recipe this engine
can still parse. Re-check this whenever the flake inputs are bumped - once the
engine supports `command_wrapper`, these move back to `configuration.nix`'s
`casks` list and this script goes away.

### Declared Homebrew brews/casks (`configuration.nix`)

The brews (`nvm`, `mongocli`, ...) and casks (`alt-tab`, `iterm2`,
`claude-code`, ...) named in `configuration.nix` are NOT version-pinned - the
repo just declares them and their version floats with the tap. Update these
with plain Homebrew, no repo edit:

```sh
brew upgrade <name>              # formula
brew upgrade --cask <name>       # cask
```

(These don't need a switch to take effect - they're a direct brew action. The
repo only controls *whether* the package is installed, not its version.)

## Validate (after any repo-file edit)

Any edit to `flake.nix`/`flake.lock`, `pkgs/`, `home.nix`, or the install
scripts needs a build check before the user applies it:

```sh
nix flake check --no-build
nix build .#darwinConfigurations.<name>.system --dry-run
```

(The `treehouse` `vendorHash` refresh is the exception - it needs a real build,
not `--dry-run`, to report the hash.) Fix any evaluation error before handing
back. Then tell the user exactly which files changed and that it's ready to
apply with `./rebuild.sh` - do not run it yourself.

## Scope note

This skill audits and updates only the pins this repo owns. A superset repo
that vendors this one adds its own pinned software on top (and its own
update-software skill for those); this skill stays limited to what lives here.
