# ADR 6: Tamper evidence

- **Status:** Proposed.
- **Requirements:** LED-10, LED-2, RPT-5, DAT-2, NFR-1.
- **Related:** [ADR 5](adr-05-migrations.md), [ADR 9](adr-09-performance.md), [security.md](../security.md) (clock and file-replacement limits).

## Context

LED-2 makes posted entries immutable through the database. That stops edits made through the app. It does not stop an edit made with an external SQLite tool on the file. LED-10 asks for detection of such edits, against a head hash recorded outside the file (printed per RPT-5). Whoever controls the file can rewrite entries and recompute every hash, so the chain proves something only against a head that was recorded elsewhere (PROMPT.md, hard problem 6).

SQLite core has no SHA-256 function, so hashes are computed in TypeScript and stored by the posting transaction. The DDL enforces the chain positions and that hashes exist on posted rows (migration-001, `posting_seq`, `content_hash`, `chain_hash` checks). It cannot check that a hash is correct.

## Options considered

**What is hashed**

| Option                                                | Verdict                                                                                            |
| ----------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| Raw rows of `entries` and `entry_lines`               | Rejected. Any schema migration that changes a column order or type changes the hash.               |
| Canonical, versioned serialization of business values | **Chosen.** Only the values that define the posted entry, in a fixed order, with a version prefix. |

**Canonical form (v1):** a UTF-8 string built field by field, each value length-prefixed, in this order: format tag `gogol-entry-v1`, journal code, fiscal year start date, entry number, accounting date, description, posted-at UTC instant, then each line in `line_no` order: account id, side, minor-unit amount. Account **ids** are used, not account numbers, because numbers can be renamed (LED-6 logs the rename, the entry must not change).

**Chain:** `chain_hash(n) = SHA-256(chain_hash(n-1) || content_hash(n))`, where `chain_hash(0)` is `SHA-256("gogol-chain-v1")`. Ordered by `posting_seq`, which migration-001 keeps gapless.

**Hash function and timing**

| Option                                                        | Notes                                                                                                                                                          |
| ------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| WebCrypto `subtle.digest`                                     | Async. One await per entry for 100 000 entries is too slow (PROMPT.md).                                                                                        |
| Synchronous audited JavaScript SHA-256 (e.g. `@noble/hashes`) | Synchronous, small, MIT. **Chosen**, pending a check of its audit status and size at adoption. One new dependency, justified: it replaces 100 000 async calls. |
| Hashing in parallel batches                                   | Kept as the fallback if the synchronous library is too slow in the benchmark.                                                                                  |

**Verification schedule**

| Check                           | When                                                                                                               | Why                                                          |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------ |
| `PRAGMA quick_check`            | Every open                                                                                                         | Cheap structural check (DAT-2, invariant 6).                 |
| Full chain verification         | Every open, inside the NFR-1 cold-start budget; tail-only if the budget breaks, with the full pass moved to export | Detects edits to posted history at open (LED-10 acceptance). |
| `PRAGMA integrity_check` (full) | On import, on restore, before export                                                                               | Thorough, slower (DAT-2).                                    |
| Full chain verification         | Before export and after every migration (ADR 5)                                                                    | The printed head must match what the file gives.             |

## Decision

1. Hash the canonical v1 serialization of each entry at posting, in the posting transaction (`content_hash`), and extend the chain (`chain_hash`). Both are stored; the values are immutable after posting (LED-2).
2. The serialization is a pure function in domain code with its own golden-file tests. A new serialization version is a new tag (`gogol-entry-v2`), never an edit of v1. Old entries keep their version.
3. Verification recomputes `content_hash` from the stored values, then `chain_hash`, and compares. A mismatch returns `ChainViolation` with the first broken `posting_seq` as detail (no amounts).
4. The **head** is the `chain_hash` of the highest `posting_seq`. Every report and export prints it with the period and generation time (RPT-5). The user keeps printed heads outside the file.
5. **Limits, documented in [security.md](../security.md):** before a head is first printed nothing is detectable; a whole-file replacement that also recomputes the chain matches only if the attacker is recomputing from a head nobody recorded, so the user must compare printed heads; the clock that stamps `posted_at_utc` is the user's; LED-10 detects edits, it does not prevent them. **Audit log not in the chain:** `audit_log` rows (account renames, role reassignments, settings changes) are protected by append-only triggers in the app but are not included in the hash chain. An external tool that bypasses the triggers can delete audit log rows without raising a LED-10 violation. This limit is recorded in security.md §4.

## Consequences

- Chain verification costs one pass over posted entries on open. Measured in the Phase 0 benchmark (NFR-1). The benchmark decides whether open runs the full pass or the tail.
- The domain code owns the canonical form; the DDL owns only the presence and order checks. The two must agree, so the canonical-form tests also read rows from the migrated schema.
- A new dependency (synchronous SHA-256) with a one-line justification in the dependency list.
- Schema migrations do not break the chain, because the serialization does not depend on physical columns (ADR 5).
