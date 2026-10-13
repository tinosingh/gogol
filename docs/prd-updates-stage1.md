# PRD updates proposed in Stage 1

- **Status:** Proposed for owner approval. Nothing here changes [prd.md](prd.md) until the owner approves each item (PRD §9).
- **Scope:** Risks and exit criteria per release phase, requirement changes, additions and drops caused by the design, one re-scoped acceptance criterion (DAT-8), and watch items.
- **Verification note:** items marked **Unverified** rely on sources I could not confirm in this session.
- **Update 2026-10-13:** encryption is deferred after v1 (owner decision), so P1 and P2 are on hold. The other items are unchanged.

## 1. Requirement changes, additions and drops

Each item lists the design reason and the ADR. "Change" means the wording of an existing ID changes; IDs are never reused (PRD §9).

| #   | ID     | Kind                                             | Proposal                                                                                                                                                                                      | Reason                                                                                                                     | ADR                   | Owner decision                                                                                                                                     |
| --- | ------ | ------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- | --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| P1  | SEC-1  | **Change**                                       | Replace "AES-256-GCM" with "authenticated encryption (AES-256-GCM, or another authenticated cipher the approved build provides and the spike validates)".                                     | The prebuilt cipher build may not expose AES-256-GCM as a page cipher. Unverified.                                         | ADR 2                 | Required if the cipher differs. Option: keep AES-256-GCM and fall back to the snapshot design (ADR 2 option A), with its crash-loss cost accepted. |
| P2  | SEC-2  | **Change (clarify)**                             | Add: "A passkey unlock is a per-device slot, confirmed by an immediate unlock when saved."                                                                                                    | PRF output differs across synced devices and platforms.                                                                    | ADR 2                 | Approve.                                                                                                                                           |
| P3  | NFR-1  | **Change (clarify)**                             | Split measurement: (a) CI gate on relative thresholds against a reference run on the same runner class; (b) absolute targets checked on a documented reference laptop before each phase exit. | CI runners are not the mid-range laptop named in NFR-1.                                                                    | ADR 9                 | Approve, or name the reference machine.                                                                                                            |
| P4  | NFR-3  | **Decided by owner 2026-10-13: Firefox dropped** | Supported: Chromium-based browsers (Chrome, Edge) only (owner decision 2026-10-13). Playwright engine: Chromium. Safari reconsidered before v1.0.                                             | Capability cells in architecture.md §4 are still unverified.                                                               | architecture.md §4    | Done.                                                                                                                                              |
| P5  | DAT-5  | **Change (clarify)**                             | Add: "Attachments can be added to posted entries; they cannot be deleted once their entry is posted."                                                                                         | Late vouchers are normal. The owner decides whether adding is allowed.                                                     | ADR 3                 | Decided 2026-10-13: allowed, deletion blocked, additions logged.                                                                                   |
| P6  | LED-10 | **Clarify (no change in test)**                  | Add to the criterion: "Detection requires a previously printed head; before the first printed head, edits are not detectable."                                                                | States the limit the requirement already implies.                                                                          | ADR 6, security.md §4 | Approve.                                                                                                                                           |
| P7  | DAT-6  | **Clarify**                                      | Add: "The automatic backup before an upgrade is kept until the upgrade is verified."                                                                                                          | Defines what "automatic backup" means for the runner.                                                                      | ADR 5                 | Approve.                                                                                                                                           |
| P8  | NFR-5  | **Clarify**                                      | Add: "The database worker starts from a blob URL, so it inherits the page's policy" as a design note, not a requirement; the requirement stays.                                               | Same-origin workers take no CSP from hosts that send no headers.                                                           | security.md §5        | Approve as a note only.                                                                                                                            |
| P9  | —      | **Add (new NFR-6)**                              | "One open connection per entity. A second tab opens read-only and can take over on the user's request."                                                                                       | Single-connection constraint of `opfs-sahpool`. PRD §6 says one user works on the books at a time; this makes it testable. | ADR 1                 | Approve or reject.                                                                                                                                 |
| P10 | —      | **Add (new requirement, Phase 1)**               | "Each entity's functional currency is fixed once anything is posted."                                                                                                                         | Already enforced by a trigger (LED-7 code path). Makes the rule visible in the PRD.                                        | ADR 7                 | Approve or treat as part of LED-7.                                                                                                                 |
| P11 | —      | **Add (decision, not a requirement)**            | D8: per-file attachment size limit. Proposed 25 MiB, placeholder.                                                                                                                             | No source in the PRD. Owner sets it.                                                                                       | ADR 3                 | Decided 2026-10-13: 10 MiB, in config.                                                                                                             |
| P12 | —      | **Add (decision)**                               | D9: correction of entries in a closed fiscal year. v1 proposal: not possible; correction in an open period only.                                                                              | ADR 8 leaves this open.                                                                                                    | ADR 8                 | Decided 2026-10-13: not in v1.                                                                                                                     |
| P13 | —      | **Add (decision)**                               | D10: applicability of the EU Cyber Resilience Act (Regulation (EU) 2024/2847).                                                                                                                | security.md §6. Needs legal review; reporting dates must be checked.                                                       | security.md §6        | Decide, with a lawyer.                                                                                                                             |
| P14 | —      | **Add (decision)**                               | D11: Trusted Types enforcement in Chromium. PROMPT.md's claim covered three engines; Firefox and Safari are out of scope (P4).                                                                | Unverified.                                                                                                                | architecture.md §4    | Confirm in the spike.                                                                                                                              |
| P15 | —      | **Drop**                                         | None. The design drops no requirement.                                                                                                                                                        |                                                                                                                            |                       |                                                                                                                                                    |

