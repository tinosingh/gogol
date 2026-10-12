# ADR 5: Migrations

- **Status:** Proposed.
- **Requirements:** DAT-6, DAT-2, LED-10, LED-2, DAT-9.
- **Related:** [ADR 4](adr-04-durability.md) (restore uses the runner), [ADR 6](adr-06-tamper-evidence.md) (chain after rebuild), [ADR 1](adr-01-hosting-opfs-vfs.md) (service worker and tabs).

## Context

Each user's database lives on their device, so no one upgrades it centrally. Upgrades run in the browser, unattended, against data that cannot be replaced (DAT-6, PROMPT.md hard problem 5). Migrations must be forward-only and transactional, and tested against fixture databases from every released schema version. SQLite cannot change `foreign_keys` inside a transaction, and a table rebuild drops its triggers.

## Options considered

**Version marker**

| Option | Notes |
| --- | --- |
| `PRAGMA user_version` | One integer in the file header. No extra table. Read and written inside the transaction. **Chosen.** |
| `schema_migrations` table | Records history, which the app does not need (YAGNI). Another table to keep in sync. |

**Runner**

| Option | Notes |
| --- | --- |
| Up-only SQL files, numbered, applied in one transaction each | **Chosen.** Matches "the migrations are the only schema definition" (PROMPT.md SSOT). |
| Down migrations | Rejected: a rollback would run older code against data it does not understand, and the hash chain (LED-10) must stay verifiable. Recovery is restore from backup. |

**Table rebuilds:** SQLite's documented procedure for changes ALTER TABLE cannot express: foreign keys off (outside any transaction), begin, create the new table, copy rows, drop the old table, rename, recreate indexes, triggers and views, run `foreign_key_check`, commit, foreign keys on. Prefer `ALTER TABLE ADD COLUMN`, `RENAME` and `DROP COLUMN` where they suffice (SQLite 3.35+).

**Service-worker update policy**

| Option | Notes |
| --- | --- |
| Activate new code immediately | Rejected: an open tab could run old JavaScript against a database migrated by new code. |
| Wait, then reload when no database connection is open | **Chosen.** The single-connection rule (ADR 1) makes "no connection open" checkable. |

## Decision

1. **Forward-only, numbered files:** `docs/schema/migration-001.sql`, `migration-002.sql`, … The schema version is the number of the latest file (PROMPT.md SSOT: not copied into a constant).
2. **Runner, on open:**
   1. Read `PRAGMA user_version`. If it is greater than the latest known number, **refuse** with `SchemaMismatch` (DAT-6). The database is not touched.
   2. If it is lower, take an automatic backup first (DAT-6): a copy written to the OPFS pool, or `VACUUM INTO` if the spike confirms it works there (ADR 4). If the backup fails, stop; do not migrate.
   3. Set `foreign_keys` on or off as the migration needs, before `BEGIN`. Apply each pending file inside its own `BEGIN IMMEDIATE … COMMIT`, then set `user_version` in the same transaction.
   4. After each file: `PRAGMA foreign_key_check` must be empty and `PRAGMA quick_check` must return `ok`. Any failure rolls back that file.
   5. For a table rebuild, the trigger list of the migrated schema must equal the expected list (a test reads `sqlite_master`), so a rebuilt table cannot lose its immutability triggers silently (LED-2).
3. **Hash chain after a rebuild:** the migration keeps `content_hash` and `chain_hash` unchanged. The runner runs the full chain verification (ADR 6) after any migration that touches `entries` or `entry_lines`.
4. **Tests:** a fixture database for every released version lives in the repository. Each one migrates to the latest version, passes the full invariant suite, and produces the same trial balance as before the migration. CI fails if a released version has no fixture.
5. **Service worker:** the new service worker waits and does not take over an open page. The app reloads into the new version only when the worker holds no database connection. An old tab that sees a newer `user_version` refuses to run and says so (DAT-6). This is the policy that stops stale code running against a migrated database.
6. **Migrations are reviewed as schema changes:** the changelog calls out each one (PROMPT.md process).

## Consequences

- A failed upgrade leaves the file as it was, plus the automatic backup. Nothing is lost.
- Every migration needs a fixture-based test and a documented rebuild if it touches a trigger table. The cost is accepted: the books are the product.
- No downgrade path. A user who opens data in an older app must restore a backup instead.
- The migration runner is itself a boundary with DAT-2 (restore runs it on an imported copy).
- Pre-migration backup doubles the storage needed during upgrade. The UI checks the quota before starting.
