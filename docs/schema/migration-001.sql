-- migration-001: ledger core
-- Phase 1 requirements: COA-1, COA-2, LED-1..LED-8, LED-10..LED-13, RPT-1, RPT-2 (see the requirement map at the end).
--
-- Conventions
--   * Forward-only. The runner applies this file in one transaction. PRAGMA foreign_keys cannot change inside a
--     transaction, so the runner sets it on the connection before BEGIN and asserts it afterwards; the statement
--     below documents the requirement and is a no-op inside the transaction.
--   * Parameterized statements are an application coding convention, not DDL: every value in application SQL is
--     bound with ? parameters, never concatenated.
--   * Money: INTEGER minor units of the entity's functional currency (LED-7, invariant 1, D6). No REAL columns.
--   * Accounting dates: TEXT 'YYYY-MM-DD', validated with date(x) IS x, which rejects NULL, timestamps and
--     non-existent dates such as 2026-02-30 (LED-8, invariant 5).
--   * Audit and posting timestamps: TEXT UTC instants. The browser clock is user-controlled (see docs/security.md).
--   * Trigger errors start with the requirement ID ('LED-1: ...'). The worker maps that prefix to a protocol error
--     code (docs/worker-protocol.ts), so every RAISE below must keep its prefix.
--   * Supporting tables beyond the first list (currencies, account_role_codes, number_sequences, report_line_map)
--     are needed for foreign keys, gapless numbering and report mapping. They are not optional extras.
--   * Table count and column set are kept minimal (YAGNI): no VAT, attachment or key-slot tables before their phase.
--     Those arrive in later migrations.

PRAGMA foreign_keys = ON;

-- =============================================================================
-- Reference data (versioned; invariant 4). The migration seeds the minimum the
-- schema needs. Adding a row later is a reference-data update, not a schema change.
-- =============================================================================

CREATE TABLE currencies (
  code     TEXT PRIMARY KEY CHECK (length(code) = 3 AND code NOT GLOB '*[^A-Z]*'),
  exponent INTEGER NOT NULL CHECK (exponent BETWEEN 0 AND 4)  -- ISO 4217 minor-unit exponent
) STRICT;

INSERT INTO currencies (code, exponent) VALUES ('EUR', 2);

CREATE TABLE account_role_codes (
  code TEXT PRIMARY KEY CHECK (length(code) BETWEEN 1 AND 40 AND code NOT GLOB '*[^a-z_]*')
) STRICT;

-- Seed covers the roles the Phase 1 to 6 features need by name (COA-2 examples, YE-1).
-- The Finnish chart template maps its accounts onto these codes.
INSERT INTO account_role_codes (code) VALUES
  ('cash_bank'), ('receivables'), ('payables'),
  ('vat_receivable'), ('vat_payable'),
  ('share_capital'), ('retained_earnings'), ('result_for_period');

-- =============================================================================
-- Entity (one database per legal entity; exactly one row)
-- =============================================================================

CREATE TABLE entities (
  id              INTEGER PRIMARY KEY CHECK (id = 1),
  legal_name      TEXT NOT NULL CHECK (length(legal_name) BETWEEN 1 AND 200),
  -- National business registry number. Format is not validated in v1: no verified rule is in the PRD.
  business_id     TEXT CHECK (business_id IS NULL OR length(business_id) BETWEEN 1 AND 40),
  currency_code   TEXT NOT NULL REFERENCES currencies(code),
  created_at_utc  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
) STRICT;

-- The functional currency cannot change once anything is posted: existing amounts would be reinterpreted.
CREATE TRIGGER entities_currency_locked
BEFORE UPDATE OF currency_code ON entities
WHEN NEW.currency_code IS NOT OLD.currency_code
BEGIN
  SELECT RAISE(ABORT, 'LED-7: functional currency cannot change after postings')
  WHERE EXISTS (SELECT 1 FROM entries WHERE status = 'posted');
END;

-- =============================================================================
-- Fiscal years and periods (LED-4, LED-8)
-- =============================================================================