Requirement IDs added as NFR-6 only if P9 is approved. D8 to D11 are decisions in PRD §8, not requirements.

No requirement is dropped and D6 (own currency only) is respected: no FX columns exist in v1 (ADR 7).

## 2. DAT-8 re-scoped acceptance criterion (Finland)

**Current text (PRD §4.2):** "Passes the official checker" with a Finnish target. The PRD says Verohallinto's guidance VH/4494/00.01.00/2025 names no required file format, so this has no target.

**Verification note:** In this session I searched for VH/4494/00.01.00/2025 and did not find it. The statement about its content comes from the PRD and is **Unverified**. The owner must check the document text before approving this item.

**Proposed text:**

> An export of posted journal entries, lines and reversal links, in documented open formats (CSV, DAT-7) with the schema documentation (DAT-9), from which an independent reviewer can verify: (a) every posted entry appears exactly once; (b) entry numbers are gapless per journal and fiscal year; (c) the hash chain verifies to the head printed in the same export (LED-10, RPT-5); (d) the lines reconcile to the trial balance (RPT-1). No specific file format is required by this criterion. Conformance is shown by a reproducible verification script and a documented procedure, not by a third-party checker.

**Effects:**

- Removes the reference to FEC and SAF-T in DAT-8. PRD §4.1 lists these as examples only ("e.g."), so no requirement depends on them.
- Phase 6 work becomes a verification procedure plus export, not a format implementation.
- If an official format is later mandated, that becomes a new requirement (new ID), not an edit to DAT-8.

## 3. Watch items for Stage 1

| Item                                                                                                                                                                                                                                                                                  | Status (checked 2026-10-12)                                                | Effect on design                                                                               | Action                                                |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| **HE 96/2026**, amendment to the Accounting Act, Trade Register Act and Auditing Act: digital financial statements and reports for certain entities, mainly limited companies. Associations, cooperatives, housing companies and foundations are out of scope per the bill's summary. | Pending in Parliament (Edilex lists it as "Vireillä"). Snapshot, not live. | Does not change the ledger. May affect statement output format (Phase 3) for Oy entities (D2). | Re-check before Phase 3. Owner to confirm the status. |
| HE 38/2026, separate amendment, reported enacted as Act 555/2026, in force 30 June 2026.                                                                                                                                                                                              | Reported by a search snippet; **Unverified** against the official text.    | Possibly affects the audit-related statements in Phase 6.                                      | Owner to confirm with the official text.              |
| VH/4494/00.01.00/2025 (Verohallinto audit guidance).                                                                                                                                                                                                                                  | Not found in search. **Unverified.**                                       | Basis of DAT-8 re-scope.                                                                       | Owner to check the document.                          |
| Safari storage eviction rules (only if Safari is added).                                                                                                                                                                                                                              | From PROMPT.md. Not re-checked.                                            | DAT-4 wording.                                                                                 | Re-verify in Phase 2.                                 |
| ASVS 5.0 control mapping.                                                                                                                                                                                                                                                             | Chapter-level only (security.md §6).                                       | Phase 6 evidence.                                                                              | Per-control mapping in Phase 6.                       |

