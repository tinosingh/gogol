# Kickoff: local-first EU bookkeeping app

## Inputs — fill in before running
- Reference jurisdiction for v1: `<country, e.g. DE>`
- Reference entity type: `<e.g. small GmbH>`
- Deployment host: `<GitHub Pages | Cloudflare Pages | other>`
- Repository host: `<GitHub | other>` (the CI tooling below assumes GitHub; map it to equivalents otherwise)

If an input is blank, ask before starting.

## Role
You are the lead architect and implementer of this open-source project. You have deep practical knowledge of SQLite and its official WASM build, browser storage and security, React/TypeScript, double-entry bookkeeping, and EU accounting and VAT law. You are not a lawyer or a certified accountant. When a decision depends on law, cite the article or national rule, separate verified fact from assumption, and flag what needs review by a qualified accountant. Never invent legal requirements, and never claim compliance or certification that software alone cannot guarantee.

## Product
Double-entry bookkeeping for small European entities (limited companies, sole proprietors, associations) whose users must keep their records for 5–10 years. Correctness, auditability and durability come before features.

- Runs entirely in the browser with no backend. Deploys as static files to any static host, including hosts that cannot send custom HTTP headers.
- Works offline as an installable PWA.
- Financial data leaves the device only through an explicit, user-initiated export.
- The user owns the database file, backups, exports and keys. Records must stay readable for the full retention period even if this project disappears. That requires a documented schema, open export formats, and a documented way to decrypt backups without the app.
- Keyboard-efficient data entry; WCAG 2.2 AA.

## Stack
Fixed: React, TypeScript (strict), Tailwind CSS, and the official SQLite WASM build (`@sqlite.org/sqlite-wasm`), or a cipher-enabled build derived from it if ADR 2 justifies one. SQLite runs in a dedicated Web Worker and persists to OPFS. The UI thread never touches the database; it talks to the worker through a typed message protocol.

Defaults (override only with a written reason): Vite, Vitest, Playwright (Chromium, Firefox, WebKit), fast-check. Use one database file per legal entity; this keeps encryption, backup, retention and deletion simple for each entity.

## Invariants
Enforce each invariant in the database (constraints, triggers, transactions), not only in TypeScript, and cover each with an automated test.

1. Money is never floating point. Amounts are integer minor units. Rates are integer basis points or exact rationals. Every rounding step is explicit and follows the jurisdiction's rule. User input is parsed with the locale in mind (`1.234,56` vs `1,234.56`), never with `parseFloat`.
2. Every posted entry balances: it has at least one debit line and one credit line, and total debits equal total credits in the functional currency.
3. Posted entries are immutable. A correction is a reversal plus a new entry, both linked to the original. There is no UPDATE or DELETE of posted rows. Changes to master data (accounts, VAT codes, settings) are written to an audit log.
4. Each posted entry gets a gapless number in posting order, separate from the primary key. The numbering scope follows the jurisdiction's rule (e.g. per journal and fiscal year). Drafts get no number.
5. Nothing can be posted into a closed period or fiscal year.
6. Journal lines are the single source of truth. Balances and reports are derived from them. Any cache must be rebuildable from the journal and checkable against it.
7. Reference data that changes with the law is versioned data with validity dates, not code. This covers VAT rates, size thresholds, report layouts and account-to-report mappings. Each posted line stores a snapshot of the rate and VAT treatment it used.
8. Accounting dates are calendar dates (`YYYY-MM-DD`), never timestamps; a time-zone conversion can move an entry across a period boundary. Audit timestamps are UTC instants. The threat model must note that the browser clock is under the user's control.
9. Every connection runs `PRAGMA foreign_keys = ON`. All tables are `STRICT`. All SQL uses parameterized statements.

## Hard problems
Decide each of these in an ADR before building the code it affects.

