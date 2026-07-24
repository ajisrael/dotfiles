#!/bin/bash
# Claude Code statusline: model, cwd, and context-window usage.
# Context usage comes straight from the statusline JSON's context_window
# object (used_percentage / total_input_tokens / context_window_size),
# which Claude Code computes from the live session transcript. If a
# session hasn't sent a message yet, used_percentage is null/absent and
# we fall back to raw token counts, or "n/a" if nothing is available yet.

input=$(cat)

# Tokyo Night palette (matches tmux/iTerm2/nvim theme)
tn_red='\033[38;2;247;118;142m'    # f7768e
tn_green='\033[38;2;158;206;106m'  # 9ece6a
tn_yellow='\033[38;2;224;175;104m' # e0af68
tn_blue='\033[38;2;122;162;247m'   # 7aa2f7
tn_magenta='\033[38;2;187;154;247m' # bb9af7
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
  main|master) branch_color="$tn_red" ;;
  develop) branch_color="$tn_blue" ;;
  *) branch_color="$tn_green" ;;
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
    branch_display=$(printf "%s ${branch_color}⇣%s" "$branch_display" "$num_behind")
  fi
  if [ -n "$num_ahead" ] && [ "$num_ahead" -gt 0 ]; then
    branch_display=$(printf "%s ${branch_color}⇡%s" "$branch_display" "$num_ahead")
  fi
  if [ "$num_staged" -gt 0 ]; then
    branch_display=$(printf "%s ${tn_blue}+%s${branch_color}" "$branch_display" "$num_staged")
  fi
  if [ "$num_unstaged" -gt 0 ]; then
    branch_display=$(printf "%s ${tn_blue}!%s${branch_color}" "$branch_display" "$num_unstaged")
  fi
  if [ "$num_untracked" -gt 0 ]; then
    branch_display=$(printf "%s ${tn_blue}?%s${branch_color}" "$branch_display" "$num_untracked")
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

ctx_color="$tn_green"
if [ -n "$total_input" ] && [ "$total_input" -gt 120000 ]; then
  ctx_color="$tn_yellow"
fi
if [ -n "$pct" ] && [ "$pct" -gt 90 ]; then
  ctx_color="$tn_red"
fi

cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
cost_display=""
cost_color="$tn_green"
if [ -n "$cost" ]; then
  cost_display=$(printf '$%.2f' "$cost")
  cost_over_25=$(echo "$cost" | awk '{print ($1 >= 25)}')
  cost_over_50=$(echo "$cost" | awk '{print ($1 >= 50)}')
  if [ "$cost_over_50" = "1" ]; then
    cost_color="$tn_red"
  elif [ "$cost_over_25" = "1" ]; then
    cost_color="$tn_yellow"
  fi
fi

if [ -n "$branch" ]; then
  printf "\033[2m%s${reset} \033[2m|${reset} ${tn_magenta}%s${reset} \033[2m|${reset} ${branch_color}%s${reset} \033[2m|${reset} ${ctx_color}%s${reset}" "$model" "$dir_display" "$branch_display" "$ctx_display"
else
  printf "\033[2m%s${reset} \033[2m|${reset} ${tn_magenta}%s${reset} \033[2m|${reset} ${ctx_color}%s${reset}" "$model" "$dir_display" "$ctx_display"
fi

if [ -n "$cost_display" ]; then
  printf " \033[2m|${reset} ${cost_color}%s${reset}" "$cost_display"
fi
