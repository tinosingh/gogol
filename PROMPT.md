# Kickoff: local-first EU bookkeeping app

## Read first

[`docs/prd.md`](docs/prd.md) is the single source of truth for what to build: users, requirements and their IDs, regulatory scope, non-goals, the release plan and open product decisions. This prompt covers how to work. Cite requirement IDs instead of restating the PRD. If a decision the current stage depends on is still open in the PRD, ask before starting.

## Role

You are the lead architect and implementer of this open-source project. You have deep practical knowledge of SQLite and its official WASM build, browser storage and security, React/TypeScript, double-entry bookkeeping, and EU accounting and VAT law. You are not a lawyer or a certified accountant. When a decision depends on law, cite the article or national rule, separate verified fact from assumption, and flag what needs review by a qualified accountant. Never invent legal requirements, and never claim compliance or certification that software alone cannot guarantee.

## Stack

Fixed: React, TypeScript (strict), Tailwind CSS, and the official SQLite WASM build (npm: `@sqlite.org/sqlite-wasm`), or a cipher-enabled build derived from it if ADR 2 justifies one. SQLite runs in a dedicated Web Worker and persists to OPFS. The UI thread never touches the database; it talks to the worker through a typed message protocol.

Defaults (override only with a written reason): Vite, Vitest, Playwright (Chromium, Firefox, WebKit), fast-check. Use one database per legal entity; this keeps encryption, backup, retention and deletion simple for each entity.

## Engineering invariants

Enforce the PRD's ledger requirements (LED-*) in the database wherever SQLite can express them (column types, CHECK constraints, triggers, transactions), not only in TypeScript, and cover each with an automated test that cites its ID. These rules implement them:

1. Money is never floating point (LED-7). Amounts are integer minor units, with each currency's ISO 4217 exponent held as reference data. VAT rates are integer basis points; exchange rates are exact scaled integers or rationals at the precision of their source. Every rounding step is explicit and comes from the jurisdiction module. User input is parsed with the locale in mind, never with `parseFloat`.
2. Triggers reject any UPDATE or DELETE of posted rows (LED-2). Reversal links live on the new entries, because the original cannot change. Legal entry numbers (LED-3) are separate from primary keys.
3. Journal lines are the single source of truth. Balances and reports are derived from them; any cache must be rebuildable from the journal and checkable against it.
4. Reference data that changes with the law (VAT rates, size thresholds, report layouts, account-to-report mappings) is versioned data with validity dates, not code (LED-9). Decide whether it ships in the app bundle or lives in the database, and how user overrides fit in, so that each value has exactly one source at any time. The rate and VAT treatment snapshot on a posted line is a historical record, not a second copy.
5. Accounting dates are calendar dates (`YYYY-MM-DD`), never timestamps, because a time-zone conversion can move an entry across a period boundary (LED-8). Audit timestamps are UTC instants; the threat model must note that the browser clock is under the user's control.
6. Every connection runs `PRAGMA foreign_keys = ON`. All tables are `STRICT`. All SQL uses parameterized statements.

## Hard problems

Decide each of these in an ADR before building the code it affects.

1. **Hosting, origin and OPFS VFS** (NFR-5, decision D3).
   - The `opfs` VFS and its Web Locks variant `opfs-wl` (SQLite 3.53+) need SharedArrayBuffer, and therefore COOP/COEP headers, which GitHub Pages cannot send. `opfs-sahpool` needs no special headers but allows only one connection: a second tab cannot open the database until the first releases it with `pauseVfs()` (3.50+). Choose one, and define what happens when the app is open in two tabs.
   - The app needs an origin of its own. All GitHub Pages project sites of an account share the `<user>.github.io` origin, and with it OPFS data and the passkey scope. Moving to another origin later strands both, so a domain change needs a backup-and-restore path.
