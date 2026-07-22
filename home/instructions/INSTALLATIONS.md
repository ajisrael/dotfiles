# Installing software on this machine

This applies to global/system-level installs only - a package manager
operating on this machine's state outside of a single project (a CLI tool,
a GUI app, a language runtime available on PATH everywhere). It does not
apply to project-local installs (`npm install` inside a repo, a Python
venv, `go get` for a module) - those follow whatever the project itself
uses.

This machine is managed by nix-darwin/home-manager (`dotfiles`).
Before installing anything globally, use this priority order:

1. **Nix (`home.packages` in `home.nix`)** - first choice. Reproducible,
   declarative, and rolls back cleanly. Check nixpkgs has the package
   before falling to a lower tier: `nix search nixpkgs <name>`.
2. **Homebrew (`homebrew.brews`/`homebrew.casks`, managed by nix-homebrew)**
   - second choice, for packages with no nixpkgs equivalent or where the
   Homebrew cask is materially better maintained (GUI apps in particular).
3. **Custom install (a `home.activation` block calling a vendored install
   script, or a manual one-off)** - last resort, only when neither Nix nor
   Homebrew packages the thing. Examples already in this repo: sdkman
   (`installSdkman`), Plash (`installPlash`) - both outrun by tier 1/2 for
   documented reasons visible at each activation block in `home.nix`.

Record *why* a package landed at a lower tier right next to the
`home.packages` entry, `homebrew.brews`/`casks` entry, or activation block
- e.g. "no nixpkgs package" or "Homebrew cask unmaintained, curl install
pinned to a specific release". Future edits (including automated ones)
need that reasoning to avoid re-litigating the same tier decision or
silently regressing a package to a worse tier.

After adding or changing anything in `home.nix`/`configuration.nix`,
validate with:

```sh
nix flake check --no-build
nix build .#darwinConfigurations.<name>.system --dry-run
```

then stop - applying the change (`./rebuild.sh` / `darwin-rebuild switch`)
is always the user's own step, never an agent's. See this repo's
AGENTS.md for that rule and why.
