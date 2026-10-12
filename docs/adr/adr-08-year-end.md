# ADR 8: Year-end and opening balances

- **Status:** Proposed. Implementation is Phase 6 (YE-1) and Phase 1 (LED-12, opening balances). The design is fixed now so the schema in migration-001 supports it.
- **Requirements:** YE-1, LED-12, LED-4, LED-13, LED-1, RPT-1, LED-6.
- **Related:** [ADR 7](adr-07-currency.md), [ADR 9](adr-09-performance.md).

## Context

- **Year-end (YE-1):** closing entries, transfer of the result to equity, and carry-forward of balance-sheet accounts. The new year's opening trial balance must equal the closing balance sheet.
- **Opening balances (LED-12):** entered or imported when an entity starts or moves from other software. Imported balances must balance and appear in the first period's trial balance.

The PRD fixes the outcome, not the mechanics. Mechanics are decided here.

## Options considered

**Closing entries**

| Option | Notes |
| --- | --- |
| A. Closing entries are ordinary posted entries in a closing journal, in the last period of the year | **Chosen.** Reuses LED-1 to LED-3, the audit trail, the chain and the reports. No special-case storage. |
| B. Computed closing: reports subtract the result, nothing is posted | Rejected. The books would not show the transfer, and the accountant's closing would be missing from the chain. |
| C. Closing via a stored table of year-end balances | Rejected: a second copy of balances (invariant 3). |

**Opening balances**

| Option | Notes |
| --- | --- |
| A. Opening entry in the first period of the new year, in an opening journal, one line per balance-sheet account | **Chosen.** Ordinary entry, so LED-1 checks it and it is numbered and chained. |
| B. A `balance` column on `accounts` | Rejected: a second source of balances. |
| C. Import without an entry | Rejected: breaks LED-1 and the chain. |

**Carry-forward of result:** the result goes to `retained_earnings` in the closing entries. Whether a separate `profit_or_loss_brought_forward` role is needed is an accounting decision for the Finnish chart template, flagged for an accountant (it is not invented here).

## Decision

1. **Closing sequence (fiscal year end), one wizard, each step a posted entry or a status change:**
   1. All periods of the year are open or closed as the user decides; no drafts remain in the year (drafts are never balances, LED-11). The wizard lists remaining drafts and blocks until none remain or the user deletes them.
   2. **Closing entries** (closing journal, last period): debit each revenue account and credit each expense account for its net, and move the net to `result_for_period`. Then move `result_for_period` to `retained_earnings`. Each step is a posted entry, numbered per LED-3, with LED-1 checking the balance.
   3. **Close the fiscal year** (`fiscal_years.status = 'closed'`, one-way, LED-4). Its periods close too.
2. **Carry-forward:** the new fiscal year is created (no overlap, LED-4 trigger). Its opening entry (opening journal, first period) has one line per balance-sheet account with a non-zero closing net, debit or credit as the net requires. The entry balances because, after closing, the balance-sheet accounts net to zero in total. The check is LED-1, not a special case.
3. **Opening balance import (LED-12):** the same opening entry, built from a user's entries or a file. The import is validated before posting: a non-balancing import is rejected with `BalanceViolation` and nothing is written (one unit of work, worker-protocol.ts).
4. **Role use:** closing and opening lines use account roles (`result_for_period`, `retained_earnings`), never account numbers (COA-2).
5. **Acceptance test (YE-1):** a property test over random years: the new year's opening trial balance equals the closing balance sheet, account by account.
6. **Corrections after closing:** not in v1. A correction in a closed year needs a reversal in an open period, which the owner must approve as policy before Phase 6. Flagged in [prd-updates-stage1.md](../prd-updates-stage1.md).

## Consequences

- No special storage for year-end. Every balance remains derivable from journal lines (invariant 3), and the chain covers the closing and opening entries.
- The closing journal and opening journal are created by the wizard (LED-13). They are ordinary journals.
- The closing sequence depends on the period status rules in migration-001 (LED-4). A closed period cannot be posted into, so the closing order is enforced by the database.
- Whether the Finnish chart needs a separate brought-forward result account, and whether a closed year's result must stay fixed under the accounting rules, is for a qualified accountant to confirm. This ADR does not assert either.
