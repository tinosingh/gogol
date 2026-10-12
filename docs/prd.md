# PRD: gogol, local-first EU bookkeeping

- **Status:** Draft v0.3, awaiting owner approval
- **Owner:** @tinosingh
- **Last updated:** 2026-10-11
- **Repository:** <https://github.com/tinosingh/gogol>

This document is the single source of truth for what gogol does and why: its users, requirements, scope, release plan and open product decisions. How it is built lives in [`PROMPT.md`](../PROMPT.md) (later `CLAUDE.md`) and in the ADRs under `docs/adr/`. Those documents cite requirement IDs from here instead of restating them.

## 1. Problem

Small European entities must keep books, usually double-entry, and retain them for years: typically 5–10, depending on the member state and the type of record. Many bookkeeping tools keep those books on the vendor's servers, require an account and a subscription, and stop working offline. Desktop tools tie the books to one machine. gogol keeps the books in the user's browser, with no backend and no account. It works offline, is open source, and leaves the user holding the only copy and the only keys.

## 2. Users

| User | Situation | Needs most |
| --- | --- | --- |
| Sole proprietor or freelancer | Keeps their own books; VAT-registered or in the SME exemption scheme | Fast entry, VAT data, a simple year-end |
| Association treasurer | Often a volunteer; the role may change hands yearly; activities may be partly VAT-exempt | Easy handover of the file, an audit trail, clear reports |
| Bookkeeper of a micro or small company | Keeps the books of a limited company (e.g. GmbH, SARL, BV) | Statutory statements in the national layout, VAT-return data, audit-file export |
| External accountant or auditor | Receives the file or exports at year-end | Open formats, verifiable integrity, standard audit files |

## 3. Goals and success measures

gogol collects no telemetry (SEC-6), so success is measured with tests, benchmarks and reviews rather than usage analytics.

| ID | Goal | Measured by |
| --- | --- | --- |
| G1 | A bookkeeper keeps one entity's books for a full fiscal year in the reference jurisdiction, entirely in the browser. | A moderated test: a bookkeeper new to the app records a month of sample transactions and produces the trial balance and VAT summary unaided. |
| G2 | Statements and VAT data are correct for the reference jurisdiction. | Golden-file fixtures reviewed and signed off by a qualified accountant of that jurisdiction before v1.0. |
| G3 | The books cannot silently become inconsistent. | Property-based tests prove every LED requirement in CI. |
| G4 | The user keeps sole custody of the data. | An end-to-end test asserts that no request reaches an origin outside the allowlist; encryption tests find no plaintext at rest. |
| G5 | Records survive device loss and browser eviction. | Backup and restore round trips pass in every supported engine. |
| G6 | The app is fast and accessible. | NFR-1 benchmarks and automated accessibility checks pass in CI; a manual WCAG 2.2 AA audit is done before v1.0. |

## 4. Scope

v1 serves micro and small undertakings, sole proprietors and associations in one reference jurisdiction (D1).

### 4.1 Regulatory scope

- Directive 2013/34/EU governs the annual accounts of limited-liability undertakings (Annexes I–II). Member states transpose it with national options. Its size thresholds were raised by Delegated Directive (EU) 2023/2775. Sole proprietors and associations fall under national law, which sometimes allows cash-basis or simplified bookkeeping.
- VAT follows Directive 2006/112/EC. The VAT model must be able to represent:
  - standard and reduced rates, and zero rates where a member state applies them (in EU law, an exemption with the right to deduct input VAT);
  - exempt supplies without that right (Arts. 132–137), with pro-rata deduction for mixed activities (Arts. 173–175);
  - reverse charge, intra-EU supplies (Art. 138) and intra-EU acquisitions;
  - the SME exemption scheme (Directive (EU) 2020/285), which matters most for sole traders and associations;
  - optional cash accounting (Art. 167a).

  v1 implements the subset that the reference jurisdiction and entity type need. It produces VAT summaries per period, and the data for the EC Sales List (Art. 262) until ViDA's digital reporting replaces it.
- One generic double-entry core. Everything specific to a jurisdiction or entity type lives in a jurisdiction module:
  - chart-of-accounts templates (e.g. SKR03/04, PCG);
  - report layouts: the Annex III/IV balance sheet and Annex V/VI P&L, plus the abridged small and micro versions under Arts. 14 and 36;
  - VAT-return box mappings and the national VAT options in use (e.g. cash accounting, SME thresholds);
  - rounding and numbering rules;
  - retention periods per type of record;
  - audit-file exports (e.g. SAF-T variants, FEC, GoBD data access).
