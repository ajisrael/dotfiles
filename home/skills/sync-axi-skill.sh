#!/usr/bin/env bash
# Regenerates a local SKILL.md for one axi-family package from the exact
# copy shipped inside the pinned, globally installed npm package itself
# (each of gh-axi/chrome-devtools-axi/lavish-axi ships skills/<name>/SKILL.md
# in its own npm `files` list), with every `npx -y <pkg>` invocation
# rewritten to a plain call to the installed binary.
#
# Run via home.nix's installAxiFamily activation block right after
# `npm install -g <pkg>@<version>`, so bumping the pinned version there and
# running ./rebuild.sh regenerates the matching local skill automatically -
# no manual re-copy/re-diff against the upstream skill file needed.
#
# Usage: sync-axi-skill.sh <npm-bin> <npm-package> <skill-dir-name> <dest-dir>
set -euo pipefail

npm_bin="$1"
pkg="$2"
skill_name="$3"
dest_dir="$4"

npm_root_g="$("$npm_bin" root -g)"
src="${npm_root_g}/${pkg}/skills/${skill_name}/SKILL.md"

if [ ! -f "$src" ]; then
  echo "sync-axi-skill: ${src} not found (is ${pkg} installed globally?)" >&2
  exit 1
fi

mkdir -p "$dest_dir"
sed -E \
  -e "s#You do not need ${pkg} installed globally - invoke it with \`npx -y ${pkg}([^\`]*)\`\.#${pkg} is installed globally and pinned to an exact version by dotfiles (see ~/.claude/plans/memoized-mixing-quilt.md) - invoke it directly with \`${pkg}\1\`.#g" \
  -e "/^When using \`npx -y ${pkg}\`, npx already resolves the package on demand\.\$/d" \
  -e "s#npx -y ${pkg}#${pkg}#g" \
  "$src" > "${dest_dir}/SKILL.md"

# Upstream's skill text tells the agent to run `<pkg> update` to self-update
# via npm. That would bypass the version pin in dotfiles's home.nix
# until the next `./rebuild.sh` silently reinstalls the pinned version over
# it - a confusing, temporary drift. Override that instruction explicitly.
cat >> "${dest_dir}/SKILL.md" <<EOF

## Version pinning on this machine

Do not run \`${pkg} update\` - it self-updates via npm and would drift from
the version pinned in dotfiles's \`home.nix\`, until the next
\`./rebuild.sh\` silently reinstalls the pinned version over it. To upgrade,
tell the user to bump the pinned version in \`home.nix\` and run
\`./rebuild.sh\` - that regenerates this skill file to match automatically.
\`${pkg} update --check\` (read-only, does not install) is still fine to run.
EOF
