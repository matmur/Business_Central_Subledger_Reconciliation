> [🇩🇪 Deutsch](README.md) | 🇬🇧 English

# Sub-Ledger Reconciliation for Business Central

![Business Central](https://img.shields.io/badge/Business%20Central-28.3-0078D4)
![AL Runtime](https://img.shields.io/badge/AL%20runtime-17.0-5C2D91)
![Localization](https://img.shields.io/badge/localization-DE-lightgrey)
![License](https://img.shields.io/badge/license-MIT-green)

A small, focused **Business Central (AL)** extension that catches **sub-ledger drift** — when the customer receivables sub-ledger stops agreeing with its G/L control account.

For each **G/L receivables control account** it compares the **open customer ledger entries** (summed remaining, LCY) against the **account balance**. Any non-zero difference is drift — a manual G/L posting, a posting made without a customer, a partial reversal. Pure aggregation, no judgment calls.

## Demo

A run against the BC **28.3** sandbox (DE localization, CRONUS). The extension changes **nothing** in the ledgers — it reads the data live and only surfaces drift.

**Starting point — balanced.** Sub-ledger and G/L agree, `Delta` = 0,00:

![Reconciliation Findings with all rows green, delta 0,00, status "Balanced"](docs/balanced.png)

**After a wrong posting — drift detected.** A manual entry is posted straight to receivables control account `1202` (INLAND). That pushes the sub-ledger and G/L apart — the next run surfaces it, the row turns red, `Delta` = −500,00:

![Reconciliation Findings with the INLAND row in red, delta −500,00, status "Drift Detected"](docs/drift-detected.png)

`AUSLAND` and `EU` both map to account `1203` and stay balanced — exactly the case the per-account reconciliation handles (see below).

## Why it matters

The sub-ledger and G/L are supposed to move together. Post **directly** to a receivables control account without naming a customer and they silently diverge — usually caught only at period close. This surfaces it on demand or on a schedule, any time.

## How drift happens

| Cause | Requires "Direct Posting"? |
|---|---|
| Manual G/L posting with no customer (the demo case, because it is the easiest to reproduce) | Yes |
| Data migration or API integration writes straight to the G/L, bypassing the standard posting routine | No |
| Partial reversal where only one side was unapplied | No |

The check doesn't test whether a rule was broken, but whether the numbers still agree — regardless of the cause.

A **posting group reassigned after the fact** is *not* one of these causes, but tools that read the account from the current setup report it as one. See the second design decision.

## The two design decisions

**1. Reconcile per control account, not per posting group.** Several posting groups can map to the *same* receivables account (e.g. `EU` and `AUSLAND` → `1203`). Comparing one group's partial sub-ledger to the account's full balance would report phantom drift. So the comparison happens **once per account**, where the numbers are actually comparable.

**2. The account comes from the posting, not from the setup.** An entry's posting group is fixed when it is posted; the account behind that group can be changed later. Reading the account from the current setup measures old entries against a new account and makes **two** accounts report drift — the one that lost the entries and the one that gained them. Both figures are arithmetically correct and both reports are wrong.

Instead, for every open entry the G/L line of the same transaction is located (same transaction number, source type Customer, same customer number) and its account is used. The standard report 33 "Reconcile Customer and Vendor Accounts" works from the setup and shows the behaviour described above.

**Which accounts get checked** comes primarily from the receivables accounts named by the customer posting groups. G/L accounts carrying the *Accounts Receivable* subcategory are added on top — a field that may be maintained, but often is not. Where it is empty it contributes nothing; where it is filled, an account a posting group was moved away from stays recognisable. A free extra, not a guarantee — see *Limitations*.

## Limitations

- **No history.** Every run shows the state as of today and replaces the previous one. A past cut-off date would require reconstructing which entries were open on that day.
- **An account that is neither named by a posting group nor classified as receivables is not checked** — even with entries still sitting on it. Since the classification is unmaintained in many tenants, in practice: remove an account from the setup entirely and it drops out of the check. BC records nowhere that an account once served as a control account, and within a transaction the receivables line cannot be told apart from revenue and tax lines without that list.
- **Per-entry cost.** Resolving the account costs one query per open entry. Accepted deliberately at this scope; with a very large open-item count the attribution would need to be built differently.

## Objects

| Object | ID | Role |
|---|---|---|
| enum `Recon Status` | 50100 | Balanced / Drift Detected |
| table `Recon Finding` | 50101 | One finding per account per run (`Delta`/`Status` derived in `OnInsert`) |
| codeunit `Sub-Ledger Recon Mgt.` | 50102 | Core reconciliation logic |
| codeunit `Recon Check Job` | 50103 | Job Queue wrapper (schedulable) |
| page `Recon Findings` | 50104 | List UI + run action + red/green styling |
| permissionset `Sub-Ledger Recon` | 50105 | Permissions, so users do not need SUPER |
| codeunit `Recon Finding Tests` | 50149 | Tests for delta, status and account resolution |

## Under the hood

- **Extension-only, upgrade-safe.** No base objects modified; it only *reads* base data (`Customer Posting Group`, `Cust. Ledger Entry`, `G/L Entry`, `G/L Account`, `G/L Account Category`) through their public surface.
- **FlowFields, handled correctly.** `Remaining Amt. (LCY)` and G/L `Balance` are FlowFields, not stored columns — so they can't be `CalcSums`'d. Across the set of entries the server computes them during the fetch (`SetAutoCalcFields`); for the single account balance `CalcFields` is used.
- **Costs stated plainly.** Reading the remaining amounts stays set-based; resolving the account does not — that is one query per open entry. See *Limitations*.
- **Derivation lives in the table.** `Delta` and `Status` are derived in the finding table's `OnInsert`, not in the caller, so every row is consistent the moment it is written, no matter who writes it.
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

## Contact

**Matthias Mur** — .NET/SQL developer with a background in production ERP systems (custom .NET extensions, billing and service-management logic, SQL validation, live production debugging), now building on Business Central (AL). Available for freelance BC and ERP work, 100% remote across DACH.

[LinkedIn](https://www.linkedin.com/in/matthias-mur/) · [matthias@mur-consulting.com](mailto:matthias@mur-consulting.com)

## License

[MIT](LICENSE) © 2026 Matthias Mur