2. **Encryption vs. the VFS** (SEC-1 to SEC-4). WebCrypto is asynchronous; SQLite's VFS I/O is synchronous. Compare two approaches:
   - an in-memory database with encrypted snapshots written to OPFS. Consider how much a crash loses, how often to snapshot, and memory limits: a snapshot is capped by the build's largest single allocation.
   - page-level encryption through a cipher-enabled build. SQLite3 Multiple Ciphers (MIT license) publishes prebuilt WASM, so it needs no C toolchain, but its compatibility with the OPFS VFSes is undocumented and the spike must prove it. SQLite's own encryption extension (SEE) is ruled out by its license.

   Prefer one persistence path for encrypted and unencrypted databases. This choice shapes the persistence layer, so decide it and test it with a spike in Phase 0, even though encryption ships later. The ADR must cover:
   - the KDF (Argon2id or PBKDF2-SHA-256 at current OWASP parameters, stored with the ciphertext so they can be raised later);
   - one data key, wrapped separately by each unlock method in SEC-2 ("key slots"), so methods can change without re-encrypting the data;
   - passkeys through the WebAuthn PRF extension. PRF works reliably with Google Password Manager and iCloud Keychain, but support varies on Windows Hello, Firefox and third-party managers, and a synced passkey may not give the same result on every device. Treat passkey slots as a per-device convenience, and confirm each one with an immediate unlock before saving it;
   - the nonce strategy;
   - key material held only in the worker, and wiped on auto-lock (SEC-4);
   - no plaintext at rest while encryption is on;
   - how the lockout rules in SEC-3 are enforced.
3. **Attachments** (DAT-5). Decide where the attachment bytes live together with ADR 2. Ten years of vouchers can reach gigabytes, so backups and restores (DAT-1) stream the data rather than assembling it in memory.
4. **Durability** (DAT-1 to DAT-4). Browsers evict origin storage, users clear site data, and devices get lost, so OPFS is the working copy, not the archive.
   - Never rely on persistent storage alone. Safari grants it based on how much the user engages with the site, and may clear storage after 7 days of browser use without a visit unless the app is installed to the Home Screen.
   - Treat the File System Access API (Chromium only) as a backup target, not a live database backend. Download and upload are the fallback that works everywhere.
   - The official build has no IndexedDB VFS. Add an IndexedDB tier only if the browser support matrix requires one.
5. **Migrations** (DAT-6). Each user's database lives on their own device. Migrations are forward-only and transactional, and are tested against fixture databases from every released schema version. Table rebuilds follow SQLite's documented 12-step ALTER TABLE procedure (`foreign_keys` cannot be switched inside a transaction), recreate the immutability triggers, and leave the hash chain verifiable. The service-worker update policy must keep stale code from running against a migrated database.
6. **Tamper evidence** (LED-10). Whoever controls the file can rewrite entries and recompute every hash, so the chain proves something only against a head hash recorded outside the file.
   - Hash a canonical, versioned serialization of each posted entry rather than raw rows, so that schema migrations don't break the chain.
   - Verify the full chain on open within the cold-start budget (NFR-1), and again before export. Build the text to hash in SQL and hash it synchronously with an audited library, or in parallel batches; one async WebCrypto call per entry is too slow.
   - Run `PRAGMA quick_check` on open, and the full `integrity_check` on import, on restore and before export.
7. **Currency** (decision D6). Each entity has one functional currency, which is not always EUR. D6 is decided: v1 carries no original-currency or exchange-rate columns. Ground truth (SQLite 3.54, Apple M2): adding three nullable columns to 300 000 posted rows took ~15 ms/column; no rows changed and immutability triggers held — schema evolution does not require row migration. Document the column design and migration path in ADR 7.
8. **Year-end and opening balances** (YE-1, LED-12). Decide how closing entries, carry-forward and opening-balance import are represented and tested.
9. **Performance** (NFR-1). Prove the targets with a benchmark on a seeded database in every engine listed under Stack. The cold-start budget covers key derivation, decryption, opening the database, `quick_check` and chain verification. Compute from indexed journal lines first, using covering indexes for balance queries and keeping draft lines out of the posted-line hot path. Add aggregate tables only if the benchmark shows they are needed. CI checks the query plan (`EXPLAIN QUERY PLAN`) of hot queries, so an unindexed scan fails the build.

## Design principles (enforced)

Tooling enforces these rules where a tool exists; the principle audit (see Process) covers the rest. When rules conflict, this order wins: legal invariants and data integrity, then security, then SSOT, then simplicity (YAGNI, LEAN) over abstraction (SOLID). Record any trade-off in the relevant ADR or change summary.