## 4. Risks and exit criteria per phase

Exit criteria are the PRD's own (§7) plus the design's gates. "Gate" means a go or no-go decision the owner records before the next phase.

### Phase 0: Walking skeleton

- **Risks:** (1) `opfs-sahpool` plus the cipher build fails the spike (ADR 2 gate). (2) `pauseVfs()` takeover does not work in one engine (ADR 1). (3) Blob worker does not inherit the CSP in one engine (security.md §5). (4) D3 is still open, so the deployed origin is unknown. (5) Chromium Playwright tests flaky. (6) Protocol and DDL drift apart.
- **Exit criteria:** SEC-5 and SEC-6 end-to-end tests green in all three engines; LIC-1 About screen and source link on the deployed build; NFR-2 offline journey; NFR-3 green in three engines; NFR-4 automated checks green; NFR-5 passes the end-to-end tests on the chosen host (D3); NFR-1 benchmark harness runs; spike results written to an ADR update; CI gates from PROMPT.md green; repository settings (protected main, required checks) listed for the owner to apply.
- **Gate:** the two spikes (ADR 1, ADR 2). Fail means the owner decides the fallback before Phase 1.

### Phase 1: Ledger core

- **Risks:** (1) COA-1 needs the Finnish chart template; its source and licence are not in the PRD and must be chosen before the golden fixtures exist. (2) Trigger error mapping drifts from `triggerErrorCode` (worker-protocol.ts); a test must read the migrated schema. (3) Posting speed on the 300 000-line seed. (4) LED-10 chain verification on open may break the cold-start budget.
- **Exit criteria:** COA-1, COA-2, LED-1 to LED-8, LED-10 to LED-13, RPT-1, RPT-2 pass property tests (fast-check) and golden fixtures; each test cites its ID; query-plan check green; mutation spot-check on posting rules.
- **Gate:** owner review of the chart template and the first golden fixtures. An accountant review is not required here (G2 is Phase 3 and 6).

### Phase 2: Durability

- **Risks:** (1) Restore of hostile files (DAT-2). (2) `VACUUM INTO` or the online backup API may not work on `opfs-sahpool`; the pre-migration backup depends on it (ADR 4, ADR 5). (3) Storage quota is smaller than assumed in some engines. (4) Attachment size and streaming (ADR 3). (5) Fixture databases start from the first released schema, so migration tests begin here.
- **Exit criteria:** DAT-1 to DAT-6 pass; restore round trips identical in all three engines (G5); corrupt and foreign files rejected with a reason; migration tests pass from every released fixture; newer files refused; service-worker update policy tested.
- **Gate:** owner decision on P5 and D8 (attachments) before the attachment migration.

### Phase 3: Reports

- **Risks:** (1) Statement layouts (RPT-4) need an accountant and the current layout rules; HE 96/2026 may change the output (watch item). (2) Formula injection in CSV (DAT-7). (3) Report printing of the chain head (RPT-5).
- **Exit criteria:** RPT-3, RPT-4, RPT-5, DAT-7 pass; golden fixtures for statements reviewed by an accountant (G2, first sign-off); CSV injection tests.
- **Gate:** accountant sign-off on the layouts. Without it, RPT-4 stays open.

### Phase 4: VAT

- **Risks:** (1) VAT rules need an accountant's review for each treatment (VAT-1 to VAT-5). (2) Rate history source for LED-9 (reference data) must be chosen and dated. (3) VAT options (SME exemption, cash accounting, pro-rata) are complex and may need a second golden set.
- **Exit criteria:** LED-9, VAT-1 to VAT-5 pass golden fixtures reviewed by an accountant; a rate change does not change earlier reports.
- **Gate:** accountant sign-off. The design does not assume the rules in this phase.

### Phase 5: Encryption

