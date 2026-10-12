# ADR 2: Encryption vs the VFS

- **Status:** Proposed. The persistence path is fixed in Phase 0 by a spike; encryption ships in Phase 5.
- **Requirements:** SEC-1, SEC-2, SEC-3, SEC-4, SEC-5, DAT-1, DAT-9, NFR-1.
- **Related:** [ADR 1](adr-01-hosting-opfs-vfs.md), [ADR 3](adr-03-attachments.md), [ADR 9](adr-09-performance.md), [security.md](../security.md).

## Context

WebCrypto is asynchronous; SQLite's VFS I/O is synchronous. Encryption therefore cannot sit inside a plain `opfs-sahpool` read or write without a bridge. Two approaches exist:

- **A. In-memory database with encrypted snapshots.** The database lives in WASM memory. A snapshot (`sqlite3_serialize`), encrypted with the data key, is written to OPFS.
- **B. Page-level encryption through a cipher-enabled build.** SQLite3 Multiple Ciphers (MIT licence, prebuilt WASM, no C toolchain) encrypts pages below the pager. The database stays a file on the VFS. SEE, SQLite's own encryption extension, is ruled out by its licence.

PROMPT.md asks for one persistence path for encrypted and unencrypted databases. Option B meets that: encryption is a key supplied on open, and an unencrypted database simply has no key.

## Options considered

| Criterion | A. In-memory + snapshots | B. Cipher build on `opfs-sahpool` |
| --- | --- | --- |
| Crash loss | Everything since the last snapshot. A snapshot rewrites the whole database, so snapshotting per commit is too costly at 300 000 lines. | Per-transaction, like any SQLite file. |
| Memory | Whole database in WASM memory. Capped by the largest single allocation of the build and the browser (verify in the spike). Conflicts with large attachments (ADR 3). | Page cache only. |
| Single persistence path | Unencrypted databases would also be in memory, so the crash-loss problem applies to everyone. | Yes. |
| Compatibility | Uses only the proven `sqlite3_serialize` path. | Codec compatibility with OPFS VFSes is undocumented. Must be proven. |
| Ciphers | Our choice (WebCrypto AES-GCM over the snapshot). | Limited to the codecs the build ships. |
| Dependencies | None beyond WebCrypto. | One prebuilt WASM artifact from a third party (verify its hash in the build). |

**Ciphers.** SEC-1 names AES-256-GCM. I could not verify in this session whether the prebuilt Multiple Ciphers WASM exposes an AES-256-GCM page cipher. If it does not, the choice is between an owner-approved change to SEC-1 (for example to ChaCha20-Poly1305 or AES-256-CBC with HMAC, whichever the build offers and the spike validates) and option A. This is a PRD change, not an engineering choice, and it goes to the owner ([prd-updates-stage1.md](../prd-updates-stage1.md)).

**KDF.**

| Option | Notes |
| --- | --- |
| PBKDF2-HMAC-SHA-256 via WebCrypto | Native, no dependency. OWASP's Password Storage Cheat Sheet gives 600 000 iterations for this function (to be re-checked at Phase 5). Time is measured in the cold-start budget (NFR-1). |
| Argon2id via an audited WASM library | Memory-hard, which is better against GPU attackers. Adds a dependency and WASM startup cost. |

**Chosen for v1: PBKDF2-HMAC-SHA-256 at the current OWASP count**, because it adds no dependency and stays inside the cold-start budget. The KDF id and its parameters are stored in each key slot, so Argon2id can be added later for new slots without re-encrypting data (PROMPT.md, hard problem 2). If the Phase 0 benchmark shows the count breaks NFR-1, the count is lowered only with a written reason, and Argon2id is reconsidered.

## Decision

1. **Persistence path: option B**, the cipher build on `opfs-sahpool` (ADR 1), **gated by a Phase 0 spike.** The spike must show: open, write and read persistence through reload; `pauseVfs()` takeover; codec on and off with the same VFS; AES-256-GCM or the owner-approved alternative; a seeded 300 000-line database inside the NFR-1 budget. **If the spike fails**, fall back to option A and accept its crash-loss and memory limits in writing before Phase 5.
2. **Data key (DEK):** 256-bit random, generated once per database. The DEK never changes unless the owner asks for a rekey.
3. **Key slots:** each unlock method wraps the DEK separately. A slot row holds: kind (`password`, `recovery`, `passkey`), KDF id and parameters, salt, wrap nonce, wrapped DEK, and creation time. Changing a method adds or removes a slot and never re-encrypts data (SEC-2). The slot table ships in a Phase 5 migration, not in migration-001.
4. **Recovery code:** 128 bits of CSPRNG output, shown once. Stored as a slot like the others, with the same KDF path.
5. **Passkeys:** WebAuthn PRF output, through HKDF, wraps the DEK. A passkey slot is a per-device convenience. The app confirms the slot with an immediate unlock before saving it. Support varies by platform; the password and recovery code always work (PRD §6).
6. **Nonce strategy:** a random 96-bit nonce per DEK wrap (few wraps, so collisions are negligible). For pages, the nonce is whatever the codec defines; the spike must confirm it. If the codec uses a random nonce per page write, the app counts page writes per key and forces a rekey well before the GCM limit of 2^32 random-nonce messages per key. The threshold is set after the spike.
7. **Key material:** the DEK exists only in the worker. Lock (SEC-4) closes the database, overwrites the JavaScript buffer, and drops the references. The WASM heap is not reliably wiped by the runtime; this residual is recorded in [security.md](../security.md).
8. **No plaintext at rest while encryption is on (SEC-1).** The attachment store (ADR 3) and backups use the same codec. Backups carry all slots (DAT-1).
9. **Lockout rules (SEC-3)** are domain invariants on the slot set, not UI checks: the recovery slot cannot be removed; at least one slot besides the recovery slot must exist before the last non-recovery slot is removed; turning encryption on requires re-entering the recovery code. Each rule has a property test.
10. **Offline attack.** An attacker with the file can guess passwords without limit, because nothing online can throttle them. The KDF cost is the only defence. This is why the password policy and the KDF count matter, and why the threat model says so ([security.md](../security.md)).

## Consequences

- One persistence path for both modes. Unencrypted work is not a second code path.
- The spike is on the critical path for Phase 0. If option B fails, Phase 5 gets a larger scope, and the crash-loss statement goes to the owner.
- SEC-1 wording may change (cipher name). That is a PRD decision, listed in [prd-updates-stage1.md](../prd-updates-stage1.md).
- The codec adds a third-party WASM artifact. It is pinned by version and hash, and the license (MIT) is recorded.
- Passkey support will be partial, so the password path must stay complete and tested on its own.