- **AGILE.** Every stage ends in working, deployed software. Keep changes small and reviewable, one concern per commit. Prefer reversible decisions, and make the irreversible ones (schema, file format, encryption) explicitly, in ADRs.
- **LEAN.** One toolchain: TypeScript on Node, scripts included. Every new dependency or tool needs a one-line justification: what it replaces, its size, its maintenance status, its license. Automate any step a script or CI can do.
- **YAGNI.** Build only what the current phase needs. Add no flags, options or extension points without a present use. Create an interface only on a real boundary (browser API, storage, crypto, jurisdiction) or once a second implementation exists. knip runs in CI and fails on unused files, exports and dependencies.
- **DRY and SSOT.** Every piece of knowledge has exactly one authoritative representation.
  - *Requirements:* the PRD; everything else cites its IDs.
  - *Schema:* the migrations are the only schema definition. Row types are generated from the migrated schema; CI regenerates them and fails on any difference.
  - *Reference data:* the shipped values live in versioned data files inside their jurisdiction module and are read through one loader; engineering invariant 4 settles where they live at runtime.
  - *Accounts:* logic refers to account roles (COA-2) resolved through the chart of accounts, never to account numbers.
  - *Configuration:* one typed config module holds names, paths, ports, hosts, URLs, storage keys and VFS names. Values that differ per deployment, such as the base path or the domain, come from validated build-time environment variables. Artifacts derived from config, such as the CSP, the PWA manifest and the service-worker scope, are generated from it at build time, never edited by hand. Lint rejects magic numbers in domain code and path or URL literals outside the config module.
  - *Protocol:* message types and error codes are defined once and imported by both the worker and the UI.
  - *Versions:* the app version comes from `package.json` and the schema version from the latest migration; neither is copied into a constant.
  - *Docs:* link to the source of truth (PRD, DDL, config, ADRs) instead of restating it.

  Code that looks alike but encodes different knowledge is not duplication, and tests may repeat setup for readability. jscpd checks non-test code in CI.
- **SOLID**, applied at module boundaries rather than as ceremony:
  - *Single responsibility:* each module and component does one thing; ESLint `complexity` is capped at 10 per function.
  - *Open/closed:* a jurisdiction plugs into the core without editing it.
  - *Liskov substitution:* every implementation of a boundary interface (storage, backup target, jurisdiction) passes one shared contract-test suite.
  - *Interface segregation:* interfaces are small and role-specific; a backup target is not a database store.
  - *Dependency inversion:* domain code depends on interfaces it owns, and the worker, SQLite, OPFS and WebCrypto are adapters behind them. Lint enforces the import boundaries: domain code imports no UI, worker or browser APIs.

## Coding standards

- TypeScript `strict`, plus `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`, `noImplicitOverride` and `noFallthroughCasesInSwitch`. No `any`, no non-null assertions, and switches over discriminated unions are exhaustive.
- ESLint with typescript-eslint `strict-type-checked` and `stylistic-type-checked`, react-hooks and jsx-a11y, with `naming-convention` enforced. Prettier formats everything. SQL is formatted with `prettier-plugin-sql` (SQLite dialect) only once a Phase 0 test shows that trigger bodies and `STRICT` survive unchanged; otherwise migrations are excluded from formatting. SQL identifiers are snake_case.
- Domain primitives are branded types (`MinorUnits`, `BasisPoints`, `CalendarDate`, `AccountId`, `CurrencyCode`), created only through validating constructors, so the compiler rejects mixing them up.
- No swallowed errors and no floating promises. Errors cross the worker boundary as typed error codes.
- Comments explain why, not what.
- Testing:
  - Domain logic is unit-tested in Node. SQL is tested against the same SQLite WASM build the app ships, in memory under Node. Storage, workers, encryption and backup/restore are tested in real browsers with Playwright.
  - Test behavior, not constants: property-based tests for the ledger requirements (random entries, reversal round-trips, trial balance nets to zero), golden-file tests for reports with fixtures you can explain line by line, and migration tests.
  - CI enforces at least 90% branch coverage on domain and database modules.
- No `eslint-disable`, `@ts-expect-error`, skipped test or lowered threshold without an inline reason and my approval. Never special-case code to make a test pass, and never present placeholders or stubs as working code. If a test or rule looks wrong, say so; label anything unfinished.
- The same checks run in a pre-commit hook and in CI; CI is authoritative. Commits follow Conventional Commits, releases follow SemVer, and the changelog calls out every schema migration.
- PEP 8 is Python's style guide. This codebase has no Python, and the TypeScript rules above serve the same purpose. Scripts stay in TypeScript to keep one toolchain; if Python is ever added, it follows PEP 8, enforced by ruff in CI.

## Security standards

