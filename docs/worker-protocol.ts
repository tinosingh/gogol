/**
 * SQLite worker message protocol: types only (Stage 1). Imported by the worker and the UI, so the
 * message shapes and error codes are defined once (PROMPT.md, DRY/SSOT: protocol).
 *
 * Rules that the types encode
 * - The UI thread never touches the database; it sends an Envelope and receives a ProtocolResponse.
 * - Every request runs as one unit of work. Write requests run in BEGIN IMMEDIATE, read requests in a
 *   deferred read transaction. Nothing is committed unless the whole unit succeeds (section "Transactions").
 * - Failures cross the boundary only as typed ErrorCodes. The worker never throws across postMessage.
 * - Error messages carry no amounts, names, account numbers or keys (privacy, PROMPT.md security standards).
 *
 * Ids and money are branded (PROMPT.md coding standards). Values are created only through validating
 * constructors in the domain module, which is not part of this file.
 */

// -----------------------------------------------------------------------------
// Branded primitives
// -----------------------------------------------------------------------------

declare const brand: unique symbol;
type Brand<T, B extends string> = T & { readonly [brand]: B };

export type RequestId = Brand<string, 'RequestId'>;
export type AccountId = Brand<number, 'AccountId'>;
export type JournalId = Brand<number, 'JournalId'>;
export type PeriodId = Brand<number, 'PeriodId'>;
export type FiscalYearId = Brand<number, 'FiscalYearId'>;
export type EntryId = Brand<number, 'EntryId'>;

/** Integer minor units of the entity's functional currency; 0 <= value <= 10^15 - 1 (LED-7, migration-001). */
export type MinorUnits = Brand<number, 'MinorUnits'>;
/** 'YYYY-MM-DD' calendar date (LED-8). Never a timestamp. */
export type CalendarDate = Brand<string, 'CalendarDate'>;
/** Lowercase hex SHA-256 (LED-10). */
export type Sha256Hex = Brand<string, 'Sha256Hex'>;
/** Stable requirement reference, e.g. 'LED-1' or 'DAT-2'. Keeps the PRD as the single source of IDs. */
export type RequirementId = `${'COA' | 'LED' | 'VAT' | 'RPT' | 'DAT' | 'SEC' | 'YE' | 'NFR' | 'LIC'}-${number}`;

// -----------------------------------------------------------------------------
// Envelope
// -----------------------------------------------------------------------------

export interface Envelope<R extends Request> {
  readonly id: RequestId;
  readonly body: R;
}

// -----------------------------------------------------------------------------
// Requests
// -----------------------------------------------------------------------------

export type EntrySide = 'debit' | 'credit';

export interface EntryLineInput {
  readonly accountId: AccountId;
  readonly side: EntrySide;
  readonly amount: MinorUnits;
  readonly description?: string;
}

export interface EntryDraft {
  readonly id?: EntryId; // absent for a new draft
  readonly journalId: JournalId;
  readonly accountingDate: CalendarDate;
  readonly description: string;
  readonly lines: readonly EntryLineInput[];
}

/** Request shapes keyed by their discriminant. Adding a request means adding one key here. */
export interface RequestPayloads {
  // Lifecycle
  OpenDatabase: { readonly mode: 'readwrite' }; // Busy if another tab holds the connection (ADR 1)
  RunMigration: Record<never, never>; // forward-only; runs after an automatic backup (DAT-6)
  VerifyIntegrity: { readonly level: 'quick' | 'full' }; // quick_check on open, full integrity_check on import, restore, export (ADR 6)

  // Ledger writes (LED-*)
  SaveDraft: { readonly draft: EntryDraft }; // LED-11
  PostEntry: { readonly entryId: EntryId }; // LED-1, LED-3, LED-4, LED-10
  ReverseEntry: {
    readonly entryId: EntryId; // the posted original (LED-2)
    readonly accountingDate: CalendarDate;
    readonly description: string;
  };

  // Reads (RPT-*). Read-only transactions; drafts excluded (LED-11).
  QueryTrialBalance: { readonly periodId: PeriodId }; // RPT-1
  QueryGeneralLedger: { readonly accountId: AccountId; readonly periodId: PeriodId }; // RPT-2

  // Backup and restore (DAT-1, DAT-2). Bytes stream through a MessagePort, never one buffer (ADR 3).
  Backup: { readonly sink: MessagePort };
  // source is untrusted: integrity and schema checks first (DAT-2). Worker must reject if source.size
  // exceeds the current storage quota estimate before opening it — an unbounded Blob can exhaust worker
  // memory before any SQLite check runs.
  Restore: { readonly source: Blob };
}

export type RequestType = keyof RequestPayloads;

export type Request = { readonly [K in RequestType]: { readonly type: K } & RequestPayloads[K] }[RequestType];

