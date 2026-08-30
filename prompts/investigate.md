# Investigate

```text
/investigate
```

Multi-step investigation with live evidence. Do not invent findings.

Optional focus:

```text
<question, symptom, or area: scan, duplicates, Photos, deploy, website, …>
```

## Execute

1. Map the question to modules (`DiskScannerKit`, `PhotosKit`, app UI, website, scripts).
2. Read code + run commands (`swift test`, `npm run ci`, logs) as needed.
3. Cross-check `docs/architecture.md` and `.cursor/rules/diskwise-macos-architecture.mdc`.
4. Produce structured output before recommending a fix.

## Output

```text
Finding:
- …
Evidence:
- …
Risk:
- …
Recommendation:
- …
```