- v1 ships the generic core and the reference jurisdiction only. The module interface is derived from that one concrete implementation, not designed for all 27 member states up front.

### 4.2 Functional requirements

Priority is for v1: Must, Should or Could. Phase refers to the release plan (section 7). Status is `TODO`, `WIP`, `DONE <commit> (<date>)` or `DROPPED (<reason>)`.

#### Chart of accounts

| ID | Requirement | Acceptance criterion | Priority | Phase | Status |
| --- | --- | --- | --- | --- | --- |
| COA-1 | A hierarchical chart of accounts, created from the reference jurisdiction's template and extensible by the user. | A new entity starts with the template; users can add accounts under any parent. | Must | 1 | TODO |
| COA-2 | Accounts carry roles (e.g. VAT payable, retained earnings) that features rely on, so a customized chart keeps working. | Assigning a role to a different account redirects the affected postings without code changes. | Must | 1 | TODO |

#### Ledger

| ID | Requirement | Acceptance criterion | Priority | Phase | Status |
| --- | --- | --- | --- | --- | --- |
| LED-1 | Every posted entry balances: at least one debit line and one credit line, and total debits equal total credits in the functional currency. | Posting an unbalanced entry is rejected. | Must | 1 | TODO |
| LED-2 | Posted entries never change. A correction is a reversal plus a new entry, both referencing the original. | Any edit or deletion of a posted entry is rejected; the general ledger shows the reversal links. | Must | 1 | TODO |
| LED-3 | Each posted entry gets a gapless number in posting order, scoped by the jurisdiction's rule (e.g. per journal and fiscal year). Drafts get none. | No gaps or duplicates after any sequence of postings and reversals. | Must | 1 | TODO |
| LED-4 | Closed periods and fiscal years accept no postings. | Posting into a closed period is rejected. | Must | 1 | TODO |
| LED-5 | An account that has postings can be deactivated but never deleted or given a different type. | Deleting or retyping it is rejected; a deactivated account takes no new postings. | Must | 1 | TODO |
| LED-6 | Changes to master data (accounts, VAT codes, settings) are recorded in an audit log with the old value, the new value and the time. | Every master-data change appears in the log. | Must | 1 | TODO |
| LED-7 | Amounts are exact to the currency's minor unit, rounding follows the jurisdiction's rule, and amounts are entered in the user's locale format. | Property tests find no rounding drift; `1.234,56` and `1,234.56` parse correctly in their locales. | Must | 1 | TODO |
| LED-8 | An entry's accounting date never shifts with the device's time zone or clock. | Entries keep their period when the time zone changes. | Must | 1 | TODO |
| LED-9 | Reports for past periods use the rates, layouts and mappings valid at the time; each posted line keeps the VAT rate and treatment it used. | A rate change from a later date leaves earlier reports unchanged. | Must | 4 | TODO |
| LED-10 | Changes to posted history can be detected against a hash-chain head recorded outside the file (printed per RPT-5). The limits of this detection are documented. | Editing a posted entry with an external tool is detected on open; a file whose chain was recomputed no longer matches a previously printed head. | Must | 1 | TODO |
| LED-11 | Entries can be saved as drafts, edited freely and posted later. | Drafts are excluded from balances and reports. | Must | 1 | TODO |
| LED-12 | Opening balances can be entered or imported when starting an entity or moving from other software. | Imported opening balances balance and appear in the first period's trial balance. | Must | 1 | TODO |
| LED-13 | Several journals (e.g. general, bank, sales, purchases). | Each journal numbers its entries per LED-3. | Should | 1 | TODO |

#### VAT

