function __rich_ri_complete
    set -l words (commandline -opc)
    set -e words[1]
    command rich-ri --complete $words (commandline -ct) 2>/dev/null
end

complete -c rich-ri -f -a '(__rich_ri_complete)'