- **Risks:** (1) Passkey support varies (PRF) (ADR 2). (2) Lockout rules (SEC-3) can be wrong in edge cases; each needs a test. (3) Nonce strategy depends on the cipher codec (ADR 2). (4) Memory wipe is partial (security.md §2). (5) The slot migration must keep the chain intact (ADR 5).
- **Exit criteria:** SEC-1 to SEC-4 and DAT-9 pass; no plaintext at rest found by the test; each unlock method unlocks; slot changes leave data untouched; lockout tests green; DAT-9 documentation tested by a third party reading a backup.
- **Gate:** owner review of the recovery and lockout copy shown before encryption is turned on (SEC-3).

### Phase 6: Year-end and hardening

- **Risks:** (1) DAT-8 re-scoped criterion needs owner approval and the document check (section 2). (2) Year-end corrections policy (P12). (3) Accountant availability for G2 final sign-off. (4) Full-scale NFR-1 on the reference laptop. (5) Reproducible-build check across hosts. (6) CRA applicability (P13).
- **Exit criteria:** YE-1 property test (opening trial balance equals closing balance sheet); DAT-8 verification procedure passes on the fixture year; NFR-1 at full scale; NFR-4 manual WCAG 2.2 AA audit; G2 accountant sign-off; mutation testing of money, VAT and posting logic; ASVS verification per control; reproducible build.
- **Gate:** owner release decision for v1.0.

## 5. Open questions that block decisions

1. D3: deployment host and domain (ADR 1). Blocks the Phase 0 deploy.
2. Cipher build: does the approved WASM expose AES-256-GCM? (P1, ADR 2.)
3. Chromium WebAuthn PRF and Trusted Types support (architecture.md §4). Firefox and Safari are out of scope (P4).
4. Finnish chart template source and licence (Phase 1).
5. Accountant for G2 and VAT sign-off (Phases 3, 4, 6).
6. Attachment size and whether adding to posted entries is allowed (P5, P11).
7. Correction policy for closed years (P12).
8. CRA applicability (P13).

## 6. Proposal (2026-10-13): OS-level encryption and passphrase-encrypted backups

**Status:** E1 to E5 approved and applied in PRD v0.11 (2026-10-13). E6 (LED-10) is open.

This replaces the deferred SEC-1 to SEC-4 with a smaller design. Nothing here changes [prd.md](prd.md) until the owner approves each item (PRD §9).

**Reason.** The live database sits in the browser profile on the same disk as the rest of the user's data, so the OS's full-disk encryption already protects it when the machine is off or locked. The browser cannot encrypt the live database through its storage layer (ADR 2 spike), so an app-level live-database encryption is both the most complex part and the least needed. The real gap is the backup file, which the app writes to a location the OS does not protect.

| #   | ID     | Proposal                                                                                                                                                                                    | Owner decision |
| --- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------- |
| E1  | SEC-1  | **Replace** with: "The live database relies on the device's full-disk encryption (FileVault, BitLocker or LUKS). The first-run and About screens state this requirement."                   | Approve        |
| E2  | SEC-2  | **Replace** with: "A backup can be exported encrypted with a passphrase: AES-256-GCM through WebCrypto, with the key derived by PBKDF2-SHA-256. The KDF parameters are stored in the file." | Approve        |
| E3  | SEC-3  | **Replace** with: "Before the first encrypted export, the UI states that the passphrase cannot be recovered by the project."                                                                | Approve        |
| E4  | SEC-4  | **Drop** (no live-database keys to wipe; the OS session lock applies).                                                                                                                      | Approve        |
| E5  | DAT-9  | Already limited to schema documentation (PRD v0.10). Add: "An encrypted backup can be decrypted by following the documentation."                                                            | Approve        |
| E6  | LED-10 | **Option, not decided:** keep as Must, make it Should, or check the chain at export only.                                                                                                   | Decide         |

**Effects if approved**

- ADR 2 applies to the backup file only. Its live-database options (A and B) are closed.
- security.md: the lost-device row says the OS protects the disk; the profile row says the same; the backup row gets the passphrase control.
- architecture.md: the crypto component covers the backup export only, with WebCrypto and no third-party cipher.
- Dependencies: none new. WebCrypto is part of the platform.
- Phase 5 becomes "passphrase-encrypted backup export" and is much smaller.

**Open risks the owner must accept**

- The app cannot check whether disk encryption is on. It can only tell the user to enable it.
- A backup saved without a passphrase, or copied to a synced folder, is readable by anyone with access to that copy.
