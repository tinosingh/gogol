-- queries.sql: reporting queries over migration-001.sql (RPT-1, RPT-2, RPT-4, VAT-2 stub).
--
-- Rules every query follows
--   * Balances come only from posted lines: e.status = 'posted' is written literally so the partial index
--     entries_posted_by_period is eligible (drafts never appear, LED-11).
--   * Parameters are bound with named parameters (:name). Application code binds them; nothing is concatenated.
--   * Money is INTEGER minor units. Net = debit - credit, so assets come out positive and liability/equity
--     presentation flips the sign in the report, not in the data.
--   * Accounts are reached through roles (account_roles, COA-2); account numbers are display text only.
--   * CI runs EXPLAIN QUERY PLAN on each query below and fails on a full scan of entry_lines or entries (ADR 9).
--
-- Named parameters
--   :period_id     periods.id                         (activity of one period)
--   :fiscal_year_id fiscal_years.id                    (cumulative reports)
--   :period_end    periods.end_date of the last period in scope, 'YYYY-MM-DD'
--   :account_id    accounts.id
--   :layout        report layout code, e.g. the Phase 3 layout key (report_line_map.layout)

-- -----------------------------------------------------------------------------
-- 1. Trial balance (RPT-1)
--    Activity of one period. For a cumulative trial balance (opening balances included),
--    replace the period filter with the fiscal-year range shown in the comment below.
-- -----------------------------------------------------------------------------
WITH in_scope_periods AS (
  -- Activity of one period:
  SELECT id FROM periods WHERE id = :period_id
  -- Cumulative to period end (uncomment instead, and drop the line above):
  -- SELECT id FROM periods WHERE fiscal_year_id = :fiscal_year_id AND end_date <= :period_end
),
activity AS (
  SELECT l.account_id,
         SUM(l.debit_minor)  AS debit_minor,
         SUM(l.credit_minor) AS credit_minor
    FROM entries e
    JOIN entry_lines l ON l.entry_id = e.id
   WHERE e.status = 'posted'
     AND e.period_id IN (SELECT id FROM in_scope_periods)
   GROUP BY l.account_id
)
SELECT a.id                                   AS account_id,
       a.number,
       a.name,
       a.account_type,
       COALESCE(t.debit_minor, 0)             AS debit_minor,
       COALESCE(t.credit_minor, 0)            AS credit_minor,
       COALESCE(t.debit_minor, 0)
         - COALESCE(t.credit_minor, 0)        AS net_minor
  FROM accounts a
  JOIN activity t ON t.account_id = a.id       -- accounts with postings only; zero rows are omitted
 ORDER BY a.number;

-- Self-check: the trial balance nets to zero (LED-1 consequence). Must return 0.
WITH in_scope_periods AS (
  SELECT id FROM periods WHERE id = :period_id
)
SELECT COALESCE(SUM(l.debit_minor), 0) - COALESCE(SUM(l.credit_minor), 0) AS must_be_zero
  FROM entries e
  JOIN entry_lines l ON l.entry_id = e.id
 WHERE e.status = 'posted'
   AND e.period_id IN (SELECT id FROM in_scope_periods);

-- -----------------------------------------------------------------------------
-- 2. General ledger for one account and period (RPT-2)
--    Every posted line of the account in the period, in order. Reversal links are shown in both directions
--    (LED-2): reverses_entry_id on the reversal, reversed_by_entry_id on the original.
-- -----------------------------------------------------------------------------
SELECT e.id                   AS entry_id,
       e.journal_id,
       e.entry_number,
       e.accounting_date,
       l.line_no,
       e.description,
       l.debit_minor,
       l.credit_minor,
       e.reverses_entry_id,
       (SELECT r.id FROM entries r WHERE r.reverses_entry_id = e.id) AS reversed_by_entry_id
  FROM entries e
  JOIN entry_lines l ON l.entry_id = e.id
 WHERE e.status = 'posted'
   AND e.period_id = :period_id
   AND l.account_id = :account_id
 ORDER BY e.accounting_date, e.journal_id, e.entry_number, l.line_no;

-- -----------------------------------------------------------------------------
-- 3. Balance sheet (RPT-4, Phase 3)
--    Cumulative to period end. Mapping: account -> account_roles (one role per account, UNIQUE) ->
--    report_line_map (layout, role) -> line_code. Accounts without a role fall into an 'unmapped_<type>' line,
--    so totals still reconcile while a layout is incomplete. The result of the period is shown as its own
--    equity line from the revenue and expense accounts, because closing entries (YE-1) come later.
-- -----------------------------------------------------------------------------
WITH bal AS (
  SELECT l.account_id,
         SUM(l.debit_minor) - SUM(l.credit_minor) AS net_minor
    FROM entries e
    JOIN entry_lines l ON l.entry_id = e.id
   WHERE e.status = 'posted'
     AND e.period_id IN (SELECT id FROM periods
                          WHERE fiscal_year_id = :fiscal_year_id AND end_date <= :period_end)
   GROUP BY l.account_id
),
balance_sheet_lines AS (
  SELECT CASE WHEN a.account_type = 'asset' THEN 'assets' ELSE 'liabilities_and_equity' END AS side,
         COALESCE(m.line_code, 'unmapped_' || a.account_type)                                  AS report_line,
         CASE WHEN a.account_type = 'asset' THEN b.net_minor ELSE -b.net_minor END           AS amount_minor
    FROM bal b
    JOIN accounts a          ON a.id = b.account_id
    LEFT JOIN account_roles r ON r.account_id = a.id
    LEFT JOIN report_line_map m ON m.role = r.role AND m.layout = :layout
   WHERE a.account_type IN ('asset', 'liability', 'equity')
),
result_line AS (
  SELECT 'liabilities_and_equity' AS side,
         'result_for_period'      AS report_line,
         -SUM(b.net_minor)        AS amount_minor            -- revenue is credit-normal, so the sign flips
    FROM bal b
    JOIN accounts a ON a.id = b.account_id
   WHERE a.account_type IN ('revenue', 'expense')
)
SELECT side, report_line, SUM(amount_minor) AS amount_minor
  FROM (SELECT * FROM balance_sheet_lines UNION ALL SELECT * FROM result_line)
 GROUP BY side, report_line
 ORDER BY side, report_line;

