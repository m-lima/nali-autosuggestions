
#--------------------------------------------------------------------#
# Async                                                              #
#--------------------------------------------------------------------#

zmodload zsh/system

_zsh_autosuggest_async_request() {
	typeset -g _ZSH_AUTOSUGGEST_ASYNC_FD _ZSH_AUTOSUGGEST_CHILD_PID

	# If we've got a pending request, cancel it
	if [[ -n "$_ZSH_AUTOSUGGEST_ASYNC_FD" ]] && { true <&$_ZSH_AUTOSUGGEST_ASYNC_FD } 2>/dev/null; then
		# Close the file descriptor and remove the handler
		exec {_ZSH_AUTOSUGGEST_ASYNC_FD}<&-
		zle -F $_ZSH_AUTOSUGGEST_ASYNC_FD

		# Zsh will make a new process group for the child process only if job
		# control is enabled (MONITOR option)
		if [[ -o MONITOR ]]; then
			# Send the signal to the process group to kill any processes that may
			# have been forked by the suggestion strategy
			kill -TERM -$_ZSH_AUTOSUGGEST_CHILD_PID 2>/dev/null
		else
			# Kill just the child process since it wasn't placed in a new process
			# group. If the suggestion strategy forked any child processes they may
			# be orphaned and left behind.
			kill -TERM $_ZSH_AUTOSUGGEST_CHILD_PID 2>/dev/null
		fi
	fi

	# Fork a process to fetch a suggestion and open a pipe to read from it
	exec {_ZSH_AUTOSUGGEST_ASYNC_FD}< <(
		# Tell parent process our pid
		echo $sysparams[pid]

		# Fetch and print the suggestion
		local capped_history_index
		local suggestion
		_zsh_autosuggest_fetch_suggestion "$@"
		echo -nE "$capped_history_index" "$suggestion"
	)

	# Read the pid from the child process
	read _ZSH_AUTOSUGGEST_CHILD_PID <&$_ZSH_AUTOSUGGEST_ASYNC_FD

	# When the fd is readable, call the response handler
	zle -F "$_ZSH_AUTOSUGGEST_ASYNC_FD" _zsh_autosuggest_async_response
}

# Called when new data is ready to be read from the pipe
# First arg will be fd ready for reading
# Second arg will be passed in case of error
_zsh_autosuggest_async_response() {
	if [[ -z "$2" || "$2" == "hup" ]]; then
		# Read everything from the fd and give it as a suggestion
		local raw_input=`cat <&$1`

		# Break up the output
		# - (z) split into words using shell parsing to find the words
		local input=(${(z)raw_input})
		local capped_history_index="${input[1]}"
		local suggestion="${input[2,-1]}"

		zle autosuggest-suggest -- "$capped_history_index" "$suggestion"

		# Close the fd
		exec {1}<&-
	fi

	# Always remove the handler
	zle -F "$1"
}