CREATE TABLE fiscal_years (
  id         INTEGER PRIMARY KEY,
  start_date TEXT NOT NULL CHECK (date(start_date) IS start_date),
  end_date   TEXT NOT NULL CHECK (date(end_date) IS end_date AND start_date < end_date),
  status     TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed'))
) STRICT;

CREATE TRIGGER fiscal_years_no_overlap
BEFORE INSERT ON fiscal_years
BEGIN
  SELECT RAISE(ABORT, 'LED-4/overlap: fiscal year overlaps an existing fiscal year')
  WHERE EXISTS (SELECT 1 FROM fiscal_years f
                WHERE f.start_date <= NEW.end_date AND NEW.start_date <= f.end_date);
END;

-- Dates are fixed after creation: moving them would move posted entries between periods.
CREATE TRIGGER fiscal_years_dates_fixed
BEFORE UPDATE OF start_date, end_date ON fiscal_years
BEGIN
  SELECT RAISE(ABORT, 'LED-4/fixed: fiscal year dates are fixed');
END;

-- Closing is one-way in v1. Corrections go through a reversal in an open period.
CREATE TRIGGER fiscal_years_no_reopen
BEFORE UPDATE OF status ON fiscal_years
WHEN OLD.status = 'closed' AND NEW.status = 'open'
BEGIN
  SELECT RAISE(ABORT, 'LED-4/reopen: a closed fiscal year cannot be reopened');
END;

CREATE TABLE periods (
  id             INTEGER PRIMARY KEY,
  fiscal_year_id INTEGER NOT NULL REFERENCES fiscal_years(id),
  start_date     TEXT NOT NULL CHECK (date(start_date) IS start_date),
  end_date       TEXT NOT NULL CHECK (date(end_date) IS end_date AND start_date <= end_date),
  status         TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed'))
) STRICT;

CREATE TRIGGER periods_inside_fiscal_year_no_overlap
BEFORE INSERT ON periods
BEGIN
  SELECT RAISE(ABORT, 'LED-4/range: period lies outside its fiscal year or overlaps a period')
  WHERE NOT EXISTS (SELECT 1 FROM fiscal_years f
                    WHERE f.id = NEW.fiscal_year_id
                      AND NEW.start_date >= f.start_date AND NEW.end_date <= f.end_date)
     OR EXISTS (SELECT 1 FROM periods p
                WHERE p.fiscal_year_id = NEW.fiscal_year_id
                  AND p.start_date <= NEW.end_date AND NEW.start_date <= p.end_date);
END;

CREATE TRIGGER periods_dates_fixed
BEFORE UPDATE OF start_date, end_date, fiscal_year_id ON periods
BEGIN
  SELECT RAISE(ABORT, 'LED-4/fixed: period dates are fixed');
END;

CREATE TRIGGER periods_no_reopen
BEFORE UPDATE OF status ON periods
WHEN OLD.status = 'closed' AND NEW.status = 'open'
BEGIN
  SELECT RAISE(ABORT, 'LED-4/reopen: a closed period cannot be reopened');
END;

-- =============================================================================
-- Journals (LED-13)
-- =============================================================================

CREATE TABLE journals (
  id        INTEGER PRIMARY KEY,
  code      TEXT NOT NULL UNIQUE CHECK (length(code) BETWEEN 1 AND 10),
  name      TEXT NOT NULL CHECK (length(name) BETWEEN 1 AND 100),
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1))
) STRICT;
-- A journal with entries cannot be deleted: entries.journal_id has no ON DELETE action.

-- =============================================================================
-- Chart of accounts (COA-1, COA-2, LED-5)
-- =============================================================================

