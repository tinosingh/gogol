# ADR 4: Durability

- **Status:** Proposed.
- **Requirements:** DAT-1, DAT-2, DAT-3, DAT-4, G5.
- **Related:** [ADR 1](adr-01-hosting-opfs-vfs.md), [ADR 3](adr-03-attachments.md), [ADR 5](adr-05-migrations.md).

## Context

Browsers evict origin storage, users clear site data, and devices get lost (PROMPT.md, hard problem 4). OPFS is therefore the working copy. The archive is a backup file the user keeps. Safari grants persistent storage by engagement, and may clear storage after seven days of browser use without a visit unless the app is installed to the Home Screen (PROMPT.md; to re-verify against Apple's current documentation in Phase 2).

## Options considered

**Backup targets** (interface: a backup target accepts a byte stream and a name; a restore source yields one. Interface segregation, PROMPT.md SOLID.)

| Target | Engines | Notes |
| --- | --- | --- |
| Download (`<a download>` from a Blob or a stream) | All | The fallback that works everywhere (PROMPT.md). The browser decides the folder. |
| File System Access API (`showSaveFilePicker`, writable stream) | Chromium only | Writes straight to a path the user picks, so no download folder juggling. Not a live database backend. |
| IndexedDB tier | All | Rejected: the official build has no IndexedDB VFS, and a second store adds a second copy to keep consistent. Added only if the browser matrix requires it (it does not, on the current assumptions). |

**Persistence:** `navigator.storage.persist()` is requested on first run (DAT-4). Where it is denied or unsupported, and on Safari, the UI recommends installing the app (DAT-4). The app never relies on the grant alone.

**Backup reminder (DAT-3):** the time of the last successful external backup is stored in the database (in the books' own file, so a restore brings back the matching reminder state). The interval is config. The reminder appears on open once the interval has passed.

## Decision

1. **OPFS is the working copy. The backup file is the archive.** The UI says so on first run and in the backup screen.
2. **Backup:** the worker streams a consistent snapshot (SQLite online backup API, or `VACUUM INTO` if the spike shows it works on `opfs-sahpool`) through a `MessagePort` (ADR 3). The UI writes it to the chosen target. Target is File System Access where available, otherwise download. The format is the encrypted or plain SQLite file (DAT-9 documents it).
3. **Restore:** the file is untrusted (DAT-2). Steps: check the SQLite header, open in defensive mode with `trusted_schema = OFF`, run `integrity_check`, read `user_version`, refuse a newer version (DAT-6), run the migration runner (ADR 5) on a copy, then replace the working copy. The working copy is not touched until every check passes.
4. **Restore replaces, never merges.** Merging two ledgers would need a conflict model that the PRD does not ask for (sync is a non-goal, PRD §5).
5. **Persistence:** `persist()` requested on first run (DAT-4); install recommendation shown where it applies.
6. **Reminder:** DAT-3 as above.

## Consequences

- Download works everywhere, so every engine in NFR-3 can complete a backup and a restore (G5).
- The File System Access path is a Chromium convenience. Its absence is never a failure.
- Each backup is a full copy. With gigabyte-sized attachment stores (ADR 3), the backup size and time become visible to users; the UI shows the estimated size before writing.
- Restore needs a copy of the working database during the swap, so the quota must hold two copies. The UI checks the estimate first.
- Re-verify before Phase 2: Safari's current eviction rules, and whether `VACUUM INTO` works through `opfs-sahpool`.