| ID | Requirement | Acceptance criterion | Priority | Phase | Status |
| --- | --- | --- | --- | --- | --- |
| VAT-1 | VAT codes and rates are reference data with validity dates and cover what the reference jurisdiction needs from section 4.1: rates, exemptions with and without the right to deduct, reverse charge, intra-EU supplies and acquisitions. | A posting uses the rate valid at its tax point; a rate change needs no code change. | Must | 4 | TODO |
| VAT-2 | A VAT summary per period. | Matches golden fixtures reviewed by an accountant (G2). | Must | 4 | TODO |
| VAT-3 | EC Sales List (recapitulative statement) data. | Matches golden fixtures. | Must | 4 | TODO |
| VAT-4 | Totals mapped to the boxes of the reference VAT return (data only; no electronic filing). | Box totals match golden fixtures. | Must | 4 | TODO |
| VAT-5 | The VAT options the reference entity type needs: SME exemption, cash accounting, pro-rata deduction. | Each enabled option has golden fixtures. | Should | 4 | TODO |

#### Reports

| ID | Requirement | Acceptance criterion | Priority | Phase | Status |
| --- | --- | --- | --- | --- | --- |
| RPT-1 | Trial balance for any period. | Nets to zero and matches golden fixtures. | Must | 1 | TODO |
| RPT-2 | General ledger for any account and period. | Every posted line appears exactly once. | Must | 1 | TODO |
| RPT-3 | Journal reports. | Every posted entry appears exactly once, in number order. | Must | 3 | TODO |
| RPT-4 | Balance sheet and P&L in the generic layout and the reference jurisdiction's layouts, including the abridged small and micro versions. | Match golden fixtures signed off by an accountant (G2). | Must | 3 | TODO |
| RPT-5 | Every report and export states its period, its generation time and the hash-chain head. | Present on every report and export. | Must | 3 | TODO |

#### Data custody and durability

| ID | Requirement | Acceptance criterion | Priority | Phase | Status |
| --- | --- | --- | --- | --- | --- |
| DAT-1 | A full backup to a file the user chooses, holding the books, the vouchers and all key slots as of one point in time. | Restoring it reproduces identical books and vouchers. | Must | 2 | TODO |
| DAT-2 | Restore treats the file as untrusted and verifies it (integrity and schema checks) before use. | Corrupted or foreign files are rejected with a clear reason. | Must | 2 | TODO |
| DAT-3 | A reminder when the last external backup is older than a configured interval. | The reminder appears once the interval has passed. | Must | 2 | TODO |
| DAT-4 | The app requests persistent storage and, where browsers may evict data (e.g. Safari), recommends installing it. | Shown on first run where it applies. | Must | 2 | TODO |
| DAT-5 | Vouchers (receipts, invoices) are attached to entries and kept for the retention period. | Attachments survive backup and restore; a posted entry's voucher cannot be deleted. | Must | 2 | TODO |
| DAT-6 | Schema upgrades run automatically after an automatic backup; the app refuses a database from a newer version. | Upgrades pass from every released version; a newer file is refused. | Must | 2 | TODO |
| DAT-7 | Exports: the complete SQLite file, plus CSV and JSON for journals and reports, safe against spreadsheet formula injection. | Exports open in common tools; injected formulas are neutralized and negative amounts stay intact. | Must | 3 | TODO |
| DAT-8 | Audit-file export for the reference jurisdiction (e.g. FEC, SAF-T or GoBD data access). | **Stage 1 re-scope required (§9):** Verohallinto's audit guidance VH/4494/00.01.00/2025 (in force 4.12.2025) names no required file format, only that data must let an unbroken audit trail be verified. "Passes the official checker" has no Finnish target; the acceptance criterion will be proposed in Stage 1 and requires owner approval before work begins. | Must | 6 | TODO |
| DAT-9 | Records stay usable without the app: the schema is documented, and so is a way to decrypt backups. | A third party can read a backup by following the documentation. | Must | 5 | TODO |

#### Security and privacy

| ID | Requirement | Acceptance criterion | Priority | Phase | Status |
| --- | --- | --- | --- | --- | --- |
| SEC-1 | Optional zero-knowledge encryption (AES-256-GCM) of the books, vouchers and backups. | With encryption on, nothing readable is stored. | Must | 5 | TODO |
| SEC-2 | Unlock with a password, a recovery code or, where the platform supports it, a passkey (stored by Google Password Manager, iCloud Keychain, Windows Hello or a password manager). This gives sign-in-with-Google/Apple/Microsoft convenience without accounts or OAuth. Changing unlock methods doesn't re-encrypt the data. | Each method unlocks; adding or removing one leaves the data untouched. | Must | 5 | TODO |
| SEC-3 | Lockout prevention: encryption turns on only after the user re-enters the recovery code; the recovery code cannot be removed and at least one other method always remains; passkey users are asked for their password from time to time; backups carry all unlock methods. Before encryption is turned on, the UI states that nobody, including this project, can recover the data once every unlock method is lost. | Tests enforce each rule. | Must | 5 | TODO |
| SEC-4 | Auto-lock after a configurable period of inactivity. | Locking wipes keys and decrypted data from memory. | Must | 5 | TODO |
| SEC-5 | No ledger data leaves the device except through an explicit export. The browser blocks requests to anything but the app's own origin and the optional lookups on the allowlist. | An end-to-end test asserts that no other request is made (G4). | Must | 0 | TODO |
| SEC-6 | No telemetry, analytics or remote error reporting. | No such code or requests exist. | Must | 0 | TODO |

