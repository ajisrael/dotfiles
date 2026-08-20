# Shared helpers for tmux-sessionizer and tmux-sessionizer-treehouse.
# Sourced only - not meant to be run directly, and deliberately not
# executable so it doesn't show up as a spurious PATH entry.

apply_session_config() {
	local session="$1"
	local dir="$2"
	local script_dir
	script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

	# Prefer a project-local config, fall back to the default - projects
	# under ~/learning get their own default (opencode instead of claude on
	# the last window) since that's the assistant used there.
	local config_file="$dir/.tmux-sessionizer-config"
	if [[ ! -f "$config_file" ]]; then
		if [[ "$dir" == "$HOME/learning"/* || "$dir" == "$HOME/learning" ]]; then
			config_file="$script_dir/.default-tmux-sessionizer-config-learning"
		else
			config_file="$script_dir/.default-tmux-sessionizer-config"
		fi
	fi

	[[ ! -f "$config_file" ]] && return

	# Parse panes: blocks separated by lines containing only "---"
	local panes=()
	local block=""
	while IFS= read -r line || [[ -n "$line" ]]; do
		if [[ "$line" == "---" ]]; then
			panes+=("$block")
			block=""
		else
			[[ -n "$block" ]] && block+=$'\n'
			block+="$line"
		fi
	done < "$config_file"
	# Capture the last block if file doesn't end with ---
	[[ -n "$block" ]] && panes+=("$block")

	local total="${#panes[@]}"
	[[ "$total" -eq 0 ]] && return

	# Extract an optional "# name: <value>" from the first line of a block.
	get_window_name() {
		local block="$1"
		local first_line="${block%%$'\n'*}"
		if [[ "$first_line" =~ ^'# name: '(.+)$ ]]; then
			echo "${BASH_REMATCH[1]}"
		fi
	}

	# Strip the "# name:" line so it isn't sent as a command.
	strip_name_line() {
		local block="$1"
		local first_line="${block%%$'\n'*}"
		if [[ "$first_line" =~ ^'# name: ' ]]; then
			echo "${block#*$'\n'}"
		else
			echo "$block"
		fi
	}

	send_cmds() {
		local target="$1"
		local block="$2"
		local joined=""
		while IFS= read -r cmd; do
			[[ -z "$cmd" ]] && continue
			[[ -n "$joined" ]] && joined+=" && "
			joined+="$cmd"
		done <<< "$block"
		[[ -n "$joined" ]] && tmux send-keys -t "$target" "$joined" Enter
	}

	# First window already exists (index 1); rename it if a name is specified
	local name
	name="$(get_window_name "${panes[0]}")"
	[[ -n "$name" ]] && tmux rename-window -t "${session}:1" "$name"
	local cmds
	cmds="$(strip_name_line "${panes[0]}")"
	[[ -n "$cmds" ]] && send_cmds "${session}:1" "$cmds"

	# Create remaining windows
	for (( i=1; i<total; i++ )); do
		local win_idx=$(( i + 1 ))
		name="$(get_window_name "${panes[$i]}")"
		if [[ -n "$name" ]]; then
			tmux new-window -t "${session}:${win_idx}" -n "$name" -c "$dir"
		else
			tmux new-window -t "${session}:${win_idx}" -c "$dir"
		fi
		cmds="$(strip_name_line "${panes[$i]}")"
		[[ -n "$cmds" ]] && send_cmds "${session}:${win_idx}" "$cmds"
	done

	# Focus window 1
	tmux select-window -t "${session}:1"
}
