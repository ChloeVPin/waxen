# GitHub Action

Run waxen in CI so a macOS job fails when the built `.app`, `.dmg`, or `.pkg` would be blocked. The file is not modified.

```yaml
- uses: ChloeVPin/waxen@main
  with:
    path: dist/MyApp.dmg
```

Use a `macos-*` runner. The plain-language verdict is added to the job summary.

If `binary` is empty, the action uses `waxen` already on PATH. If it is not installed, the action builds it from its checked-out Swift source.

From a checkout of this repo you can provide the binary directly:

```yaml
- uses: ./
  with:
    path: dist/MyApp.dmg
    binary: .build/release/waxen
```

Use `main` until a rebranded Action release is tagged. The CLI version (for example 0.3.0) is the tool release.

## Inputs

| Name | Required | Default | Meaning |
| --- | --- | --- | --- |
| `path` | yes | | Path to an `.app`, `.dmg`, or `.pkg` |
| `binary` | no | empty | Path to a `waxen` executable. Empty uses PATH or builds from source |
| `json` | no | `true` | Write a JSON report |
| `report-path` | no | `waxen-report.json` | Where to write the report |
| `fail-on-blocker` | no | `true` | Fail the job when waxen exits `1` |
| `fail-on-error` | no | `true` | Fail the job on usage or tool errors |

## Outputs

| Name | Meaning |
| --- | --- |
| `exit-code` | waxen process exit code |
| `launch-status` | `clean`, `blocked`, or `inconclusive` when the report is JSON |
| `verdict` | `trusted`, `cautious`, `unsigned`, `tampered`, `broken`, or `unknown` |
| `report-path` | Path to the written report |

## License

MIT. Same terms as waxen.
