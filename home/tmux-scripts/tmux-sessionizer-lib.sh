# shellcheck shell=bash
# Shared helpers for tmux-sessionizer and tmux-sessionizer-treehouse.
# Sourced only - not meant to be run directly, and deliberately not
# executable so it doesn't show up as a spurious PATH entry.
#
# Session config format (.tmux-sessionizer-config)
# ------------------------------------------------
# A new session is laid out from the project's own .tmux-sessionizer-config,
# or from .default-tmux-sessionizer-config next to this file when the project
# has none. The file is a list of windows, one block each, separated by lines
# containing only "---". In a block:
#
#   - an optional first line "# name: <window name>" names the window;
#   - every other non-empty line is a command. A pane's commands are joined
#     with " && " and typed into its shell with send-keys (not run as the
#     pane's start command), so the pane outlives them and keeps their output;
#   - a "# pane:" line splits the window - the commands after it, up to the
#     next "# pane:" line or the end of the block, go to a new pane:
#
#       # pane: <right|below> [<size>] [dir=<path>] [title=<text>]
#
#       right         the new pane goes to the right (side by side)
#       below         the new pane goes underneath (stacked)
#       <size>        its width (right) or height (below): "40%", or a
#                     number of cells ("80")
#       dir=<path>    its working directory: relative to the session
#                     directory, absolute, or ~/...; no spaces. Default: the
#                     session directory
#       title=<text>  its title, shown in the window's pane borders; takes
#                     the rest of the line, so it goes last
#
# Each split divides the pane created just before it, so "right" then
# "below" leaves a full-height pane on the left and a column of two on the
# right. A "# pane:" line with no direction, before the block's first
# command, sets dir=/title= for the window's first pane instead of splitting.
# Focus ends on each window's first pane, and on the first window.
#
# Example - a dev server on the left, a listener and a log stacked right:
#
#   # name: services
#   # pane: dir=web title=web
#   ./dev.sh
#   # pane: right 40% title=listener
#   ./listener
#   # pane: below dir=logs title=log
#   tail -f app.log
#
# An executable setup-local-env.sh in the project is sourced first (with the
# session dir and the project dir as arguments), so what it exports - e.g.
# ports that vary per worktree - reaches every command. Globally gitignored.

_tmux_sessionizer_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# apply_session_config <session> <dir> [config_lookup_dir]
#
# Lay out the freshly created <session> (its window 1 already exists, opened
# in <dir>) from the project config in config_lookup_dir - which defaults to
# <dir> but differs for a worktree, where <dir> is the worktree and
# config_lookup_dir the real project root - else from the default config.
apply_session_config() {
	local session="$1" dir="$2" config_lookup_dir="${3:-$2}"
	apply_session_config_file "$session" "$dir" "$config_lookup_dir" \
		"$(session_config_file "$config_lookup_dir" "$_tmux_sessionizer_lib_dir/.default-tmux-sessionizer-config")"
}

# session_config_file <config_lookup_dir> <default_config>
#
# Print the project's own config if config_lookup_dir has one, else
# <default_config>.
session_config_file() {
	if [[ -f "$1/.tmux-sessionizer-config" ]]; then
		printf '%s\n' "$1/.tmux-sessionizer-config"
	else
		printf '%s\n' "$2"
	fi
}

