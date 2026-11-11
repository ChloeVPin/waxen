# Changelog

All notable changes to waxen are documented here.

## 0.3.0

The default output is now a short plain-language verdict. `--details` prints the full report.

### Rebrand

Renamed the project, executable, Swift modules, and GitHub repository to Waxen. Update Action references to `ChloeVPin/waxen`; GitHub does not redirect Action calls from renamed repositories. Homebrew distribution is pending; build from source for now.

### Added

1. A verdict as the default output: one of `trusted`, `cautious`, `unsigned`, `tampered`, `broken`, or `unknown`, with who signed the app, whether Apple checked it, and where it was downloaded from
2. `waxen <path>` works without a subcommand
3. `--details` prints the full report that `diagnose` used to print
4. `--share` prints a Markdown verdict for bug reports, with file names but no folder paths
5. `waxen finder install` / `uninstall` adds or removes a Finder Quick Action, "Why Won’t This Open?", that shows the verdict in a native alert
6. The GitHub Action writes the verdict to the job summary and exposes a `verdict` output
7. Exit code `73` when the Quick Action can't be written

### Changed

1. `diagnose` text output is the verdict. Use `--details` (or `--verbose`) for the old report. JSON output and exit codes are unchanged
2. Color is used only when stdout is a terminal and `NO_COLOR` is unset
3. The GitHub Action passes `--details` when `json: false`, so text reports stay complete

## 0.2.2

### Added

1. `waxen --version` and `-V`
2. Generated `.pkg` fixture plus diagnosis-path, CI, and integration coverage for installer packages

### Changed

1. The GitHub Action lives only in this repository. Use `ChloeVPin/waxen@main`
2. Homebrew tap, man page, and CLI version are aligned at 0.2.2
3. Bash completion offers flags after `diagnose` / `evidence`

## 0.2.1

### Added

1. GitHub Action that runs `waxen diagnose` on a `.app`, `.dmg`, or `.pkg` and fails the job on a confirmed blocker
2. One-line CI snippet: `uses: ChloeVPin/waxen@main`

## 0.2.0

### Added

1. Read-only `.dmg` inspection: the image is mounted without modification, then the nested `.app` is diagnosed
2. Read-only `.pkg` inspection: the package is expanded into a temporary directory, then the nested `.app` is diagnosed
3. Container evidence and findings with stable identifiers (`container.mounted`, `container.expanded`, `container.app-found`, `container.no-app`, `container.unavailable`, `container.quarantine`)
4. Optional `container` object on the versioned JSON report
5. Diagnosis-path tests for a clean app, an unsigned app, quarantine-as-trigger, and a generated disk image

### Changed

1. CLI usage, man page, and completions accept `.app`, `.dmg`, and `.pkg`
2. Exit code `65` now means the target is outside `.app` / `.dmg` / `.pkg`, not "not an .app"

## 0.1.1

### Added

1. Bash completion script in `completions/waxen.bash`
2. Zsh completion script in `completions/_waxen`
3. Fish completion script in `completions/waxen.fish`
4. Man page in `man/waxen.1`
5. Homebrew formula installs completions and the man page

## 0.1.0

### Added

1. Read-only `.app` bundle diagnosis for Apple Silicon macOS
2. Bundle structure and `Info.plist` validation
3. Bounded Mach-O inspection with arm64 and x86_64 detection
4. Public Security.framework static code validation on macOS
5. Strict code-signature evidence from `codesign`
6. Explicit nested code inspection with bounded parallelism
7. Signing identity, Team ID, Hardened Runtime, and entitlement evidence
8. Stapled ticket validation through `xcrun stapler`
9. Gatekeeper assessment through `spctl`
10. Quarantine parsing through `xattr`
11. Causal diagnosis fields that separate primary findings from triggers
12. Stable JSON output and exit codes
13. Generated parser fixtures and macOS CI validation
14. MIT licensing and contributor security guidance

### Known limitations

1. TCC, sandbox, App Translocation, and unified log correlation are not implemented
2. ZIP inspection is not implemented
3. Notarization submission logs are not queried
4. A clean external Mac is still required for final distribution validation
5. Gatekeeper and Apple policy services may be unavailable or version dependent