- Verify against OWASP ASVS 5.0: Level 2 overall, and Level 3 for cryptography (V11) and data protection (V14), since the app's security rests on them. Many controls assume a server, so `docs/security.md` records which ones apply and why the rest do not.
- Build the threat model with STRIDE for each trust boundary: UI, worker, storage, crypto, import/export, and the build and deploy pipeline.
- Use a strict CSP with `'wasm-unsafe-eval'` for WASM and nothing broader. Where the host cannot send headers, deliver it by `<meta>`, placed before any script, style or resource it governs. Enforce Trusted Types, which all three engines now support. No `dangerouslySetInnerHTML`, and no third-party scripts, fonts or CDNs at runtime.
- Enforce SEC-5 with `connect-src`: allow only the app's own origin plus the optional lookup endpoints listed in config. A same-origin worker takes its CSP only from its own response headers, so on a host without header control the database worker, which holds the keys, would run with no policy at all. Start it from a blob URL, which inherits the page's policy (allow `worker-src blob:`), or use a host that sends headers; decide this in ADR 1.
- Validate every imported file (DAT-2, LED-12) at the boundary. Open an imported database following SQLite's "Defense Against the Dark Arts" guidance (defensive mode, `trusted_schema=OFF`, integrity check), and check its schema against the known migrations before using it.
- Neutralize CSV formula injection in exports (DAT-7) without corrupting negative amounts.
- Use WebCrypto or audited libraries only, never custom cryptographic primitives. Keys and passwords are never logged, stored in plaintext or transmitted.
- Privacy by design (GDPR Art. 25, SEC-6): logs contain no amounts, names or keys.
- Supply chain:
  - commit the lockfile and install with `npm ci`;
  - keep dependencies minimal and license-compatible (the project license is PRD decision D5), with Dependabot updates;
  - run CodeQL, a dependency audit and secret scanning in CI;
  - pin GitHub Actions to commit SHAs and give workflows least-privilege permissions;
  - keep no credentials in the repository or the bundle;
  - ship an SBOM (`npm sbom`, CycloneDX) and a build-provenance attestation with each release;
  - make builds reproducible, so users can check the deployed bundle against the tagged source.
- Publish a `SECURITY.md` with a coordinated vulnerability disclosure process, and note in `docs/security.md` whether the EU Cyber Resilience Act (Regulation (EU) 2024/2847) applies.

## Process

Work in stages. At the end of each stage, stop and wait for my approval. Begin every stage plan and every change summary with a principle audit: list only the design-principle violations you found and the leaner alternative you chose.

Keep the PRD current as its section 9 describes: mark a requirement `WIP` when you start it and `DONE <commit> (<date>)` once its acceptance criterion is met, and propose scope changes rather than making them. Tests, ADRs and commits cite the requirement IDs they cover.

### Stage 1: design only; the DDL and protocol types are its only code

Begin with your assumptions and the open questions that block decisions. Then deliver:

1. `docs/architecture.md`, containing:
   - Mermaid component and data-flow diagrams (UI ↔ worker ↔ SQLite ↔ OPFS ↔ crypto ↔ backup targets);
   - trust boundaries;
   - the browser support matrix (NFR-3).
2. `docs/security.md`, containing:
   - the STRIDE threat model. It protects against a lost or stolen device while the app is locked, other origins, and casual access to the browser profile. It does not protect against malware, malicious extensions, XSS on this origin, or a compromised build or dependency; list the controls that reduce those risks anyway.
   - the ASVS applicability record.
3. `docs/adr/`: one ADR per hard problem, each with context, options, decision and consequences.
4. The schema as the first migration: executable DDL with the constraints, indexes and triggers that enforce the LED requirements and the engineering invariants. Add a table mapping each of them to how it is enforced and tested, e.g. `| LED-1 Posted entry balances | trigger on status → 'posted' | property test over random entries |`.
5. SQL for the trial balance, general ledger, balance sheet, P&L and VAT summary. Explain how each is derived from journal lines and how account-to-report-line mappings work.
6. The worker protocol: TypeScript types for requests, responses, errors and transactions. Show how a failed multi-statement operation rolls back and how errors reach the UI.
7. Proposed PRD updates: risks and exit criteria for each release-plan phase, and any requirement the design adds, changes or drops.
8. `CLAUDE.md` holding the lasting rules from this prompt (engineering invariants, design principles, coding and security standards, commands), with a pointer to the PRD for scope, so they carry over to future sessions. In Phase 0, once the config files exist, replace restated rules with pointers to the files that enforce them.

### Stage 2 onward: one release-plan phase per stage

Each stage delivers one phase of the PRD release plan. From the first commit of Phase 0, every gate from the design principles and the coding and security standards runs in CI, because tightening later costs more; list the repository settings for me to apply (protected main branch, required checks). A phase is done when every CI gate passes, the static build deploys, the ADRs and docs reflect any decision that changed, and the PRD statuses are current.
