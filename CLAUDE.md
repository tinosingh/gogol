# CLAUDE.md: gogol engineering rules

Lasting rules for future sessions. Scope and requirements live in [docs/prd.md](docs/prd.md). Decisions live in [docs/adr/](docs/adr/). Requirement IDs (LED-*, DAT-*, SEC-*, NFR-*, …) are cited, never restated. Workflow and staging rules are in [PROMPT.md](PROMPT.md).

## Stack (fixed)

- React, TypeScript (strict), Tailwind CSS.
- SQLite via the official WASM build `@sqlite.org/sqlite-wasm`, or a cipher-enabled build if [ADR 2](docs/adr/adr-02-encryption-vfs.md) is accepted.
- SQLite runs in a dedicated Web Worker and persists to OPFS (`opfs-sahpool`, [ADR 1](docs/adr/adr-01-hosting-opfs-vfs.md)). The UI thread never touches the database.
- Defaults unless a written reason overrides them: Vite, Vitest, Playwright (Chromium, Firefox, WebKit), fast-check.
- One database per legal entity.

## Engineering invariants

1. **Money is never floating point (LED-7).** Amounts are INTEGER minor units. Exponents come from reference data. VAT rates are integer basis points. Rounding is explicit and comes from the jurisdiction module. Parse user input with the locale; never `parseFloat`.
2. **Posted rows are immutable (LED-2).** Triggers reject UPDATE and DELETE on posted entries and their lines. A correction is a reversal plus a new entry, linked by `reverses_entry_id`. Legal entry numbers (LED-3) are separate from primary keys.
3. **Journal lines are the single source of truth.** Balances and reports derive from them. Any cache must be rebuildable from the journal and checkable against it.
4. **Law-dependent reference data is versioned data with validity dates (LED-9).** Each value has one source at a time. A posted line's rate and VAT treatment are a historical record, not a second copy.
5. **Accounting dates are `YYYY-MM-DD` (LED-8).** Never timestamps. Audit timestamps are UTC instants. The browser clock is user-controlled and is named as such in the threat model.
6. **Every connection runs `PRAGMA foreign_keys = ON`. All tables are `STRICT`. All SQL uses bound parameters.**

Enforce LED rules in the database wherever SQLite can express them, and cover each with a test that cites its ID. The requirement-to-enforcement map is at the end of [docs/schema/migration-001.sql](docs/schema/migration-001.sql).

## Design principles

Order when rules conflict: legal invariants and data integrity, then security, then SSOT, then simplicity (YAGNI, LEAN) over abstraction (SOLID). Record trade-offs in the relevant ADR.

- **AGILE:** every stage ends in working, deployed software. One concern per commit. Irreversible choices (schema, file format, encryption) get an ADR.
- **LEAN:** one toolchain (TypeScript, including scripts). Every dependency needs a one-line justification: what it replaces, size, maintenance, licence.
- **YAGNI:** no flags, options or extension points without a present use. Interfaces only at real boundaries (browser API, storage, crypto, jurisdiction) or with a second implementation.
- **DRY and SSOT:**
  - Requirements: PRD only. Schema: migrations only; row types generated from the migrated schema.
  - Reference data: versioned data files, one loader.
  - Accounts: logic uses account roles (COA-2), never account numbers.
  - Config: one typed module holds names, paths, ports, hosts, URLs, storage keys and VFS names. Lint rejects magic numbers in domain code and path or URL literals outside config.
  - Protocol: message types and error codes defined once, imported by worker and UI ([docs/worker-protocol.ts](docs/worker-protocol.ts)).
  - Versions: from `package.json` and the latest migration; never copied into a constant.
  - Docs link to the source of truth instead of restating it.
- **SOLID**, at module boundaries only:
  - Single responsibility; ESLint `complexity` capped at 10.
  - Open/closed: a jurisdiction plugs in without editing the core.
  - Liskov: every backup target, storage and jurisdiction implementation passes one shared contract-test suite.
  - Interface segregation: small, role-specific interfaces.
  - Dependency inversion: domain code imports no UI, worker or browser API (lint-enforced).