CREATE TABLE accounts (
  id           INTEGER PRIMARY KEY,
  -- Display number from the chart template. Logic never uses it; it refers to roles (COA-2).
  number       TEXT NOT NULL UNIQUE CHECK (length(number) BETWEEN 1 AND 20),
  name         TEXT NOT NULL CHECK (length(name) BETWEEN 1 AND 200),
  account_type TEXT NOT NULL CHECK (account_type IN ('asset', 'liability', 'equity', 'revenue', 'expense')),
  -- shortcut: parent cycles are not rejected in DDL; the app rejects them on insert and move, fix with a recursive check if a second writer appears.
  parent_id    INTEGER REFERENCES accounts(id),
  is_active    INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1))
) STRICT;

-- An account with postings is never deleted and never retyped. The explicit RAISE gives the worker an LED-5 code;
-- the FK from entry_lines would only report a generic foreign-key failure.
CREATE TRIGGER accounts_delete_locked_after_postings
BEFORE DELETE ON accounts
BEGIN
  SELECT RAISE(ABORT, 'LED-5/delete: an account with postings cannot be deleted')
  WHERE EXISTS (SELECT 1 FROM entry_lines WHERE account_id = OLD.id);
END;

CREATE TRIGGER accounts_type_locked_after_postings
BEFORE UPDATE OF account_type ON accounts
WHEN NEW.account_type IS NOT OLD.account_type
BEGIN
  SELECT RAISE(ABORT, 'LED-5/type: an account with postings cannot change type')
  WHERE EXISTS (SELECT 1 FROM entry_lines WHERE account_id = OLD.id);
END;

CREATE TABLE account_roles (
  role       TEXT PRIMARY KEY REFERENCES account_role_codes(code),
  -- UNIQUE: an account plays at most one role, so report-line mapping never assigns one balance to two lines.
  account_id INTEGER NOT NULL UNIQUE REFERENCES accounts(id)
) STRICT;
-- One account per role. Reassignment changes future postings only; posted lines keep the account they used (LED-2).

-- Maps each role code to a report line of a layout (RPT-4, Phase 3). Empty until the layouts are
-- designed; no Finnish layout values are invented here.
CREATE TABLE report_line_map (
  layout    TEXT NOT NULL CHECK (length(layout) BETWEEN 1 AND 40),
  role      TEXT NOT NULL REFERENCES account_role_codes(code),
  line_code TEXT NOT NULL CHECK (length(line_code) BETWEEN 1 AND 40),
  PRIMARY KEY (layout, role)
) STRICT;

-- =============================================================================
-- Entries and lines (LED-1, LED-2, LED-3, LED-10, LED-11)
-- =============================================================================

CREATE TABLE entries (
  id                INTEGER PRIMARY KEY,
  journal_id        INTEGER NOT NULL REFERENCES journals(id),
  fiscal_year_id    INTEGER NOT NULL REFERENCES fiscal_years(id),
  period_id         INTEGER NOT NULL REFERENCES periods(id),
  accounting_date   TEXT NOT NULL CHECK (date(accounting_date) IS accounting_date),
  description       TEXT NOT NULL CHECK (length(description) BETWEEN 1 AND 500),
  status            TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'posted')),
  -- Legal number (LED-3). Assigned only at posting; drafts have none. Separate from id (invariant 2).
  entry_number      INTEGER CHECK (entry_number IS NULL OR entry_number >= 1),
  -- Position in the global posting order, the chain order for LED-10. Assigned only at posting.
  posting_seq       INTEGER UNIQUE CHECK (posting_seq IS NULL OR posting_seq >= 1),
  -- Reversal link (LED-2). Set on the new entry; UNIQUE allows one reversal per original.
  reverses_entry_id INTEGER UNIQUE REFERENCES entries(id),
  -- Hashes are lowercase hex SHA-256 (64 chars). content_hash covers the canonical serialization (ADR 6).
  content_hash      TEXT CHECK (content_hash IS NULL OR (length(content_hash) = 64 AND content_hash NOT GLOB '*[^0-9a-f]*')),
  chain_hash        TEXT CHECK (chain_hash IS NULL OR (length(chain_hash) = 64 AND chain_hash NOT GLOB '*[^0-9a-f]*')),
  posted_at_utc     TEXT CHECK (posted_at_utc IS NULL OR posted_at_utc GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T*Z'),
  created_at_utc    TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  CHECK (
    (status = 'draft'  AND entry_number IS NULL AND posting_seq IS NULL AND content_hash IS NULL
                       AND chain_hash IS NULL AND posted_at_utc IS NULL)
    OR
    (status = 'posted' AND entry_number IS NOT NULL AND posting_seq IS NOT NULL AND content_hash IS NOT NULL
                       AND chain_hash IS NOT NULL AND posted_at_utc IS NOT NULL)
  ),
  UNIQUE (journal_id, fiscal_year_id, entry_number)   -- LED-3: no duplicates; NULLs (drafts) are exempt
) STRICT;

