# Security

- **Status:** Stage 1 design, awaiting owner approval.
- **Requirements:** SEC-1 to SEC-6, DAT-2, DAT-5, DAT-7, LED-10, LIC-1, NFR-5.
- **Related:** [architecture.md](architecture.md) (trust boundaries TB1 to TB9), ADRs [2](adr/adr-02-encryption-vfs.md), [5](adr/adr-05-migrations.md), [6](adr/adr-06-tamper-evidence.md).

This file is not a certification and not legal advice. Software cannot make bookkeeping legally compliant (PRD §6). The controls below reduce risk; they do not guarantee anything.

## 1. What gogol protects against

| Threat | Protection | Condition |
| --- | --- | --- |
| Lost or stolen device while locked | Encryption of the database, backups and attachments (SEC-1); keys exist only in worker memory and are wiped on lock (SEC-4) | Encryption is on. Before it is turned on, nothing protects the data at rest. |
| Other origins | Same-origin policy; a dedicated origin (ADR 1); no other site of the same account shares its storage | The app has its own origin. On `<user>.github.io` project sites this would not hold, so ADR 1 rejects that host. |
| Casual access to the browser profile | Encryption (SEC-1) | Encryption is on. In plain mode a person with tools can read the file. |
| Network observers and third parties | No backend; no telemetry (SEC-5, SEC-6); CSP `connect-src` limits requests to the app's origin and allow-listed lookups; no third-party runtime scripts, fonts or CDNs | Requires the browser to enforce CSP, which it does when the meta policy is present. |
| Silent edits to posted history made with external tools | Immutability triggers (LED-2); hash chain (LED-10) detected on open against a printed head | Only against a head the user recorded outside the file (see §4). |
| Corrupted or foreign restore files | Untrusted-file validation (DAT-2): defensive open, `trusted_schema = OFF`, integrity check, schema check | Always, on every restore. |
| Data loss from browser eviction | Backup file and reminder (DAT-1, DAT-3); persistence request (DAT-4) | The user makes and keeps backups. |
| Spreadsheet formula injection in exports | Neutralized in CSV and JSON exports (DAT-7) | Always. |

## 2. What gogol does not protect against

| Threat | Why not | What still reduces the risk |
| --- | --- | --- |
| Malware on the device (keyloggers, screen capture, memory reading) | Any code running as the user can read what the user types and what the app holds in memory. | Auto-lock (SEC-4); no plaintext at rest; a short unlocked window. |
| Malicious browser extensions | Extensions see the DOM and can call the app's worker. | Strict CSP; no third-party code in the app; document the risk in the UI. |
| XSS on this origin | Injected script runs with the app's privileges, can send any worker message, and can export data once the database is unlocked. | Strict CSP with `'wasm-unsafe-eval'` only; Trusted Types where enforced; no `dangerouslySetInnerHTML`; no third-party scripts; code review of every sink; dependency pinning. |
| Compromised build or dependency | The shipped code is what the build produced. | Lockfile and `npm ci`; SHA-pinned actions; CodeQL, dependency audit, secret scanning; SBOM and provenance; reproducible-build check (Phase 6); minimal dependency list with a one-line justification each. |
| Compromised browser or OS | Out of the app's reach. | None in the app. |
| A user who loses every unlock method | Intended. SEC-3 says so, and the UI says it before encryption is turned on. | Recovery code is mandatory; lockout invariants (ADR 2). |
| An attacker with the file and unlimited offline guessing | Nothing online can throttle guesses, because the file is local. | KDF cost (PBKDF2-SHA-256 at the current OWASP count, ADR 2); password policy; passkey as a second factor is not claimed. |
| A false clock | The browser clock is under the user's control. `posted_at_utc` can be set to any value. | Chain order is by `posting_seq`, not time; printed heads (RPT-5). Limit recorded here, not hidden. |
| Clickjacking | A `<meta>` policy cannot set `frame-ancestors`. | No sensitive action depends on a single click; unlock requires the secret; document the limit. |
| Whole-file replacement by a person who also recomputes the chain | The chain only matches a head the user recorded elsewhere. | The user keeps printed heads (RPT-5). |
| Passkey sync compromise or inconsistent PRF output across devices | Platform behavior. | Passkey slots are per-device and confirmed by an immediate unlock (ADR 2); password and recovery code always work. |
| Memory residue of the key | JavaScript and WASM memory are not reliably wiped by the runtime. | Keys are in worker memory only; overwritten on lock; the residual is accepted and stated. |

## 3. STRIDE threat model by trust boundary