# apply_session_config_file <session> <dir> <config_lookup_dir> <config_file>
#
# apply_session_config with the config file already chosen. No-op if
# <config_file> doesn't exist or holds no blocks.
apply_session_config_file() {
	local session="$1" dir="$2" config_lookup_dir="$3" config_file="$4"
	[[ -f "$config_file" ]] || return 0

	local setup_script="$config_lookup_dir/setup-local-env.sh"
	if [[ -x "$setup_script" ]]; then
		# shellcheck disable=SC1090
		source "$setup_script" "$dir" "$config_lookup_dir"
	fi

	# Split into window blocks on lines containing only "---". A trailing
	# block is kept only if it has content, so a final "---" adds no window.
	local blocks=() block="" line
	while IFS= read -r line || [[ -n "$line" ]]; do
		if [[ "$line" == "---" ]]; then
			blocks+=("$block")
			block=""
		else
			[[ -n "$block" ]] && block+=$'\n'
			block+="$line"
		fi
	done < "$config_file"
	[[ -n "$block" ]] && blocks+=("$block")
	[[ "${#blocks[@]}" -eq 0 ]] && return 0

	local i
	for (( i = 0; i < ${#blocks[@]}; i++ )); do
		_tmux_sessionizer_window "$session" "$(( i + 1 ))" "${blocks[i]}" "$dir" "$config_file"
	done
	tmux select-window -t "${session}:1"
}

# _tmux_sessionizer_window <session> <index> <block> <dir> <config_file>
#
# Build window <index> from one config block: window 1 already exists and
# is reused, later ones are created. All panes are laid out before any
# command is typed, so each program starts at its final size.
_tmux_sessionizer_window() {
	local session="$1" index="$2" block="$3" dir="$4" config_file="$5"

	local name="" body="$block"
	if [[ "${block%%$'\n'*}" =~ ^'# name: '(.+)$ ]]; then
		name="${BASH_REMATCH[1]}"
		if [[ "$block" == *$'\n'* ]]; then
			body="${block#*$'\n'}"
		else
			body=""
		fi
	fi

	# One entry per pane; [0] is the window's first pane.
	local where=("") size=("") cwd=("$dir") title=("") cmds=("")
	local n=0 line spec spec_where spec_size spec_dir spec_title
	while IFS= read -r line; do
		if [[ "$line" =~ ^'# pane:'(.*)$ ]]; then
			_tmux_sessionizer_parse_pane "${BASH_REMATCH[1]}" "$config_file"
			if [[ -z "$spec_where" && "$n" -eq 0 && -z "${cmds[0]}" ]]; then
				# Leading and direction-less: describes the first pane.
				[[ -n "$spec_size" ]] && _tmux_sessionizer_warn "$config_file: '# pane:$spec' - a window's first pane takes no size"
			else
				if [[ -z "$spec_where" ]]; then
					_tmux_sessionizer_warn "$config_file: '# pane:$spec' has no direction (right/below) - using right"
					spec_where=right
				fi
				n=$(( n + 1 ))
				where[n]="$spec_where"
				size[n]="$spec_size"
				cmds[n]=""
			fi
			cwd[n]="$(_tmux_sessionizer_pane_dir "$dir" "$spec_dir" "$config_file")"
			title[n]="$spec_title"
			continue
		fi
		[[ -z "$line" ]] && continue
		[[ -n "${cmds[n]}" ]] && cmds[n]+=" && "
		cmds[n]+="$line"
	done <<< "$body"

	local panes=() pane k
	if [[ "$index" -eq 1 ]]; then
		pane="$(tmux display-message -p -t "${session}:1" '#{pane_id}')"
		[[ -n "$name" ]] && tmux rename-window -t "${session}:1" "$name"
		# The session was opened in <dir>; restart its shell elsewhere if
		# the first pane asked for another directory.
		[[ "${cwd[0]}" != "$dir" ]] && tmux respawn-pane -k -t "$pane" -c "${cwd[0]}"
	else
		local new_window=(new-window -P -F '#{pane_id}' -t "${session}:${index}" -c "${cwd[0]}")
		[[ -n "$name" ]] && new_window+=(-n "$name")
		pane="$(tmux "${new_window[@]}")"
	fi
	panes+=("$pane")

	for (( k = 1; k <= n; k++ )); do
		local split=(split-window -P -F '#{pane_id}' -t "${panes[k - 1]}" -c "${cwd[k]}")
		case "${where[k]}" in
			right) split+=(-h) ;;
			below) split+=(-v) ;;
		esac
		[[ -n "${size[k]}" ]] && split+=(-l "${size[k]}")
		pane="$(tmux "${split[@]}")"
		panes+=("$pane")
	done

	# Titles show in a top pane border, on windows that set any. Programs
	# in those panes can't retitle them (allow-set-title), and untitled ones
	# get a blank title instead of tmux's default, the hostname.
	local titled=false
	for (( k = 0; k <= n; k++ )); do
		[[ -n "${title[k]}" ]] && titled=true
	done
	if [[ "$titled" == true ]]; then
		for (( k = 0; k <= n; k++ )); do
			tmux set-option -p -t "${panes[k]}" allow-set-title off
			tmux select-pane -t "${panes[k]}" -T "${title[k]}"
		done
		tmux set-option -w -t "${panes[0]}" pane-border-status top
	fi

	for (( k = 0; k <= n; k++ )); do
		[[ -n "${cmds[k]}" ]] && tmux send-keys -t "${panes[k]}" "${cmds[k]}" Enter
	done
	[[ "$n" -gt 0 ]] && tmux select-pane -t "${panes[0]}"
	return 0
}

# _tmux_sessionizer_parse_pane <text after "# pane:"> <config_file>
#
# Set the caller's spec (the raw text, for messages), spec_where,
# spec_size, spec_dir and spec_title.
_tmux_sessionizer_parse_pane() {
	spec="$1"
	spec_where="" spec_size="" spec_dir="" spec_title=""
	local rest="$1" word
	while :; do
		rest="${rest#"${rest%%[![:space:]]*}"}"
		[[ -z "$rest" ]] && break
		if [[ "$rest" == title=* ]]; then
			spec_title="${rest#title=}"
			spec_title="${spec_title%"${spec_title##*[![:space:]]}"}"
			break
		fi
		word="${rest%%[[:space:]]*}"
		rest="${rest#"$word"}"
		case "$word" in
			right | below) spec_where="$word" ;;
			dir=*) spec_dir="${word#dir=}" ;;
			*)
				if [[ "$word" =~ ^[0-9]+%?$ ]]; then
					spec_size="$word"
				else
					_tmux_sessionizer_warn "$2: '# pane:$1' - ignoring '$word'"
				fi
				;;
		esac
	done
}

# _tmux_sessionizer_pane_dir <session_dir> <dir= value> <config_file>
#
# Resolve a pane's dir= against the session dir. Falls back to the session
# dir (with a warning) if it isn't a directory.
_tmux_sessionizer_pane_dir() {
	local base="$1" want="$2" path
	case "$want" in
		"")
			printf '%s\n' "$base"
			return
			;;
		\~) path="$HOME" ;;
		\~/*) path="$HOME/${want:2}" ;;
		/*) path="$want" ;;
		*) path="$base/$want" ;;
	esac
	if [[ -d "$path" ]]; then
		printf '%s\n' "$path"
	else
		_tmux_sessionizer_warn "$3: dir=$want is not a directory - using $base"
		printf '%s\n' "$base"
	fi
}

# Config problems never stop a session from opening - they're reported on
# stderr and in tmux's status line (the sessionizer usually runs in a popup,
# whose output disappears with it).
_tmux_sessionizer_warn() {
	printf 'tmux-sessionizer: %s\n' "$1" >&2
	tmux display-message -l -d 8000 "tmux-sessionizer: $1" 2>/dev/null || true
}