-- Partial index: drafts stay out of the posted hot path (NFR-1). Queries must repeat status = 'posted' literally.
CREATE INDEX entries_posted_by_period ON entries (period_id, id) WHERE status = 'posted';

-- An entry enters the table as a draft and is posted by UPDATE, so the posting checks below always run.
CREATE TRIGGER entries_insert_as_draft
BEFORE INSERT ON entries
WHEN NEW.status <> 'draft'
BEGIN
  SELECT RAISE(ABORT, 'LED-2/insert: entries are inserted as drafts and posted by update');
END;

-- The date and period must agree, and the period must belong to the fiscal year (LED-8, LED-4).
CREATE TRIGGER entries_date_in_period_insert
BEFORE INSERT ON entries
BEGIN
  SELECT RAISE(ABORT, 'LED-8: accounting date is outside its period or fiscal year')
  WHERE NOT EXISTS (SELECT 1 FROM periods p
                    WHERE p.id = NEW.period_id
                      AND p.fiscal_year_id = NEW.fiscal_year_id
                      AND NEW.accounting_date BETWEEN p.start_date AND p.end_date);
END;

CREATE TRIGGER entries_date_in_period_update
BEFORE UPDATE OF accounting_date, period_id, fiscal_year_id ON entries
BEGIN
  SELECT RAISE(ABORT, 'LED-8: accounting date is outside its period or fiscal year')
  WHERE NOT EXISTS (SELECT 1 FROM periods p
                    WHERE p.id = NEW.period_id
                      AND p.fiscal_year_id = NEW.fiscal_year_id
                      AND NEW.accounting_date BETWEEN p.start_date AND p.end_date);
END;

-- LED-2: posted rows are immutable. Only draft -> posted is allowed (the trigger below).
CREATE TRIGGER entries_posted_immutable_update
BEFORE UPDATE ON entries
WHEN OLD.status = 'posted'
BEGIN
  SELECT RAISE(ABORT, 'LED-2/update: posted entries are immutable');
END;

CREATE TRIGGER entries_posted_immutable_delete
BEFORE DELETE ON entries
WHEN OLD.status = 'posted'
BEGIN
  SELECT RAISE(ABORT, 'LED-2/delete: posted entries cannot be deleted');
END;