#### Year-end

| ID | Requirement | Acceptance criterion | Priority | Phase | Status |
| --- | --- | --- | --- | --- | --- |
| YE-1 | Fiscal-year close: closing entries, transfer of the result to equity, and carry-forward of balance-sheet accounts as the next year's opening balances. | The new year's opening trial balance equals the closing balance sheet. | Must | 6 | TODO |

#### Licensing

| ID | Requirement | Acceptance criterion | Priority | Phase | Status |
| --- | --- | --- | --- | --- | --- |
| LIC-1 | The app shows the copyright notice, the "Licensed under the EUPL" notice and a link to the source repository, as EUPL Articles 3, 5 and 11 require of anyone serving the built app. | An About screen shows all three, and the source link works in every deployed build. | Must | 0 | TODO |

### 4.3 Non-functional requirements

| ID | Requirement | Acceptance criterion | Priority | Phase | Status |
| --- | --- | --- | --- | --- | --- |
| NFR-1 | Performance with 100,000 entries (about 300,000 lines) on a mid-range laptop, in every supported engine: one account balance under 50 ms; trial balance and financial statements under 500 ms; interactive within 2 s of a cold start, not counting the time to type a password; no main-thread task over 50 ms while queries run. | A CI benchmark on a seeded database. | Must | 0 (harness), 6 (full scale) | TODO |
| NFR-2 | Works offline as an installable PWA. | A full journey passes with the network disabled. | Must | 0 | TODO |
| NFR-3 | Supports current Chromium-based browsers, Firefox and Safari; Stage 1 fixes the exact matrix. | End-to-end tests pass in all three engines. | Must | 0 | TODO |
| NFR-4 | WCAG 2.2 AA, with keyboard-efficient data entry. | Automated checks pass in CI; a manual audit is done before v1.0. | Must | 0 (checks), 6 (audit) | TODO |
| NFR-5 | Served as static files from an origin of its own, on any static host, including hosts that cannot send custom HTTP headers. | The deployed build passes the end-to-end tests on the chosen host (D3). | Must | 0 | TODO |

## 5. Non-goals for v1

- Medium-sized and large undertakings.
- Sync and multi-device use. If sync is ever added, it must be end-to-end encrypted so that a server only ever stores ciphertext.
- Multiple users, user accounts and OAuth/OIDC sign-in. With no backend there is nothing to authorize against, and a login screen alone cannot protect data stored in the browser; encryption does (SEC-1). The app holds no API keys, tokens or credentials of any kind. Collaboration means handing over the file.
- Bank APIs: PSD2 access needs a licensed backend. Importing statement files such as CAMT.053 comes later.
- Invoicing and e-invoicing (EN 16931/ViDA).
- Payroll, fixed-asset schedules, inventory, consolidation, electronic filing.

Any network call, such as a VIES VAT-number check or ECB exchange rates, must be optional and user-initiated and must send no ledger data. CORS may block it; if so, flag it rather than adding a backend.

## 6. Constraints and assumptions

- No backend: the app runs entirely in the browser and is served as static files (NFR-5).
- Browser storage can be evicted, so the app's copy is a working copy and backups are the archive (DAT-1 to DAT-4).
- Support for passkey PRF and persistent storage varies by platform. The app falls back to the password and recovery code, and to backup reminders.
- Software alone cannot make bookkeeping legally compliant. National rules and the user's own procedures also apply, and gogol never claims certification.
- One user works on an entity's books at a time.
- Up to 100,000 entries per entity (NFR-1).

## 7. Release plan

Each phase ends with every CI gate green and a deployed build; `PROMPT.md` defines the engineering gates. Requirement status lives in section 4, not here.

