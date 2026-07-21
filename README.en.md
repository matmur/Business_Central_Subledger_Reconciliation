> [🇩🇪 Deutsch](README.md) | 🇬🇧 English

# Sub-Ledger Reconciliation for Business Central

![Business Central](https://img.shields.io/badge/Business%20Central-28.3-0078D4)
![AL Runtime](https://img.shields.io/badge/AL%20runtime-17.0-5C2D91)
![Localization](https://img.shields.io/badge/localization-DE-lightgrey)
![License](https://img.shields.io/badge/license-MIT-green)

A small, focused **Business Central (AL)** extension that catches **sub-ledger drift** — when the customer receivables sub-ledger stops agreeing with its G/L control account.

For each **G/L receivables control account** it compares the **open customer ledger entries** (summed remaining, LCY) against the **account balance**. Any non-zero difference is drift — a manual G/L posting, a reassigned posting group, a partial reversal. Pure aggregation, no judgment calls.

> **Demo:** _2-minute recording goes here — a row flips to red after a manual G/L posting._

## Why it matters

The sub-ledger and G/L are supposed to move together. Post **directly** to a receivables control account, or reassign a posting group, and they silently diverge — usually caught only at period close. This surfaces it on demand or on a schedule, any time.

## The design decision that matters

**Reconcile per control account, not per posting group.** Several posting groups can map to the *same* receivables account (e.g. `EU` and `AUSLAND` → `1203`). Comparing one group's partial sub-ledger to the account's full balance would report phantom drift. So the engine folds every group's open sub-ledger into its account and compares **once per account**, where the numbers are actually comparable.

## Objects

| Object | ID | Role |
|---|---|---|
| enum `Recon Status` | 50100 | Balanced / Drift Detected |
| table `Recon Finding` | 50101 | One finding per account per run (`Delta`/`Status` derived in `OnInsert`) |
| codeunit `Sub-Ledger Recon Mgt.` | 50102 | Core reconciliation logic |
| codeunit `Recon Check Job` | 50103 | Job Queue wrapper (schedulable) |
| page `Recon Findings` | 50104 | List UI + run action + red/green styling |

## Under the hood

- **Extension-only, upgrade-safe.** No base objects modified; it only *reads* base data (`Customer Posting Group`, `Cust. Ledger Entry`, `G/L Account`) through their public surface.
- **FlowFields, handled correctly.** `Remaining Amt. (LCY)` and G/L `Balance` are FlowFields, not stored columns — so they can't be `CalcSums`'d. The engine uses `SetAutoCalcFields` (server computes during the fetch — one set-based query, no N+1) and `CalcFields` for the single account balance.
- **Data never leaves the tenant.** Findings only — no external calls.
- **Schedulable.** Codeunit 50103 runs as a Job Queue Entry; the same core logic serves both the page button and the scheduler.

## Run it

Needs VS Code + the **AL Language** extension (17.0) and a BC **28.3** sandbox.

1. Open the folder in VS Code → **AL: Download symbols**.
2. `Ctrl+Shift+B` to compile, or **F5** to publish and launch.
3. Open **Reconciliation Findings** → **Run Reconciliation Check**.

**See drift live:** post a manual General Journal line straight to a receivables control account, then re-run — that row turns red with a non-zero delta.

To schedule: **Job Queue Entries → New**, Codeunit `50103`, set a recurrence, Status = Ready.

> `50100–50149` is a development ID range; an AppSource release needs a Microsoft-registered range.

## License

[MIT](LICENSE) © 2026 Matthias Mur
