# ADR 9: Performance

- **Status:** Proposed. Targets come from the PRD; the numbers below are hypotheses until the Phase 0 benchmark runs.
- **Requirements:** NFR-1, NFR-2, NFR-3, G6, LED-11.
- **Related:** [ADR 2](adr-02-encryption-vfs.md) (cold-start steps), [ADR 6](adr-06-tamper-evidence.md) (chain verification), [migration-001.sql](../schema/migration-001.sql), [queries.sql](../schema/queries.sql).

## Context

NFR-1 targets, on 100 000 entries (about 300 000 lines) on a mid-range laptop, in every supported engine:

- one account balance under 50 ms;
- trial balance and financial statements under 500 ms;
- interactive within 2 s of a cold start, excluding the time to type a password. The cold-start budget covers key derivation, decryption, opening the database, `quick_check` and chain verification (PROMPT.md);
- no main-thread task over 50 ms while queries run.

## Options considered

**Balance computation**

| Option                                                                  | Notes                                                                                                                                                   |
| ----------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A. Compute from indexed journal lines at query time                     | **Chosen first.** Always correct, no second copy (invariant 3). Needs the right indexes.                                                                |
| B. Aggregate table of account and period totals, maintained by triggers | Fast reads. A second copy, which must be rebuildable from the journal and checkable against it (invariant 3). Adds trigger logic to every posting path. |
| C. Aggregate table rebuilt by the app                                   | Rejected: drifts unless every write goes through one path, and the DDL cannot enforce that.                                                             |

**Keeping drafts out of the hot path.** Draft lines live in the same table as posted lines. Options: a partial index, a denormalized flag, or a separate draft table. A partial index cannot reference another table, and a flag set on posting would have to update lines of a row that is posted, which LED-2 forbids. **Chosen:** a partial index on `entries` (`WHERE status = 'posted'`), with queries that repeat `e.status = 'posted'` literally so the planner uses it. A separate draft table is rejected: it duplicates the line structure for no gain at this size.

**Threading.** All SQL runs in the worker. The UI thread receives result rows in pages for lists, and one result for summaries. No query runs on the UI thread.

## Decision

1. **Indexes in migration-001** (covering, so balance queries do not visit table rows):
   - `entry_lines_by_entry (entry_id, account_id, debit_minor, credit_minor)`;
   - `entry_lines_by_account (account_id, entry_id, debit_minor, credit_minor)`;
   - `entries_posted_by_period (period_id, id) WHERE status = 'posted'`.
     The UNIQUE constraints also create indexes (`entries(journal_id, fiscal_year_id, entry_number)`, `entry_lines(entry_id, line_no)`, `accounts(number)`).
2. **No aggregate tables in v1.** Option A first. Option B is added only if the benchmark shows the Option A plan misses NFR-1 at full scale, with the benchmark result cited in the migration that adds it.
3. **Benchmark harness (Phase 0):** a seeded database generator (100 000 entries, 300 000 lines, deterministic seed) run in Chromium through Playwright for the browser path, and in Node with the same SQLite WASM build for the SQL path. Results go to CI as an artifact, with thresholds from NFR-1. Thresholds are not loosened without an owner decision.
4. **Cold-start budget, measured in steps:** key derivation (PBKDF2 count from ADR 2), decryption, open, `quick_check`, chain verification (ADR 6). Each step is timed. If the sum breaks 2 s, the first step to cut is chain verification (tail on open, full pass on export), with the choice recorded in ADR 6.
5. **CI query-plan check:** `EXPLAIN QUERY PLAN` runs for each hot query in [queries.sql](../schema/queries.sql) (trial balance, general ledger, balance sheet, P&L) on the seeded database. The check fails on a `SCAN` of `entry_lines` or of `entries` without an index. The expected plans are stored as a snapshot file and compared in CI.
6. **Main-thread budget:** a Playwright test records long tasks (over 50 ms) on the UI thread while the reports run. Result rows are paged for lists.

## Consequences

- The first design is simple and has no duplicate state. It is correct by construction, and the risk sits in measurable numbers.
- The partial index only helps queries that repeat the status literal. A lint or review rule keeps this true, and the query-plan check catches a regression.
- A future aggregate table would need trigger code on every posting path and a rebuild command, so it is a deliberate step with a benchmark behind it.
- Benchmark results depend on hardware. CI runners are not "mid-range laptops". The CI gate uses relative thresholds against a reference run on the same runner class, and the absolute NFR-1 numbers are checked on a documented laptop before each phase exit. The PRD does not define this split, so it is listed for owner approval in [prd-updates-stage1.md](../prd-updates-stage1.md).