| Phase | Goal | Requirements and exit criteria |
| --- | --- | --- |
| 0. Walking skeleton | Retire technical risk: SQLite WASM on OPFS in a worker, migration runner, typed protocol, PWA shell, CI in every engine, deployment, encryption spike | SEC-5, SEC-6, LIC-1, NFR-1 (benchmark harness), NFR-2, NFR-3, NFR-4 (automated checks), NFR-5 |
| 1. Ledger core | Balanced, immutable, numbered books | COA-1, COA-2, LED-1 to LED-8, LED-10 to LED-13, RPT-1, RPT-2 |
| 2. Durability | Never lose the books | DAT-1 to DAT-6 |
| 3. Reports | Statements and exports | RPT-3, RPT-4, RPT-5, DAT-7 |
| 4. VAT | VAT data for the reference jurisdiction | LED-9, VAT-1 to VAT-5 |
| 5. Encryption | Zero-knowledge encryption without lockouts | SEC-1 to SEC-4, DAT-9 |
| 6. Year-end and hardening | Close the year and prove quality | YE-1, DAT-8, NFR-1 at full scale, NFR-4 audit, accountant sign-off (G2), mutation testing of money, VAT and posting logic, ASVS verification, reproducible-build check |

## 8. Decisions

| ID | Decision | Status | Notes |
| --- | --- | --- | --- |
| D1 | Reference jurisdiction for v1 | Decided 2026-10-11 | Finland. Drives the chart template, VAT return box mappings and audit-file format. Note: Verohallinto's audit guidance VH/4494/00.01.00/2025 (in force 4.12.2025) names no required file format; DAT-8 acceptance criterion must be re-scoped in Stage 1 (§9). Pending legislation HE 96/2026 amends the Accounting Act; Stage 1 must verify its status. |
| D2 | Reference entity type | Decided 2026-10-11 | Micro limited company (osakeyhtiö / Oy). An Oy must keep double-entry books under the Finnish Accounting Act (kirjanpitolaki); only natural persons below all three KPL size thresholds may use single-entry. |
| D3 | Deployment host and domain | Open | Needs an origin of its own; see `PROMPT.md` hard problem 1. |
| D4 | Repository host | Decided 2026-10-09 | GitHub, `tinosingh/gogol`; an independent repository. |
| D5 | Project license | Decided 2026-10-10 | EUPL-1.2 (`LICENSE`), with a trademark policy reserving the gogol name (`TRADEMARKS.md`). A no-derivatives license was rejected: it would not be open source, and nobody could fix the app if the project stopped (DAT-9). |
| D6 | Foreign-currency transactions in v1 | Decided 2026-10-11 | Own (functional) currency only. Lines carry no original-currency or exchange-rate columns in v1. Ground truth: adding three nullable currency columns to 300 000 posted rows took ~15 ms/column; no rows changed and immutability triggers held — columns can be added later without forced row migration. Design recorded in ADR 7. |
| D7 | UI language(s) for v1 | Decided 2026-10-11 | English only. All UI text lives in one place so a translation layer can be added later. Number and date formats still follow the user's locale (LED-7, LED-8). |

## 9. Maintaining this document

- Requirement IDs are permanent. They are never reused or deleted; a dropped requirement is marked `DROPPED (<reason>)`.
- Mark a requirement `WIP` when work on it starts. When its acceptance criterion is met, mark it `DONE <commit> (<date>)` in a follow-up commit that cites the commit that met it.
- New requirements, and changes to priority or acceptance criteria, need the owner's approval and a change-log entry.
- Tests, ADRs and commits cite the requirement IDs they cover.

## 10. Change log

| Date | Version | Change |
| --- | --- | --- |
| 2026-10-09 | 0.1 | First draft. Product scope moved here from `PROMPT.md` (fact-checked in a6ed70a) so that it has one source. |
| 2026-10-10 | 0.2 | D5 decided: EUPL-1.2 with a trademark policy. Added LIC-1, the license notice the EUPL requires in the served app. |
| 2026-10-11 | 0.3 | D1 (Finland), D2 (micro Oy), D6 (own currency only), D7 (English only) decided. DAT-8 acceptance criterion flagged for Stage 1 re-scope: Finland's Verohallinto guidance VH/4494/00.01.00/2025 mandates no specific file format. |