Boundaries are numbered as in [architecture.md §3](architecture.md#3-trust-boundaries).

| Boundary | S | T | R | I | D | E | Controls | Residual |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **UI (TB1, TB6)** | Forged worker messages from injected script | Tampered requests (amounts, ids) | Actions without record | Data read by injected script after unlock | Flooding the worker | Calling privileged requests (backup, restore) from XSS | Strict CSP; Trusted Types; typed protocol; worker validates every field; audit log for master-data changes (LED-6). | XSS still acts with the unlocked app's rights (§2). |
| **Worker (TB1, TB3)** | Impersonating a UI request id | Malformed request altering books | Errors without context | Error details leaking amounts | Long-running transactions blocking UI (NFR-1) | Bypassing SQL triggers | Every write is one unit of work; triggers enforce LED rules inside the DB; typed error codes without amounts; `BEGIN IMMEDIATE`. | A caller with DB access can still drop triggers in a copy of the file (§4). |
| **Storage (TB2)** | Another origin reading OPFS | Editing the file with an external tool | Edits to posted history without trace | Plain database read from profile | Storage eviction; quota | Replacing the file | Dedicated origin (ADR 1); encryption (SEC-1); immutability triggers (LED-2); chain (LED-10); quick_check on open; backups (DAT-1); reminders (DAT-3). | External edits detected only against printed heads; eviction handled by backup, not by the app. |
| **Crypto (TB3, TB7)** | Passkey on a different device producing a different key | Modified key slots | Unlock attempts unrecorded | Keys in memory or logs; plaintext at rest | Lockout by losing all methods (SEC-3) | Adding a slot without the recovery code | WebCrypto and audited primitives only; KDF with stored parameters; AES-GCM key wrap with random nonce; slot invariants (SEC-3) with tests; no key in logs; wipe on lock (SEC-4). | Offline guessing is limited only by KDF cost. Memory residue (§2). |
| **Import and export (TB4, TB5)** | Restoring a foreign or older file as the user's books | Crafted database file exploiting SQLite parsing | Export without a record of its head | Export carrying amounts into logs or spreadsheets | Huge file exhausting memory | CSV formula injection (DAT-7) | Defensive mode and `trusted_schema = OFF` for untrusted files; `integrity_check`; schema version check (DAT-6); attachment hash check (ADR 3); streaming, never whole-file buffers; formula neutralization; export prints period, time and head (RPT-5). | A SQLite parser bug on a crafted file is a residual; it runs inside the sandboxed worker and is covered by the dependency update policy. |
| **Build and deploy (TB8)** | Unsigned or spoofed release | Compromised dependency or action | Unreproducible build | Secrets in repository or bundle | CI outage blocks release | Action run with broad permissions | SHA-pinned actions; least-privilege workflow permissions; lockfile and `npm ci`; Dependabot; CodeQL; dependency audit; secret scanning; SBOM (`npm sbom`, CycloneDX); build provenance; reproducible-build check; no credentials in repository or bundle; SECURITY.md disclosure process. | A compromised maintainer account can still push a malicious release. Reproducible builds let users detect it. |

## 4. Tamper-evidence limits (LED-10), stated for users

- The chain detects a changed posted entry **if the printed head is known**. Before the first printed head, a change is undetectable.
- A person who controls the file can rewrite the whole chain. A printed head from before the change will then differ. A head that was never printed cannot help.
- Triggers can be dropped in a copy of the file by an external tool. The chain catches the resulting edits on open; a dropped trigger alone does not change a hash.
- Timestamps come from the device clock and can be set arbitrarily. Chain order uses `posting_seq`.
- **Audit log not in the chain.** `audit_log` rows (account renames, role reassignments, settings changes) are protected by append-only triggers but are not part of the hash chain. An external tool that drops those triggers (via `writable_schema`) can delete audit log rows silently; a LED-10 chain check will not catch it. `PRAGMA defensive = ON` on every connection (CLAUDE.md invariant 6) is the primary control against this; it prevents `writable_schema` from being set through the app.

## 5. Controls summary

| Area | Control | Requirement |
| --- | --- | --- |
| Transport | No backend; `connect-src` allow-list; no third-party resources | SEC-5, NFR-5 |
| Page policy | `<meta>` CSP before any script, style or resource. `default-src 'self'`; `script-src 'self' 'wasm-unsafe-eval'`; `worker-src 'self' blob:`; `connect-src 'self'` plus configured lookup endpoints; `object-src 'none'`; `base-uri 'none'`. Exact directives generated from config at build time. | SEC-5, NFR-5 |
| Worker policy | Database worker started from a blob URL so it inherits the page policy. A same-origin worker file would take no policy from a host that sends no headers. **Verify in the spike** that a blob worker inherits the CSP in all three engines. | SEC-5 |
| DOM sinks | No `dangerouslySetInnerHTML`; Trusted Types where enforced; lint rule for `innerHTML`, `eval`, `new Function` | SEC-5 |
| Encryption | AES-256-GCM or the approved alternative (ADR 2); PBKDF2-SHA-256 at the OWASP count; key slots; recovery slot mandatory | SEC-1, SEC-2 |
| Lockout | Domain invariants on slots; encryption on only after recovery code re-entry; tests | SEC-3 |
| Auto-lock | Configurable inactivity timer; wipes keys and closes the database | SEC-4 |
| Privacy | No telemetry; logs contain no amounts, names or keys; error codes only to the UI | SEC-6 |
| Import | Defensive open; integrity and schema checks; untrusted by default | DAT-2 |
| Export | Formula neutralization; negative amounts intact; head printed | DAT-7, RPT-5 |
| Integrity | Triggers (LED-*), chain (LED-10), `quick_check` on open, `integrity_check` on import, restore and export | LED-2, LED-10 |
| Licence notice | About screen with copyright, EUPL notice and source link | LIC-1 |
| Supply chain | Lockfile; `npm ci`; SHA-pinned actions; least-privilege workflows; Dependabot; CodeQL; audit; secret scanning; SBOM; provenance; reproducible builds | PROMPT.md |
| Disclosure | `SECURITY.md` with coordinated disclosure | PROMPT.md |

## 6. ASVS 5.0 applicability

Target: **Level 2 overall; Level 3 for V11 (cryptography) and V14 (data protection).** Control IDs are cited by chapter here. A per-control mapping against the ASVS 5.0 requirement list is a Phase 6 task, due before the ASVS verification in the release plan.

| Chapter | Level | Applies? | Notes |
| --- | --- | --- | --- |
| V1 Encoding and sanitization | L2 | Yes | Output encoding for report and CSV output; formula neutralization (DAT-7). |
| V2 Validation and business logic | L2 | Yes | Boundary validation in the worker; ledger rules in the DB (LED-*). |
| V3 Web frontend security | L2 | Yes | CSP by meta, Trusted Types, no `dangerouslySetInnerHTML`, no third-party resources. Anti-clickjacking headers: **N/A as headers**; the meta limit is recorded in §2. |
| V4 API and web service | L2 | **N/A — no server** | No API. The worker message protocol is internal and covered by V2. |
| V5 File handling | L2 | Yes | Restore and attachment uploads: size limits, type allow-list, hash checks (ADR 3, DAT-2). |
| V6 Authentication | L2 | Partly | Local unlock (SEC-2) applies. Server-side authentication, account lockout over a network and credential stores on a server: **N/A — no server**. Offline guessing is the KDF's job (ADR 2). |
| V7 Session management | L2 | Partly | "Session" is the unlocked worker state. Auto-lock (SEC-4) applies. Cookies, server sessions, token rotation: **N/A — no server, no cookies**. |
| V8 Authorization | L2 | **N/A — no server** | One user per entity (PRD §6). No roles or per-user access checks. |
| V9 Self-contained tokens | L2 | **N/A — no tokens** | The app issues no tokens (PRD §5). |
| V10 OAuth and OIDC | L2 | **N/A — non-goal** | No OAuth or OIDC (PRD §5). |
| V11 Cryptography | **L3** | Yes | ADR 2 and ADR 6: WebCrypto and audited primitives, key management, nonce strategy, KDF parameters stored, no custom primitives. Level 3 controls (for example, algorithm agility and documented key lifecycle) are verified in Phase 6. |
| V12 Secure communication | L2 | Partly | The host must serve HTTPS (host responsibility). App-level TLS settings: **N/A — no server**. Recorded as a deployment requirement for D3. |
| V13 Configuration | L2 | Yes | Config module; no secrets in code; build-time validation; headers that the host controls are not relied on. |
| V14 Data protection | **L3** | Yes | Encryption at rest (SEC-1); no plaintext in logs (SEC-6); clearing on lock (SEC-4); export controls (DAT-7); data minimization in errors. Retention (DAT-5) applies. |
| V15 Secure coding and architecture | L2 | Yes | Threat model (this file); ADRs; dependency policy; Trusted Types; lint import boundaries. |
| V16 Security logging and error handling | L2 | Partly | Local error codes only; no remote log sink (SEC-6, **N/A — no server**). Logs contain no personal or financial data. |
| V17 WebRTC | L2 | **N/A** | WebRTC is not used. |

### Regulatory notes

- **EU Cyber Resilience Act (Regulation (EU) 2024/2847).** The CRA treats free and open-source software developed and supplied outside commercial activity differently from commercial products. Whether gogol falls under its obligations depends on the owner's activity, which this file cannot decide. **Owner and a qualified lawyer must decide.** If the CRA applies, the reporting obligations for actively exploited vulnerabilities begin on 11 September 2026 (to be verified against the official text before any reliance). Today is past that date, so this must be settled now, not later.
- **GDPR (SEC-6, Art. 25).** The app holds personal data of the user's counterparties (names, amounts). Privacy by design means no telemetry, no logs of personal data, and local-only storage. The user is the controller for their own books.
- **Retention.** Retention periods (typically 5 to 10 years, PRD §1) are set by national rules. The app stores; the user decides. No deletion of posted records is offered (LED-2, DAT-5).

## 7. Disclosure

`SECURITY.md` (to be created in Phase 0) describes a private reporting channel and a coordinated disclosure timeline. This design does not invent a timeline; the owner sets it.