/** Read or write. Decides BEGIN DEFERRED or BEGIN IMMEDIATE in the worker. */
export const requestMode = {
  OpenDatabase: 'write',
  RunMigration: 'write',
  VerifyIntegrity: 'read',
  SaveDraft: 'write',
  PostEntry: 'write',
  ReverseEntry: 'write',
  QueryTrialBalance: 'read',
  QueryGeneralLedger: 'read',
  Backup: 'read',
  Restore: 'write',
} as const satisfies Record<RequestType, 'read' | 'write'>;

// -----------------------------------------------------------------------------
// Responses
// -----------------------------------------------------------------------------

export interface PostedEntryRef {
  readonly entryId: EntryId;
  readonly entryNumber: number; // LED-3, scoped by journal and fiscal year
  readonly postingSeq: number; // LED-10 chain position
  readonly chainHash: Sha256Hex; // the printable head per RPT-5 is the latest of these
}

export interface TrialBalanceRow {
  readonly accountId: AccountId;
  readonly number: string;
  readonly name: string;
  readonly debitMinor: MinorUnits;
  readonly creditMinor: MinorUnits;
}

export interface GeneralLedgerRow {
  readonly entryId: EntryId;
  readonly entryNumber: number;
  readonly accountingDate: CalendarDate;
  readonly description: string;
  readonly debitMinor: MinorUnits;
  readonly creditMinor: MinorUnits;
  readonly reversesEntryId: EntryId | null;
  readonly reversedByEntryId: EntryId | null;
}

/** Success payload per request type. */
export interface ResponsePayloads {
  OpenDatabase: { readonly schemaVersion: number; readonly writable: boolean };
  RunMigration: { readonly fromVersion: number; readonly toVersion: number };
  VerifyIntegrity: { readonly chainHead: Sha256Hex | null };
  SaveDraft: { readonly entryId: EntryId };
  PostEntry: PostedEntryRef;
  ReverseEntry: PostedEntryRef;
  QueryTrialBalance: { readonly rows: readonly TrialBalanceRow[] };
  QueryGeneralLedger: { readonly rows: readonly GeneralLedgerRow[] };
  Backup: { readonly bytesWritten: number; readonly chainHead: Sha256Hex | null };
  Restore: { readonly schemaVersion: number };
}

export type Success<K extends RequestType = RequestType> = {
  readonly [P in K]: {
    readonly ok: true;
    readonly id: RequestId;
    readonly type: P;
    readonly data: ResponsePayloads[P];
  };
}[K];

export interface Failure {
  readonly ok: false;
  readonly id: RequestId;
  readonly error: ProtocolError;
}

export type ProtocolResponse = Success | Failure;

/** Typed success for a known request, for the UI's client-side wrapper. */
export type ResponseFor<K extends RequestType> = Success<K> | Failure;

// -----------------------------------------------------------------------------
// Errors
// -----------------------------------------------------------------------------

/** One code per failure mode. The UI maps code to an English message in one place (D7). */
export const ErrorCode = {
  BalanceViolation: 'BalanceViolation', // LED-1
  ImmutabilityViolation: 'ImmutabilityViolation', // LED-2
  NumberingViolation: 'NumberingViolation', // LED-3
  ClosedPeriod: 'ClosedPeriod', // LED-4 posting or change into a closed period or year
  PeriodViolation: 'PeriodViolation', // LED-4 invalid period range, overlap or fixed dates
  AccountViolation: 'AccountViolation', // LED-5 delete, retype or deactivated account
  AuditViolation: 'AuditViolation', // LED-6 audit log is append-only
  CurrencyLocked: 'CurrencyLocked', // LED-7 functional currency changed after postings
  DateViolation: 'DateViolation', // LED-8 invalid date or date outside its period
  ChainViolation: 'ChainViolation', // LED-10 posting order or chain verification failed
  InvalidInput: 'InvalidInput', // CHECK or type constraint at the boundary
  ReferenceViolation: 'ReferenceViolation', // foreign-key constraint
  NotFound: 'NotFound',
  Busy: 'Busy', // another tab holds the single connection (ADR 1)
  SchemaMismatch: 'SchemaMismatch', // DAT-6: newer or unknown schema; refused
  IntegrityCheckFailed: 'IntegrityCheckFailed', // quick_check or integrity_check failed (ADR 6)
  InvalidBackup: 'InvalidBackup', // DAT-2: corrupted or foreign file, detail says why
  StorageUnavailable: 'StorageUnavailable', // OPFS or I/O failure, quota
  Internal: 'Internal', // unexpected; no detail beyond the code reaches the UI
} as const;

export type ErrorCode = (typeof ErrorCode)[keyof typeof ErrorCode];

