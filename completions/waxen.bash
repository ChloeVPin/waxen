# bash completion for waxen
# source this file from .bashrc or place it in the bash-completion directory

_waxen_complete() {
    local cur prev
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD - 1]}"

    if [[ ${COMP_CWORD} -eq 1 ]]; then
        if [[ "${cur}" == -* ]]; then
            COMPREPLY=($(compgen -W "--help -h --version -V" -- "${cur}"))
        else
            COMPREPLY=($(compgen -W "diagnose evidence finder" -- "${cur}") $(compgen -f -- "${cur}"))
        fi
        return 0
    fi

    if [[ "${COMP_WORDS[1]}" == "finder" ]]; then
        if [[ ${COMP_CWORD} -eq 2 ]]; then
            COMPREPLY=($(compgen -W "install uninstall" -- "${cur}"))
        fi
        return 0
    fi

    if [[ "${cur}" == -* ]]; then
        COMPREPLY=($(compgen -W "--details --verbose --share --json --no-color --help -h" -- "${cur}"))
        return 0
    fi

    COMPREPLY=($(compgen -f -- "${cur}"))
}

complete -F _waxen_complete waxen
