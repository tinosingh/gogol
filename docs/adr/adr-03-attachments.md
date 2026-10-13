# ADR 3: Attachments

- **Status:** Proposed. Storage location and limits are decided here. Adding to posted entries and the 10 MiB limit were decided by the owner on 2026-10-13 (PRD D8, DAT-5).
- **Requirements:** DAT-5, DAT-1, DAT-2, SEC-1, LED-2.
- **Related:** [ADR 2](adr-02-encryption-vfs.md) (codec), [ADR 4](adr-04-durability.md) (backup), [ADR 5](adr-05-migrations.md) (schema change).

## Context

DAT-5: vouchers (receipts, invoices) attach to entries and are kept for the retention period (typically 5 to 10 years, PRD §1). Ten years of scanned vouchers can reach gigabytes. Backups and restores must stream (PROMPT.md, hard problem 3). DAT-1 requires one backup file that holds the books, the vouchers and all key slots as of one point in time.

## Options considered

| Option                                            | Atomic backup (DAT-1)                                                                  | Memory                                          | Notes                                                                                        |
| ------------------------------------------------- | -------------------------------------------------------------------------------------- | ----------------------------------------------- | -------------------------------------------------------------------------------------------- |
| **A. BLOB rows in the database, chunked**         | Yes. One file, one transaction, one point in time.                                     | Chunked reads and writes; no whole-file buffer. | The database file grows to gigabytes. Covered by the page codec (ADR 2).                     |
| B. Files in an OPFS directory, referenced by hash | Needs a container format and two-phase consistency between the database and the files. | Streams per file.                               | Easy to get wrong: a backup can capture a database that references a file not yet copied.    |
| C. Files outside OPFS (user's disk only)          | Not atomic with the books.                                                             | Streams.                                        | Violates "one copy, one point in time" and makes encryption of the vouchers a separate path. |

A single whole-BLOB value is not an option under any choice: SQLite's default maximum length is about 1 GB (`SQLITE_MAX_LENGTH`) and reading one BLOB loads it into memory.

## Decision

1. **Option A: attachments live in the database**, in a table of chunks. Each attachment has a row (id, entry reference, file name, media type, byte length, SHA-256, created time), and its bytes sit in ordered chunk rows of a fixed size set in config. The chunk size is a config value, not a literal (SSOT).
2. **Streaming:** upload writes chunks in one transaction per attachment. Download and backup read chunks one at a time. The backup streams database pages through the sink port (`Backup` in [worker-protocol.ts](../worker-protocol.ts)) rather than building the file in memory.
3. **Integrity:** the stored SHA-256 is checked on read. The restore path runs `integrity_check` (ADR 6), then checks each attachment's hash (DAT-2).
4. **Retention (DAT-5):** an attachment of a posted entry cannot be deleted. Triggers in the Phase 2 migration reject `DELETE` on an attachment whose entry is posted, using the `LED-2/delete` prefix so the worker maps it to `ImmutabilityViolation`.
5. **Adding to posted entries:** allowed (owner decision, 2026-10-13), because late vouchers are normal, and the entry's accounting content stays immutable (LED-2). The attachment table records when it was added.
6. **Media types and size:** an allow-list (PDF, PNG, JPEG, and any type the owner adds). **Per-file limit: 10 MiB** (owner decision, 2026-10-13; PRD D8). Attachments live in the database and in every backup, so a smaller limit keeps both bounded. It is set in config, so it can be raised later without a schema change.
7. **Export:** attachments travel in the full backup and are not exported as loose files in v1 (DAT-7 covers CSV of journals and reports). Loose export is a later decision (YAGNI).
8. **Content-type safety for future preview:** the stored `media_type` column is set at upload from the allow-list check, not derived from the file's bytes. Any future inline preview feature MUST re-derive the content type from the raw bytes (magic-byte sniff) and serve the blob with `Content-Disposition: attachment`; it must never trust the stored `media_type` value to decide rendering. `image/svg+xml` with embedded script executes in the app's origin; it must stay off the allow-list.

## Consequences

- One file holds the books and the vouchers. Backup, restore, encryption and the retention rule use the same paths as the rest of the database.
- The database can reach gigabytes. The UI shows storage use (`navigator.storage.estimate()`) and warns before the quota, not after. The browser quota differs per engine and is not promised by the PRD.
- Chunked storage adds a small write overhead per attachment. Acceptable for a voucher workload.
- The per-file limit bounds the chunk count and the restore time; it is the main knob the owner controls.
- Schema: the attachment tables are added in a Phase 2 migration (not in migration-001, YAGNI).