export interface ProtocolError {
  readonly code: ErrorCode;
  readonly requirement?: RequirementId;
  /** Developer diagnostic in English. Never contains amounts, names, account numbers or keys. */
  readonly detail?: string;
}

/**
 * Trigger RAISE prefixes in migration-001.sql, written as 'REQ' or 'REQ/sub' before the colon.
 * The worker maps the prefix with this table. A test reads the migrated schema and fails if a RAISE
 * prefix is missing here or a key here has no trigger (SSOT between DDL and worker).
 */
export const triggerErrorCode = {
  'LED-1': 'BalanceViolation',
  'LED-2/insert': 'ImmutabilityViolation',
  'LED-2/update': 'ImmutabilityViolation',
  'LED-2/delete': 'ImmutabilityViolation',
  'LED-2/reversal': 'ImmutabilityViolation',
  'LED-3': 'NumberingViolation',
  'LED-4/closed': 'ClosedPeriod',
  'LED-4/reopen': 'PeriodViolation',
  'LED-4/fixed': 'PeriodViolation',
  'LED-4/overlap': 'PeriodViolation',
  'LED-4/range': 'PeriodViolation',
  'LED-5/delete': 'AccountViolation',
  'LED-5/type': 'AccountViolation',
  'LED-5/inactive': 'AccountViolation',
  'LED-6': 'AuditViolation',
  'LED-7': 'CurrencyLocked',
  'LED-8': 'DateViolation',
  'LED-10': 'ChainViolation',
} as const satisfies Record<string, ErrorCode>;

export type TriggerErrorPrefix = keyof typeof triggerErrorCode;

/** Requirement that each code is evidence for. Lets the UI show "LED-2" next to "ImmutabilityViolation". */
export const errorRequirement = {
  BalanceViolation: 'LED-1',
  ImmutabilityViolation: 'LED-2',
  NumberingViolation: 'LED-3',
  ClosedPeriod: 'LED-4',
  PeriodViolation: 'LED-4',
  AccountViolation: 'LED-5',
  AuditViolation: 'LED-6',
  CurrencyLocked: 'LED-7',
  DateViolation: 'LED-8',
  ChainViolation: 'LED-10',
  InvalidBackup: 'DAT-2',
  SchemaMismatch: 'DAT-6',
} as const satisfies Partial<Record<ErrorCode, RequirementId>>;

// -----------------------------------------------------------------------------
// Transactions
// -----------------------------------------------------------------------------

/** Bind values accepted by the worker's SQL helper. Every value is bound, never concatenated. */
export type SqlValue = number | string | bigint | Uint8Array | null;

/**
 * The handle a unit of work receives. Work is synchronous: SQLite WASM calls are synchronous inside the worker,
 * and an await inside a transaction would let another message interleave with it.
 */
export interface TxHandle {
  run(sql: string, bind: readonly SqlValue[]): void;
  // Implementations must construct row objects with Object.create(null) to prevent prototype
  // pollution if a column alias ever matches '__proto__', 'constructor', or 'toString'.
  get<T extends Record<string, SqlValue>>(sql: string, bind: readonly SqlValue[]): T | undefined;
  all<T extends Record<string, SqlValue>>(sql: string, bind: readonly SqlValue[]): readonly T[];
}

/** Outcome of one unit of work. A failed unit leaves the database exactly as it was. */
export type TransactionOutcome<T> =
  | { readonly committed: true; readonly value: T }
  | { readonly committed: false; readonly error: ProtocolError };

/**
 * Transaction protocol, implemented once in the worker:
 *   1. BEGIN IMMEDIATE (writes) or BEGIN DEFERRED (reads).
 *   2. Run the unit of work through TxHandle. Each statement is a bound parameter list.
 *   3. On success: COMMIT, then return { committed: true, value }.
 *   4. On any throw: ROLLBACK, then map the error to a ProtocolError:
 *      - RAISE prefix 'LED-n[/sub]:' -> triggerErrorCode[prefix] with requirement 'LED-n'
 *      - SQLITE_CONSTRAINT_CHECK -> InvalidInput; SQLITE_CONSTRAINT_FOREIGNKEY -> ReferenceViolation
 *      - SQLITE_CORRUPT and quick_check/integrity_check failures -> IntegrityCheckFailed
 *      - SQLITE_FULL, SQLITE_IOERR and OPFS errors -> StorageUnavailable
 *      - anything else -> Internal (the original message is logged without data, never sent to the UI)
 *   5. COMMIT failure is treated as step 4; the worker never reports success for an uncommitted unit.
 *
 * A multi-entry operation (for example a reversal: insert the reversal, insert its lines, post it) is one
 * unit of work. Either the reversal and its numbering exist together, or neither does.
 */
export type UnitOfWork<T> = (tx: TxHandle) => T;

