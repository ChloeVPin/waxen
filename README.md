# Waxen

> **“MyApp” is damaged and can’t be opened. You should move it to the Trash.**

macOS shows that message for apps that really are broken, and also for apps that are fine but unsigned. Most people search the error, paste `xattr -cr` from a forum, and switch off a safety check without knowing whether it was protecting them.

waxen tells you whether macOS is right. It answers one question: **who made this app, and has anyone touched it since?**

```sh
git clone https://github.com/ChloeVPin/waxen.git
cd waxen
swift build -c release
install -m 755 .build/release/waxen /usr/local/bin/waxen
waxen ~/Downloads/MyApp.dmg
```

```
● Nobody signed this app.

  MyApp.app has no signature at all, so macOS can't tell who made it or
  check that nothing changed. macOS calls unsigned downloads "damaged".
  Open-source and hobby apps are often unsigned. A missing signature says
  nothing about whether the app is safe.

  Made by           Nobody (unsigned)
  Checked by Apple  No
  Downloaded        Safari · 3 Nov 2026

  → Only open it if you trust where you got it. Try opening it once, then go
    to System Settings → Privacy & Security and click Open Anyway.
```

A modified app gets a different answer:

```
✗ Don't open this app.

  MyApp.app no longer matches what Jane Doe signed. Something inside it
  changed after signing: a damaged download, a bad build, or tampering.
  waxen can't tell which.

  Made by           Jane Doe (ABCDE12345)
  Checked by Apple  Once, but the app has changed since

  → Delete it and download a fresh copy from Jane Doe's own website.
```

## What you can get back

| Verdict | Meaning |
| --- | --- |
| ✓ This app checks out | Signed, unchanged, and accepted by macOS. If it still won't open, the problem is inside the app. |
| ● Apple hasn't checked this app | Signed and unchanged, but not notarized. macOS asks before opening it. |
| ● Nobody signed this app | macOS can't tell who made it. |
| ✗ Don't open this app | The app changed after it was signed, or Apple revoked its certificate. |
| ✗ This app is broken | Files are missing or malformed. It can't run. |
| ? Couldn't check everything | Some checks returned no result. `--details` shows which. |

## It only reads

waxen never changes the app you check. It doesn't remove quarantine, change Gatekeeper, re-sign anything, or use the network, and it collects no data. It reads what macOS already knows, using Apple's own tools (`codesign`, `spctl`, `stapler`, `xattr`), and explains it.

Disk images are mounted read-only and installers are unpacked into a temporary folder, so you can check a download before you open it.

## Right-click in Finder

```sh
waxen finder install
```

Then right-click any app, `.dmg`, or `.pkg` and choose **Quick Actions → Why Won’t This Open?** You get the same answer in a normal Mac alert, with a button to copy the report. `waxen finder uninstall` removes it. This is the only command that writes anything: one workflow in `~/Library/Services`, plus the setting that shows it in Finder's right-click menu.

## More detail

```sh
waxen MyApp.app --details   # every check, finding, and piece of evidence
waxen MyApp.app --share     # Markdown to paste into a bug report
waxen MyApp.app --json      # stable machine-readable report
```

The JSON schema is [Schemas/diagnosis-v1.json](Schemas/diagnosis-v1.json). Exit code `1` means a confirmed blocker. The other exit codes are in `man waxen`.

## For people who ship Mac apps

When users report that your app "is damaged", ask them for the waxen report instead of guessing. Add this to your README or issue template:

```markdown
**App won't open?** Run this and paste the result in an issue:

    # Build Waxen from https://github.com/ChloeVPin/waxen first.
    waxen ~/Downloads/YourApp.dmg --share | pbcopy
```

The report lists the signer, notarization, where the file came from, and the exact fix for you. It contains file names but no folder paths.

To check a release before publishing it, run waxen in CI on the exact file you'll ship:

```yaml
- uses: ChloeVPin/waxen@main
  with:
    path: dist/YourApp.dmg
```

The job fails on a confirmed blocker, and the verdict appears in the job summary. See [action/README.md](action/README.md).

## Build from source

```sh
swift build -c release
.build/release/waxen /Applications/Calculator.app
```

Requires macOS 13 or newer. Which checks are available depends on the macOS version, permissions, and the Apple tools installed.

## License

[MIT](LICENSE)