-- Posting checks: runs only on draft -> posted. Each SELECT RAISE is one check.
CREATE TRIGGER entries_post_checks
BEFORE UPDATE OF status ON entries
WHEN OLD.status = 'draft' AND NEW.status = 'posted'
BEGIN
  -- LED-1: at least one debit line, at least one credit line, and total debits equal total credits.
  SELECT RAISE(ABORT, 'LED-1: posted entry needs a debit and a credit line and must balance')
  WHERE (SELECT COUNT(*) FROM entry_lines WHERE entry_id = NEW.id AND debit_minor > 0) = 0
     OR (SELECT COUNT(*) FROM entry_lines WHERE entry_id = NEW.id AND credit_minor > 0) = 0
     OR (SELECT SUM(debit_minor) FROM entry_lines WHERE entry_id = NEW.id)
        IS NOT (SELECT SUM(credit_minor) FROM entry_lines WHERE entry_id = NEW.id);

  -- LED-4: no posting into a closed period or fiscal year.
  SELECT RAISE(ABORT, 'LED-4/closed: period or fiscal year is closed')
  WHERE (SELECT status FROM periods WHERE id = NEW.period_id) <> 'open'
     OR (SELECT status FROM fiscal_years WHERE id = NEW.fiscal_year_id) <> 'open';

  -- LED-5: no posting to a deactivated account.
  SELECT RAISE(ABORT, 'LED-5/inactive: a line uses a deactivated account')
  WHERE EXISTS (SELECT 1 FROM entry_lines l JOIN accounts a ON a.id = l.account_id
                WHERE l.entry_id = NEW.id AND a.is_active = 0);

  -- LED-3: the number must be the next gapless number of its journal and fiscal year.
  SELECT RAISE(ABORT, 'LED-3: entry number is not the next gapless number')
  WHERE NEW.entry_number IS NOT (SELECT last_number + 1 FROM number_sequences
                                 WHERE journal_id = NEW.journal_id AND fiscal_year_id = NEW.fiscal_year_id);

  -- LED-10: the chain position must be the next posting sequence value.
  SELECT RAISE(ABORT, 'LED-10: posting sequence is not the next chain position')
  WHERE NEW.posting_seq IS NOT (SELECT COALESCE(MAX(posting_seq), 0) + 1 FROM entries);

  -- A reversal must reference a posted entry (LED-2).
  SELECT RAISE(ABORT, 'LED-2/reversal: a reversal must reference a posted entry')
  WHERE NEW.reverses_entry_id IS NOT NULL
    AND (SELECT status FROM entries WHERE id = NEW.reverses_entry_id) IS NOT 'posted';
END;

-- Advances the counter only after the posted row exists; number_sequences' own trigger checks it.
CREATE TRIGGER entries_number_advance
AFTER UPDATE OF status ON entries
WHEN OLD.status = 'draft' AND NEW.status = 'posted'
BEGIN
  UPDATE number_sequences
     SET last_number = NEW.entry_number
   WHERE journal_id = NEW.journal_id AND fiscal_year_id = NEW.fiscal_year_id;
END;

-- LED-3: one counter per journal and fiscal year. Application code inserts the row with
-- INSERT OR IGNORE (last_number = 0) inside the posting transaction before the first posting.
CREATE TABLE number_sequences (
  journal_id     INTEGER NOT NULL REFERENCES journals(id),
  fiscal_year_id INTEGER NOT NULL REFERENCES fiscal_years(id),
  last_number    INTEGER NOT NULL DEFAULT 0 CHECK (last_number >= 0),
  PRIMARY KEY (journal_id, fiscal_year_id)
) STRICT;

-- The counter moves only by exactly one, and only to a number that a posted entry already holds.
-- Together with the posting checks this makes a gap or a manual jump impossible through SQL.
CREATE TRIGGER number_sequences_advance_only_with_posted_entry
BEFORE UPDATE ON number_sequences
BEGIN
  SELECT RAISE(ABORT, 'LED-3: counter may only advance to the number of a posted entry')
  WHERE NEW.last_number IS NOT OLD.last_number + 1
     OR NOT EXISTS (SELECT 1 FROM entries e
                    WHERE e.journal_id = NEW.journal_id
                      AND e.fiscal_year_id = NEW.fiscal_year_id
                      AND e.entry_number = NEW.last_number
                      AND e.status = 'posted');
END;

CREATE TRIGGER number_sequences_no_delete
BEFORE DELETE ON number_sequences
BEGIN
  SELECT RAISE(ABORT, 'LED-3: numbering counters cannot be deleted');
END;