- **Config files:** pointers to be added in Phase 0 (ESLint, tsconfig, knip, jscpd, Prettier, CI workflow). Replace restated rules with pointers to those files once they exist.

## Coding standards

- TypeScript: `strict`, `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`, `noImplicitOverride`, `noFallthroughCasesInSwitch`. No `any`. No non-null assertions. Discriminated-union switches are exhaustive.
- ESLint: typescript-eslint `strict-type-checked` and `stylistic-type-checked`, react-hooks, jsx-a11y, `naming-convention`. Prettier everywhere. SQL formatting only after a Phase 0 test shows triggers and `STRICT` survive it; otherwise migrations are excluded. SQL identifiers are snake_case.
- Branded domain types (`MinorUnits`, `BasisPoints`, `CalendarDate`, `AccountId`, `CurrencyCode`), created only through validating constructors.
- No swallowed errors. No floating promises. Errors cross the worker boundary as typed error codes, never raw exceptions.
- Comments explain why, not what.
- No `eslint-disable`, `@ts-expect-error`, skipped test or lowered coverage threshold without an inline reason and the owner's approval. Never special-case code to pass a test. Label unfinished work; never present stubs as working code.
- Testing:
  - Domain logic: unit tests in Node.
  - SQL: tests against the same SQLite WASM build the app ships, in memory under Node.
  - Storage, workers, encryption, backup and restore: Playwright in real browsers.
  - Property tests for LED requirements; golden files for reports with explainable fixtures; migration tests from every released schema version.
  - At least 90% branch coverage on domain and database modules.
- Commits: Conventional Commits. Releases: SemVer. The changelog calls out every schema migration.
- Python: none. If added, PEP 8, enforced by ruff in CI.

## Security standards

- Verify against OWASP ASVS 5.0: Level 2 overall; Level 3 for V11 (cryptography) and V14 (data protection). [docs/security.md](docs/security.md) records what applies and why server-side controls are N/A.
- Threat model: STRIDE per trust boundary (UI, worker, storage, crypto, import and export, build and deploy). Keep it current in security.md.
- CSP by `<meta>` before any script, style or resource: `'wasm-unsafe-eval'` for WASM and nothing broader. Trusted Types where enforced. No `dangerouslySetInnerHTML`. No third-party scripts, fonts or CDNs at runtime.
- `connect-src` allows only the app's own origin and the lookup endpoints in config (SEC-5).
- Validate every imported file at the boundary (DAT-2): defensive SQLite open, `trusted_schema = OFF`, integrity and schema checks.
- Neutralize CSV formula injection in exports without corrupting negative amounts (DAT-7).
- WebCrypto or audited libraries only. Never custom primitives. Keys and passwords are never logged, stored in plaintext or transmitted.
- Logs contain no amounts, names or keys (SEC-6, GDPR Art. 25).
- Supply chain: committed lockfile, `npm ci`, minimal dependencies, Dependabot, CodeQL, dependency audit and secret scanning in CI, actions pinned to commit SHAs, least-privilege workflow permissions, no credentials in the repository or the bundle, SBOM (CycloneDX) and build provenance per release, reproducible builds.
- `SECURITY.md` with coordinated disclosure.

## Commands

Placeholder. Fill in during Phase 0, once `package.json` and the config files exist. Do not guess commands before then.

- Install: `npm ci`
- Dev server: TBD
- Unit and SQL tests: TBD
- Browser tests: TBD
- Lint, typecheck, format: TBD
- Benchmark: TBD
- Migration check: TBD

## Where to look

- Scope, requirements, decisions D1 to D7, release plan: [docs/prd.md](docs/prd.md)
- Architecture and browser matrix: [docs/architecture.md](docs/architecture.md)
- Security and ASVS applicability: [docs/security.md](docs/security.md)
- Decisions: [docs/adr/](docs/adr/)
- Ledger DDL and requirement map: [docs/schema/migration-001.sql](docs/schema/migration-001.sql)
- Reporting queries: [docs/schema/queries.sql](docs/schema/queries.sql)
- Worker protocol: [docs/worker-protocol.ts](docs/worker-protocol.ts)
- Proposed PRD changes awaiting owner approval: [docs/prd-updates-stage1.md](docs/prd-updates-stage1.md)
