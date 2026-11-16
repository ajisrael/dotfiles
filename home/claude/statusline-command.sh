#!/bin/bash
# Claude Code statusline: model, cwd, git branch, and context-window usage.
# Context usage comes straight from the statusline JSON's context_window
# object (used_percentage / total_input_tokens / context_window_size),
# which Claude Code computes from the live session transcript. If a
# session hasn't sent a message yet, used_percentage is null/absent and
# we fall back to raw token counts, or "n/a" if nothing is available yet.

input=$(cat)

# ANSI 0-15 palette: the accents resolve through the terminal's ANSI colour
# slots, so the statusline follows whatever theme the terminal runs - iTerm2's
# Tokyo Night profile on the Mac (which pins ANSI 1-5 to these exact hues),
# `omarchy theme set` on the omarchy box. SGI 1-5 = red/green/yellow/blue/
# magenta; segments stay dim via SGR 2.
red='\033[31m'
green='\033[32m'
yellow='\033[33m'
blue='\033[34m'
magenta='\033[35m'
reset='\033[0m'

model=$(echo "$input" | jq -r '.model.display_name // "?"')
effort=$(echo "$input" | jq -r '.effort.level // empty')
if [ -n "$effort" ]; then
  model="$model ($effort)"
fi
dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "?"')
dir_display=$(basename "$dir")

branch=$(git -C "$dir" branch --show-current 2>/dev/null)

case "$branch" in
  main|master) branch_color="$red" ;;
  develop) branch_color="$blue" ;;
  *) branch_color="$green" ;;
esac

# Same ⇡ahead/⇣behind/+staged/!unstaged/?untracked convention as the shell
# prompt's p10k vcs segment. Built via printf (not plain interpolation) so
# the embedded \033 color codes are resolved to real escape bytes now - the
# final printf below substitutes this in through %s, which does not
# interpret backslash escapes in substituted values, only in its own
# literal format string.
branch_display="$branch"
if [ -n "$branch" ]; then
  num_ahead=$(git -C "$dir" rev-list --count '@{upstream}..HEAD' 2>/dev/null)
  num_behind=$(git -C "$dir" rev-list --count 'HEAD..@{upstream}' 2>/dev/null)
  num_staged=$(git -C "$dir" diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
  num_unstaged=$(git -C "$dir" diff --name-only 2>/dev/null | wc -l | tr -d ' ')
  num_untracked=$(git -C "$dir" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
  if [ -n "$num_behind" ] && [ "$num_behind" -gt 0 ]; then
    branch_display=$(printf "%s ${blue}⇣%s${branch_color}" "$branch_display" "$num_behind")
  fi
  if [ -n "$num_ahead" ] && [ "$num_ahead" -gt 0 ]; then
    branch_display=$(printf "%s ${blue}⇡%s${branch_color}" "$branch_display" "$num_ahead")
  fi
  if [ "$num_staged" -gt 0 ]; then
    branch_display=$(printf "%s ${blue}+%s${branch_color}" "$branch_display" "$num_staged")
  fi
  if [ "$num_unstaged" -gt 0 ]; then
    branch_display=$(printf "%s ${blue}!%s${branch_color}" "$branch_display" "$num_unstaged")
  fi
  if [ "$num_untracked" -gt 0 ]; then
    branch_display=$(printf "%s ${blue}?%s${branch_color}" "$branch_display" "$num_untracked")
  fi
fi

used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
total_input=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')
window_size=$(echo "$input" | jq -r '.context_window.context_window_size // empty')

pct=""
if [ -n "$used_pct" ]; then
  pct=$(printf "%.0f" "$used_pct")
  ctx_display=$(printf "ctx %s%% used" "$pct")
  if [ -n "$total_input" ] && [ -n "$window_size" ]; then
    ctx_display=$(printf "%s (%sk/%sk)" "$ctx_display" "$((total_input / 1000))" "$((window_size / 1000))")
  fi
elif [ -n "$total_input" ] && [ -n "$window_size" ] && [ "$window_size" -gt 0 ]; then
  pct=$(( total_input * 100 / window_size ))
  ctx_display=$(printf "ctx ~%s%% used (%sk/%sk)" "$pct" "$((total_input / 1000))" "$((window_size / 1000))")
else
  ctx_display="ctx n/a"
fi

ctx_color="$green"
if [ -n "$total_input" ] && [ "$total_input" -gt 120000 ]; then
  ctx_color="$yellow"
fi
if [ -n "$pct" ] && [ "$pct" -gt 90 ]; then
  ctx_color="$red"
fi

if [ -n "$branch" ]; then
  printf "\033[2m%s${reset} \033[2m|${reset} ${magenta}%s${reset} \033[2m|${reset} ${branch_color}%s${reset} \033[2m|${reset} ${ctx_color}%s${reset}" "$model" "$dir_display" "$branch_display" "$ctx_display"
else
  printf "\033[2m%s${reset} \033[2m|${reset} ${magenta}%s${reset} \033[2m|${reset} ${ctx_color}%s${reset}" "$model" "$dir_display" "$ctx_display"
fi

# Optional extra segment. If $CLAUDE_STATUSLINE_EXTRA points at an executable,
# run it with the same statusline JSON on stdin and append its stdout as one
# more "|"-separated segment (only when it prints something non-empty). A
# generic extension point - this script stays agnostic about what the extra
# segment is; whatever provides the hook owns its content and its own
# colors/formatting. The extra command must be fast and non-blocking (it runs
# on every statusline render); anything slow should cache and refresh in the
# background on its own.
if [ -n "${CLAUDE_STATUSLINE_EXTRA:-}" ] && [ -x "${CLAUDE_STATUSLINE_EXTRA}" ]; then
  extra=$(printf '%s' "$input" | "$CLAUDE_STATUSLINE_EXTRA" 2>/dev/null)
  if [ -n "$extra" ]; then
    printf " \033[2m|${reset} %s" "$extra"
  fi
fi