CREATE TABLE entry_lines (
  id           INTEGER PRIMARY KEY,
  entry_id     INTEGER NOT NULL REFERENCES entries(id),
  line_no      INTEGER NOT NULL CHECK (line_no >= 1),
  account_id   INTEGER NOT NULL REFERENCES accounts(id),
  -- Exactly one side is non-zero. Upper bound 10^15 - 1 minor units keeps every SUM below 2^53,
  -- the largest integer a JavaScript number holds exactly. Property tests check the bound.
  debit_minor  INTEGER NOT NULL DEFAULT 0 CHECK (debit_minor BETWEEN 0 AND 999999999999999),
  credit_minor INTEGER NOT NULL DEFAULT 0 CHECK (credit_minor BETWEEN 0 AND 999999999999999),
  description  TEXT CHECK (description IS NULL OR length(description) <= 500),
  CHECK ((debit_minor = 0) <> (credit_minor = 0)),
  UNIQUE (entry_id, line_no)
) STRICT;

-- Covering indexes for the balance and ledger queries (NFR-1). Plans are checked in CI (ADR 9).
CREATE INDEX entry_lines_by_entry ON entry_lines (entry_id, account_id, debit_minor, credit_minor);
CREATE INDEX entry_lines_by_account ON entry_lines (account_id, entry_id, debit_minor, credit_minor);

-- LED-2: lines of a posted entry are immutable (insert, update and delete).
CREATE TRIGGER entry_lines_posted_insert
BEFORE INSERT ON entry_lines
WHEN (SELECT status FROM entries WHERE id = NEW.entry_id) = 'posted'
BEGIN
  SELECT RAISE(ABORT, 'LED-2/insert: lines of a posted entry cannot be added');
END;

CREATE TRIGGER entry_lines_posted_update
BEFORE UPDATE ON entry_lines
WHEN (SELECT status FROM entries WHERE id = OLD.entry_id) = 'posted'
BEGIN
  SELECT RAISE(ABORT, 'LED-2/update: lines of a posted entry are immutable');
END;

CREATE TRIGGER entry_lines_posted_delete
BEFORE DELETE ON entry_lines
WHEN (SELECT status FROM entries WHERE id = OLD.entry_id) = 'posted'
BEGIN
  SELECT RAISE(ABORT, 'LED-2/delete: lines of a posted entry cannot be deleted');
END;

-- =============================================================================
-- Audit log (LED-6). Append-only. Times are UTC instants.
-- =============================================================================

CREATE TABLE audit_log (
  id             INTEGER PRIMARY KEY,
  occurred_at_utc TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  table_name     TEXT NOT NULL CHECK (table_name IN
                   ('entities', 'accounts', 'account_roles', 'journals', 'fiscal_years', 'periods')),
  row_key        TEXT NOT NULL,
  action         TEXT NOT NULL CHECK (action IN ('insert', 'update', 'delete')),
  old_value      TEXT CHECK (old_value IS NULL OR json_valid(old_value)),
  new_value      TEXT CHECK (new_value IS NULL OR json_valid(new_value))
) STRICT;

CREATE TRIGGER audit_log_no_update
BEFORE UPDATE ON audit_log
BEGIN
  SELECT RAISE(ABORT, 'LED-6: the audit log is append-only');
END;

CREATE TRIGGER audit_log_no_delete
BEFORE DELETE ON audit_log
BEGIN
  SELECT RAISE(ABORT, 'LED-6: the audit log is append-only');
END;

CREATE TRIGGER entities_audit_insert AFTER INSERT ON entities
BEGIN
  INSERT INTO audit_log (table_name, row_key, action, new_value)
  VALUES ('entities', CAST(NEW.id AS TEXT), 'insert',
          json_object('legal_name', NEW.legal_name, 'business_id', NEW.business_id, 'currency_code', NEW.currency_code));
END;

CREATE TRIGGER entities_audit_update AFTER UPDATE ON entities
BEGIN
  INSERT INTO audit_log (table_name, row_key, action, old_value, new_value)
  VALUES ('entities', CAST(NEW.id AS TEXT), 'update',
          json_object('legal_name', OLD.legal_name, 'business_id', OLD.business_id, 'currency_code', OLD.currency_code),
          json_object('legal_name', NEW.legal_name, 'business_id', NEW.business_id, 'currency_code', NEW.currency_code));