1. **Hosting vs. OPFS VFS.** The `opfs` VFS needs SharedArrayBuffer, and therefore COOP/COEP headers, which GitHub Pages cannot send. `opfs-sahpool` needs no special headers but allows only one connection at a time. Choose one, and define what happens when the app is open in two tabs.
2. **Encryption vs. the VFS.** Encryption is optional, zero-knowledge, and uses AES-256-GCM. WebCrypto is asynchronous; SQLite's VFS I/O is synchronous. Compare two approaches:
   - an in-memory database with encrypted snapshots written to OPFS (consider how much is lost in a crash, how often to snapshot, and the memory ceiling);
   - page-level encryption through a cipher-enabled build or a custom VFS.

   This choice shapes the persistence layer, so decide it and test it with a spike in Phase 0, even though encryption ships later. The ADR must cover:
   - the KDF (Argon2id or PBKDF2-SHA-256 at current OWASP parameters, stored with the ciphertext so they can be raised later);
   - one data key, wrapped separately by each unlock method ("key slots"): the password, a recovery code, and optionally passkeys through the WebAuthn PRF extension where the browser and authenticator support it. Passkeys are stored by the platform (Google Password Manager, iCloud Keychain, Windows Hello) or a password manager, which gives users sign-in-with-Google/Apple/Microsoft convenience without OAuth, tokens or a backend;
   - the nonce strategy;
   - key material held only in the worker;
   - no plaintext at rest while encryption is on;
   - auto-lock after inactivity;
   - changing the password, and adding or removing unlock methods, without re-encrypting the data;
   - lockout prevention:
     - encryption turns on only after the user has re-entered the recovery code;
     - the recovery-code slot cannot be removed, and at least one other method must always remain;
     - passkey users are asked for their password from time to time so they don't forget it;
     - every backup carries all key slots.

   With no server there is no password reset, and nobody, including this project, can recover the data. Losing every unlock method means losing the data, and the UI must say so before the user turns encryption on.
3. **Attachments.** Vouchers (receipts, invoices) must stay linked to their entries for the whole retention period. Decide where the attachment bytes live together with ADR 2. One backup must hold both books and vouchers, consistently and encrypted, and must fit in memory with ten years of data.
4. **Durability.** Browsers evict origin storage, users clear site data, and devices get lost, so OPFS is the working copy, not the archive.
   - Request persistent storage.
   - Track time since the last external backup and remind the user.
   - Verify backups on restore.
   - Treat the File System Access API (Chromium only) as a backup target, not a live database backend. Download and upload are the fallback that works everywhere.
   - The official build has no IndexedDB VFS. Add an IndexedDB tier only if the browser support matrix requires one.
5. **Migrations.** Each user's database lives on their own device. Migrations are forward-only and transactional, run after an automatic backup, and are tested against fixture databases from every released schema version. The app refuses to open a database from a newer schema version. The service-worker update policy must keep stale code from running against a migrated database.
6. **Tamper evidence.** The user can edit the file with any SQLite tool, so the app can detect tampering but not prevent it. Hash-chain the posted entries, verify the chain on open and before export, and document this limitation.
7. **Currency.** Each entity has one functional currency, which is not always EUR. Decide now whether lines carry the original currency, amount and exchange rate; adding these later means migrating every posted row.
8. **Year-end.** Cover closing entries, transfer of the result to equity, opening balances for the next year, and opening balances for an entity moving from other software.
9. **Performance.** Targets with 100,000 entries (about 300,000 lines) on a mid-range laptop:
   - one account balance: under 50 ms;
   - trial balance and financial statements: under 500 ms;
   - interactive within 2 s of a cold start (after unlock, if encrypted);
   - no main-thread task over 50 ms while queries run.

   Prove these with a benchmark on a seeded database. Compute from indexed journal lines first, and add aggregate tables only if the benchmark shows they are needed.

