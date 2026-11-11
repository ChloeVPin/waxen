# fish completion for waxen

complete -c waxen -f

complete -c waxen -n "__fish_use_subcommand" -a diagnose -d "Explain whether macOS is right to block an app"
complete -c waxen -n "__fish_use_subcommand" -a evidence -d "Show raw evidence for an application, disk image, or installer package"
complete -c waxen -n "__fish_use_subcommand" -a finder -d "Install or remove the Finder Quick Action"
complete -c waxen -n "__fish_use_subcommand" -l help -s h -d "Show help"
complete -c waxen -n "__fish_use_subcommand" -l version -s V -d "Print the waxen version"

complete -c waxen -n "__fish_seen_subcommand_from finder; and not __fish_seen_subcommand_from install uninstall" -a install -d "Add \"Why Won't This Open?\" to Finder"
complete -c waxen -n "__fish_seen_subcommand_from finder; and not __fish_seen_subcommand_from install uninstall" -a uninstall -d "Remove the Quick Action"

set -l __waxen_target "not __fish_seen_subcommand_from finder"
complete -c waxen -n "$__waxen_target" -l details -d "Print the full evidence report"
complete -c waxen -n "$__waxen_target" -l verbose -d "Full report plus suggested repair actions"
complete -c waxen -n "$__waxen_target" -l share -d "Print the verdict as Markdown for an issue"
complete -c waxen -n "$__waxen_target" -l json -d "Emit a machine readable JSON report"
complete -c waxen -n "$__waxen_target" -l no-color -d "Disable colored output"

complete -c waxen -n "$__waxen_target" -a "(__fish_complete_suffix .app)" -d "Application bundle"
complete -c waxen -n "$__waxen_target" -a "(__fish_complete_suffix .dmg)" -d "Disk image"
complete -c waxen -n "$__waxen_target" -a "(__fish_complete_suffix .pkg)" -d "Installer package"