END;

CREATE TRIGGER accounts_audit_insert AFTER INSERT ON accounts
BEGIN
  INSERT INTO audit_log (table_name, row_key, action, new_value)
  VALUES ('accounts', CAST(NEW.id AS TEXT), 'insert',
          json_object('number', NEW.number, 'name', NEW.name, 'account_type', NEW.account_type,
                      'parent_id', NEW.parent_id, 'is_active', NEW.is_active));
END;

CREATE TRIGGER accounts_audit_update AFTER UPDATE ON accounts
BEGIN
  INSERT INTO audit_log (table_name, row_key, action, old_value, new_value)
  VALUES ('accounts', CAST(NEW.id AS TEXT), 'update',
          json_object('number', OLD.number, 'name', OLD.name, 'account_type', OLD.account_type,
                      'parent_id', OLD.parent_id, 'is_active', OLD.is_active),
          json_object('number', NEW.number, 'name', NEW.name, 'account_type', NEW.account_type,
                      'parent_id', NEW.parent_id, 'is_active', NEW.is_active));
END;

CREATE TRIGGER accounts_audit_delete AFTER DELETE ON accounts
BEGIN
  INSERT INTO audit_log (table_name, row_key, action, old_value)
  VALUES ('accounts', CAST(OLD.id AS TEXT), 'delete',
          json_object('number', OLD.number, 'name', OLD.name, 'account_type', OLD.account_type,
                      'parent_id', OLD.parent_id, 'is_active', OLD.is_active));
END;

CREATE TRIGGER account_roles_audit_insert AFTER INSERT ON account_roles
BEGIN
  INSERT INTO audit_log (table_name, row_key, action, new_value)
  VALUES ('account_roles', NEW.role, 'insert', json_object('account_id', NEW.account_id));
END;

CREATE TRIGGER account_roles_audit_update AFTER UPDATE ON account_roles
BEGIN
  INSERT INTO audit_log (table_name, row_key, action, old_value, new_value)
  VALUES ('account_roles', NEW.role, 'update',
          json_object('account_id', OLD.account_id), json_object('account_id', NEW.account_id));
END;

CREATE TRIGGER account_roles_audit_delete AFTER DELETE ON account_roles
BEGIN
  INSERT INTO audit_log (table_name, row_key, action, old_value)
  VALUES ('account_roles', OLD.role, 'delete', json_object('account_id', OLD.account_id));
END;

CREATE TRIGGER journals_audit_insert AFTER INSERT ON journals
BEGIN
  INSERT INTO audit_log (table_name, row_key, action, new_value)
  VALUES ('journals', CAST(NEW.id AS TEXT), 'insert',
          json_object('code', NEW.code, 'name', NEW.name, 'is_active', NEW.is_active));
END;

CREATE TRIGGER journals_audit_update AFTER UPDATE ON journals
BEGIN
  INSERT INTO audit_log (table_name, row_key, action, old_value, new_value)
  VALUES ('journals', CAST(NEW.id AS TEXT), 'update',
          json_object('code', OLD.code, 'name', OLD.name, 'is_active', OLD.is_active),
          json_object('code', NEW.code, 'name', NEW.name, 'is_active', NEW.is_active));
END;

CREATE TRIGGER fiscal_years_audit_insert AFTER INSERT ON fiscal_years
BEGIN
  INSERT INTO audit_log (table_name, row_key, action, new_value)
  VALUES ('fiscal_years', CAST(NEW.id AS TEXT), 'insert',
          json_object('start_date', NEW.start_date, 'end_date', NEW.end_date, 'status', NEW.status));
END;

CREATE TRIGGER fiscal_years_audit_update AFTER UPDATE OF status ON fiscal_years
BEGIN
  INSERT INTO audit_log (table_name, row_key, action, old_value, new_value)
  VALUES ('fiscal_years', CAST(NEW.id AS TEXT), 'update',
          json_object('status', OLD.status), json_object('status', NEW.status));
END;

