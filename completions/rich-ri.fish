function __rich_ri_complete
    set -l words (commandline -xpc 2>/dev/null)
    or set words (commandline -opc | string unescape)
    set -e words[1]
    set -l current (commandline -ct | string unescape)
    command rich-ri --complete $words "$current" 2>/dev/null
end

complete -c rich-ri -f -a '(__rich_ri_complete)'