## Regulatory scope
- Directive 2013/34/EU governs the annual accounts of limited-liability undertakings (Annexes I–II). Member states transpose it with national options. Its size thresholds were raised by Delegated Directive (EU) 2023/2775. Sole proprietors and associations fall under national law, which sometimes allows cash-basis or simplified bookkeeping.
- VAT follows Directive 2006/112/EC. Support standard, reduced, zero-rated and exempt supplies, reverse charge, and intra-EU supplies and acquisitions. Produce VAT summaries per period and the data for the EC Sales List (Art. 262).
- Build one generic double-entry core. Everything specific to a jurisdiction or entity type lives in a jurisdiction module:
  - chart-of-accounts templates (e.g. SKR03/04, PCG);
  - report layouts: the Annex III/IV balance sheet and Annex V/VI P&L, plus the abridged small and micro versions under Arts. 14 and 36;
  - VAT-return box mappings;
  - rounding and numbering rules;
  - retention periods;
  - audit-file exports (e.g. SAF-T variants, FEC, GoBD data access).
- v1 ships the generic core and the reference jurisdiction only. Derive the module interface from that one concrete implementation instead of designing it for all 27 member states up front.

## Non-goals for v1
- Sync and multi-device use. If sync is ever added, it must be end-to-end encrypted so that a server only ever stores ciphertext.
- Multiple users, user accounts and OAuth/OIDC sign-in. With no backend there is nothing to authorize against, and a login screen alone cannot protect data stored in the browser; encryption does (ADR 2). The app holds no API keys, tokens or credentials of any kind. Collaboration means handing over the file.
- Bank APIs: PSD2 access needs a licensed backend. Importing statement files such as CAMT.053 comes later.
- Invoicing and e-invoicing (EN 16931/ViDA).
- Payroll, fixed-asset schedules, inventory, consolidation, electronic filing.

Any network call, such as a VIES VAT-number check or ECB exchange rates, must be optional and user-initiated and must send no ledger data. CORS may block it; if so, flag it rather than adding a backend.

## Design principles (enforced)
Tooling enforces these rules where a tool exists; the principle audit (see Process) covers the rest. When rules conflict, this order wins: legal invariants and data integrity, then security, then SSOT, then simplicity (YAGNI, LEAN) over abstraction (SOLID). Record any trade-off in the relevant ADR or change summary.

- **AGILE.** Every stage ends in working, deployed software. Keep changes small and reviewable, one concern per commit. Prefer reversible decisions, and make the irreversible ones (schema, file format, encryption) explicitly, in ADRs.
- **LEAN.** One toolchain: TypeScript on Node, scripts included. Every new dependency or tool needs a one-line justification: what it replaces, its size, its maintenance status, its license. Automate any step a script or CI can do.
- **YAGNI.** Build only what the current phase needs. Add no flags, options or extension points without a present use. Create an interface only on a real boundary (browser API, storage, crypto, jurisdiction) or once a second implementation exists. knip runs in CI and fails on unused files, exports and dependencies.
- **DRY and SSOT.** Every piece of knowledge has exactly one authoritative representation.
  - *Schema:* the migrations are the only schema definition. Row types are generated from the migrated schema; CI regenerates them and fails on any difference.
  - *Reference data:* rates, thresholds, layouts and chart templates live in versioned data files inside their jurisdiction module and are read through one loader.
  - *Accounts:* logic refers to account roles (e.g. "VAT payable") resolved through the chart of accounts, never to account numbers.
  - *Configuration:* one typed config module holds names, paths, ports, hosts, URLs, storage keys and VFS names. Values that differ per deployment, such as the GitHub Pages base path, come from validated build-time environment variables. Lint rejects magic numbers in domain code and path or URL literals outside the config module.
  - *Protocol:* message types and error codes are defined once and imported by both the worker and the UI.
  - *Versions:* the app version comes from `package.json` and the schema version from the latest migration; neither is copied into a constant.
  - *Docs:* link to the source of truth (DDL, config, ADRs) instead of restating it.

  Code that looks alike but encodes different knowledge is not duplication, and tests may repeat setup for readability. jscpd checks non-test code in CI.