CREATE TRIGGER periods_audit_insert AFTER INSERT ON periods
BEGIN
  INSERT INTO audit_log (table_name, row_key, action, new_value)
  VALUES ('periods', CAST(NEW.id AS TEXT), 'insert',
          json_object('start_date', NEW.start_date, 'end_date', NEW.end_date, 'status', NEW.status));
END;

CREATE TRIGGER periods_audit_update AFTER UPDATE OF status ON periods
BEGIN
  INSERT INTO audit_log (table_name, row_key, action, old_value, new_value)
  VALUES ('periods', CAST(NEW.id AS TEXT), 'update',
          json_object('status', OLD.status), json_object('status', NEW.status));
END;

-- =============================================================================
-- Requirement map. Each row names the enforcement and the planned test (test IDs are created in Phase 1).
-- =============================================================================
--
-- | Req | Enforcement in this file | Planned test |
-- | --- | --- | --- |
-- | COA-1 Chart from template, extensible | accounts table; account_role_codes seeded | Golden: template loads; property: insert under any parent |
-- | COA-2 Roles redirect postings | account_roles PK(role) -> account_id; roles are the only link logic uses | Test: reassign role, next posting uses new account, posted lines unchanged |
-- | LED-1 Balanced entries | trigger entries_post_checks (LED-1 check); line CHECK one side non-zero | Property (fast-check): random entries, unbalanced always rejected |
-- | LED-2 Immutability | triggers entries_posted_immutable_update/delete, entry_lines_posted_*, entries_insert_as_draft; reversal link UNIQUE reverses_entry_id, reversal must reference posted | Property: any UPDATE/DELETE on posted rejected; reversal round-trip |
-- | LED-3 Gapless numbering | UNIQUE(journal, fy, entry_number); posting check vs number_sequences; number_sequences_advance_only_with_posted_entry; CHECK status-number coupling | Property: random post/reverse sequences leave no gaps; gap query in queries.sql |
-- | LED-4 Closed periods | posting check on periods/fiscal_years status; no reopen triggers; fixed dates; containment and overlap triggers | Test: posting into closed period/year rejected; reopen rejected |
-- | LED-5 Account lifecycle | FK NO ACTION blocks delete of used account; accounts_type_locked_after_postings; posting check is_active | Test: delete and retype rejected; deactivated account rejects posting |
-- | LED-6 Master-data audit | audit_log append-only triggers; *_audit_* triggers on entities, accounts, account_roles, journals, fiscal_years, periods | Test: each master-data change yields one audit row with old and new values |
-- | LED-7 Exact amounts | INTEGER minor units; CHECK range; currencies exponent; entities_currency_locked | Property: no drift; bound test near 10^15 |
-- | LED-8 Calendar dates | date(x) IS x CHECKs; entries_date_in_period_* triggers; no timestamps in accounting columns | Test: date outside period rejected; invalid dates rejected; zone change does not move entry |
-- | LED-9 Historical rates | Not in migration-001 (VAT Phase 4) | Phase 4 |
-- | LED-10 Tamper evidence | posting_seq UNIQUE and posting check; content_hash and chain_hash CHECKs and posting coupling; hashing in TS (ADR 6) | Test: chain verifies; edited row detected; recomputed chain differs from printed head |
-- | LED-11 Drafts | status draft; drafts have no number or hash (CHECK); partial index on posted | Test: drafts excluded from trial balance and general ledger |
-- | LED-12 Opening balances | opening entries are ordinary entries in a dedicated journal; posting checks (LED-1, LED-8) apply to them | Test: imported opening balances balance and appear in period one |
-- | LED-13 Several journals | journals table; numbering per journal (UNIQUE and counter scope) | Test: each journal numbers independently |
-- | DAT-6 Schema version | Not in this file; set by the runner in a schema-version table in a later migration | Phase 2 migration tests |
-- | SEC-5/SEC-6 no network, no telemetry | Not a DDL concern; no network-related tables | Phase 0 end-to-end request assertion |
