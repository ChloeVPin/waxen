# Security Policy

waxen only inspects files. It must never remove quarantine, change Gatekeeper, edit privacy databases, disable system protections, install certificates, re-sign apps, or upload what you point it at.

The one exception is `waxen finder install`, which you run on purpose. It writes a single Quick Action to `~/Library/Services/Why Won't This Open.workflow` and turns on that one entry in the Services settings (`pbs` preferences), so Finder shows it under Quick Actions. `waxen finder uninstall` removes both, and only if waxen created the workflow. The Quick Action passes report text to `osascript` as arguments, never as script source, so a file name can't run code.

## Report a vulnerability

Do not file a public issue for an undisclosed vulnerability.

Use GitHub’s private security advisory on this repository. Include:

1. A short description
2. The affected version or commit
3. Steps to reproduce that do not need private data
4. What you expected
5. What happened
6. A JSON report or other evidence, with secrets removed

Strip personal paths, signing identities, certificate material, private source, and proprietary app data before you attach anything.

## Safe testing

Work on copies. Do not turn Gatekeeper off, disable system protections, strip quarantine from production files, change TCC, or launch unknown apps in order to test waxen.

## Limits

A report is only as complete as the tools and permissions on that Mac. It is not a substitute for trying the real download on a clean Apple Silicon Mac.