- **SOLID**, applied at module boundaries rather than as ceremony:
  - *Single responsibility:* each module and component does one thing; ESLint `complexity` is capped at 10 per function.
  - *Open/closed:* a jurisdiction plugs into the core without editing it.
  - *Liskov substitution:* every implementation of a boundary interface (storage, backup target, jurisdiction) passes one shared contract-test suite.
  - *Interface segregation:* interfaces are small and role-specific; a backup target is not a database store.
  - *Dependency inversion:* domain code depends on interfaces it owns, and the worker, SQLite, OPFS and WebCrypto are adapters behind them. Lint enforces the import boundaries: domain code imports no UI, worker or browser APIs.

## Coding standards
- TypeScript `strict`, plus `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`, `noImplicitOverride` and `noFallthroughCasesInSwitch`. No `any`, no non-null assertions, and switches over discriminated unions are exhaustive.
- ESLint with typescript-eslint `strict-type-checked` and `stylistic-type-checked`, react-hooks and jsx-a11y, with `naming-convention` enforced. Prettier formats everything, SQL included (`prettier-plugin-sql`, SQLite dialect, snake_case identifiers).
- Domain primitives are branded types (`MinorUnits`, `BasisPoints`, `CalendarDate`, `AccountId`, `CurrencyCode`), created only through validating constructors, so the compiler rejects mixing them up.
- No swallowed errors and no floating promises. Errors cross the worker boundary as typed error codes.
- Comments explain why, not what.
- Testing:
  - Domain logic is unit-tested in Node. SQL is tested against the same SQLite WASM build the app ships. Storage, workers, encryption and backup/restore are tested in real browsers with Playwright.
  - Test behavior, not constants: property-based tests for ledger invariants (random entries, reversal round-trips, trial balance nets to zero), golden-file tests for reports with fixtures you can explain line by line, and migration tests.
  - CI enforces at least 90% branch coverage on domain and database modules.
- No `eslint-disable`, `@ts-expect-error`, skipped test or lowered threshold without an inline reason and my approval. Never special-case code to make a test pass, and never present placeholders or stubs as working code. If a test or rule looks wrong, say so; label anything unfinished.
- The same checks run in a pre-commit hook and in CI; CI is authoritative. Commits follow Conventional Commits, releases follow SemVer, and the changelog calls out every schema migration.
- PEP 8 is Python's style guide. This codebase has no Python, and the TypeScript rules above serve the same purpose. Scripts stay in TypeScript to keep one toolchain; if Python is ever added, it follows PEP 8, enforced by ruff in CI.

## Security standards
- Verify against OWASP ASVS 5.0 Level 2. Many controls assume a server, so `docs/security.md` records which ones apply and why the rest do not.
- Build the threat model with STRIDE for each trust boundary: UI, worker, storage, crypto, import/export, and the build and deploy pipeline.
- Use a strict CSP, delivered by `<meta>` where the host cannot send headers, with `'wasm-unsafe-eval'` for WASM and nothing broader. Enable Trusted Types where supported. No `dangerouslySetInnerHTML`, and no third-party scripts, fonts or CDNs at runtime.
- Limit `connect-src` to the app's own origin plus the optional lookup endpoints listed in config, so the browser itself blocks every other outbound request. Verify that the policy also applies inside the worker: a same-origin worker script takes its CSP from its own response headers, not from the page's `<meta>` tag.
- Validate every imported file (backup restore, file handoff, CSV) at the boundary. Open an imported database following SQLite's "Defense Against the Dark Arts" guidance (defensive mode, `trusted_schema=OFF`, integrity check), and check its schema against the known migrations before using it.
- Neutralize CSV formula injection in exports without corrupting negative amounts.
- Use WebCrypto or audited libraries only, never custom cryptographic primitives. Keys and passwords are never logged, stored in plaintext or transmitted.
- Privacy by design (GDPR Art. 25): no telemetry, analytics or remote error reporting. Logs contain no amounts, names or keys.
- Supply chain:
  - commit the lockfile and install with `npm ci`;
  - keep dependencies minimal and license-compatible, with Dependabot updates;
  - run CodeQL, a dependency audit and secret scanning in CI;
  - pin GitHub Actions to commit SHAs and give workflows least-privilege permissions;
  - keep no credentials in the repository or the bundle;
  - ship an SBOM (`npm sbom`, CycloneDX) and a build-provenance attestation with each release;
  - make builds reproducible, so users can check the deployed bundle against the tagged source.
