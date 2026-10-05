# fish completion for rich-ri
#
# Install it where fish loads it the first time it is needed:
#
#   rich-ri --completion=fish > $__fish_config_dir/completions/rich-ri.fish

function __rich_ri_complete
    set -l words (commandline -xpc 2>/dev/null)
    or set words (commandline -opc | string unescape)
    set -e words[1]
    set -l token (commandline -ct)
    set -l current (commandline -ct | string unescape)
    set -l lines (command rich-ri --complete $words "$current" 2>/dev/null)
    set -q lines[1]
    or return
    set -l directive $lines[-1]
    set -e lines[-1]
    switch $directive
        case :files
            __rich_ri_paths __fish_complete_path "$token"
        case :directories
            __rich_ri_paths __fish_complete_directories "$token"
        case '*'
            set -q lines[1]
            and printf '%s\n' $lines
    end
end

# fish completes a path by itself, and replaces the whole word: the path that
# follows "--option=" is completed alone and the option put back before it.
function __rich_ri_paths --argument-names complete token
    set -l option (string match -r -- '^--[^=]+=' "$token")
    $complete (string replace -r -- '^--[^=]+=' '' "$token") | string replace -r -- '^' "$option"
end

complete -c rich-ri -f -a '(__rich_ri_complete)'