-- Self-check: assets must equal liabilities_and_equity. Must return 0.
WITH bal AS (
  SELECT l.account_id, SUM(l.debit_minor) - SUM(l.credit_minor) AS net_minor
    FROM entries e JOIN entry_lines l ON l.entry_id = e.id
   WHERE e.status = 'posted'
     AND e.period_id IN (SELECT id FROM periods
                          WHERE fiscal_year_id = :fiscal_year_id AND end_date <= :period_end)
   GROUP BY l.account_id
)
SELECT COALESCE(SUM(CASE WHEN a.account_type = 'asset' THEN b.net_minor END), 0)
     + COALESCE(SUM(CASE WHEN a.account_type IN ('liability', 'equity', 'revenue', 'expense') THEN b.net_minor END), 0)
       AS must_be_zero
  FROM bal b JOIN accounts a ON a.id = b.account_id;

-- -----------------------------------------------------------------------------
-- 4. Profit and loss (RPT-4, Phase 3)
--    Revenue and expense accounts summed by report line, cumulative to period end.
--    Revenue is shown positive; expense stays positive as a cost.
-- -----------------------------------------------------------------------------
WITH bal AS (
  SELECT l.account_id,
         SUM(l.debit_minor) - SUM(l.credit_minor) AS net_minor
    FROM entries e
    JOIN entry_lines l ON l.entry_id = e.id
   WHERE e.status = 'posted'
     AND e.period_id IN (SELECT id FROM periods
                          WHERE fiscal_year_id = :fiscal_year_id AND end_date <= :period_end)
   GROUP BY l.account_id
)
SELECT a.account_type,
       COALESCE(m.line_code, 'unmapped_' || a.account_type) AS report_line,
       SUM(CASE WHEN a.account_type = 'revenue' THEN -b.net_minor ELSE b.net_minor END) AS amount_minor
  FROM bal b
  JOIN accounts a           ON a.id = b.account_id
  LEFT JOIN account_roles r ON r.account_id = a.id
  LEFT JOIN report_line_map m ON m.role = r.role AND m.layout = :layout
 WHERE a.account_type IN ('revenue', 'expense')
 GROUP BY a.account_type, report_line
 ORDER BY a.account_type, report_line;

-- -----------------------------------------------------------------------------
-- 5. VAT summary (VAT-2): STUB, Phase 4
--    No VAT tables exist in migration-001. The planned approach:
--      * each posted line stores its VAT code and the rate snapshot it used (LED-9), so later rate changes
--        cannot alter history;
--      * the summary groups posted lines by VAT code and report box per period, and sums base and tax;
--      * box mapping comes from report_line_map with layout = 'vat_return' (same mechanism as the statements),
--        so no box number is hard-coded in SQL.
--    Placeholder below: the net of the accounts holding the VAT roles for the period, so the figure can be
--    reconciled against the trial balance until the real query exists.
-- -----------------------------------------------------------------------------
SELECT r.role,
       a.id AS account_id,
       SUM(l.debit_minor) - SUM(l.credit_minor) AS net_minor
  FROM account_roles r
  JOIN accounts a     ON a.id = r.account_id
  JOIN entry_lines l  ON l.account_id = a.id
  JOIN entries e      ON e.id = l.entry_id
 WHERE r.role IN ('vat_receivable', 'vat_payable')
   AND e.status = 'posted'
   AND e.period_id = :period_id
 GROUP BY r.role, a.id;

-- -----------------------------------------------------------------------------
-- 6. Integrity checks (LED-3, LED-10): run on open per the quick_check schedule (ADR 6) and in tests.
-- -----------------------------------------------------------------------------

-- Gapless numbering: for each journal and fiscal year, the count of posted entries equals the highest number
-- and the counter. Returns rows only for broken scopes; expect zero rows.
SELECT s.journal_id, s.fiscal_year_id, s.last_number,
       COUNT(e.id) AS posted_count, MAX(e.entry_number) AS max_number
  FROM number_sequences s
  LEFT JOIN entries e ON e.journal_id = s.journal_id AND e.fiscal_year_id = s.fiscal_year_id
                     AND e.status = 'posted'
 GROUP BY s.journal_id, s.fiscal_year_id, s.last_number
HAVING COUNT(e.id) <> s.last_number OR COALESCE(MAX(e.entry_number), 0) <> s.last_number;

-- Chain positions: posted entries must hold exactly 1..n. Expect a single row with ok = 1.
SELECT COUNT(*) = COALESCE(MAX(posting_seq), 0) AS ok
  FROM entries
 WHERE status = 'posted';