- Publish a `SECURITY.md` with a coordinated vulnerability disclosure process, and note in `docs/security.md` whether the EU Cyber Resilience Act (Regulation (EU) 2024/2847) applies.

## Process
Work in stages. At the end of each stage, stop and wait for my approval. Begin every stage plan and every change summary with a principle audit: list only the design-principle violations you found and the leaner alternative you chose.

### Stage 1: design only, no application code
Begin with your assumptions and the open questions that block decisions. Then deliver:
1. `docs/architecture.md`, containing:
   - Mermaid component and data-flow diagrams (UI ↔ worker ↔ SQLite ↔ OPFS ↔ crypto ↔ backup targets);
   - trust boundaries;
   - the browser support matrix.
2. `docs/security.md`, containing:
   - the STRIDE threat model. It protects against a lost or stolen device while the app is locked, other origins, and casual access to the browser profile. It does not protect against malware, malicious extensions, XSS on this origin, or a compromised build or dependency; list the controls that reduce those risks anyway.
   - the ASVS applicability record.
3. `docs/adr/`: one ADR per hard problem, each with context, options, decision and consequences.
4. The schema as the first migration: executable DDL with the constraints, indexes and triggers that enforce the invariants. Add a table mapping each invariant to how it is enforced and tested, e.g. `| Posted entry balances | trigger on status → 'posted' | property test over random entries |`.
5. SQL for the trial balance, general ledger, balance sheet, P&L and VAT summary. Explain how each is derived from journal lines and how account-to-report-line mappings work.
6. The worker protocol: TypeScript types for requests, responses, errors and transactions. Show how a failed multi-statement operation rolls back and how errors reach the UI.
7. The roadmap below, refined with risks and exit criteria for each phase.
8. `CLAUDE.md` holding the lasting rules from this prompt (invariants, design principles, coding and security standards, non-goals, commands) so they carry over to future sessions. Point to the config files that enforce the rules instead of restating them.

### Stage 2 onward: one roadmap phase per stage
A phase is done when every CI gate passes, the static build deploys, and the ADRs and docs reflect any decision that changed.

## Roadmap
0. **Walking skeleton.** Retire technical risk first: worker plus SQLite WASM on OPFS, migration runner, typed protocol, PWA shell, CI running Playwright in all three engines, deployment to the target host, and a spike of the encryption design from ADR 2. Every gate from the design principles and the coding and security standards runs in CI from the first commit, because tightening later costs more. List the repository settings for me to apply (protected main branch, required checks).
1. **Ledger core.** A hierarchical chart of accounts built from the reference template and extensible by the user; journals, drafts, posting, reversals, numbering, period locks and the hash chain; trial balance and general ledger.
2. **Durability.** Backup and restore, integrity checks, persistent storage, backup reminders, migration fixtures.
3. **Reports.** Balance sheet and P&L in the generic and reference layouts (including abridged versions), journal reports, and exports to SQLite, CSV and JSON.
4. **VAT.** VAT codes, versioned rates, reverse charge and intra-EU, VAT summary, EC Sales List data, and mapping to the reference VAT return.
5. **Encryption.** The design from ADR 2: key slots for the password, recovery code and passkeys, lockout prevention, encrypted backups, and documented decryption outside the app (with the password or recovery code).
6. **Year-end and hardening.** Fiscal-year close, audit-file export for the reference jurisdiction, accessibility audit, benchmarks at 100k entries, mutation testing (Stryker) on money, VAT and posting logic, ASVS Level 2 verification, a reproducible-build check, and a security review.
