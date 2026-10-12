# ADR 7: Currency

- **Status:** Proposed. D6 is decided by the owner (2026-10-11): own currency only in v1.
- **Requirements:** D6, LED-7, LED-9, VAT-1, LED-1, LED-2.
- **Related:** [ADR 6](adr-06-tamper-evidence.md) (canonical form covers currency), [ADR 5](adr-05-migrations.md) (column additions).

## Context

Each entity has one functional currency, which is not always EUR (PROMPT.md). D6 decides that v1 carries no original-currency or exchange-rate columns. Ground truth from the owner's measurement (SQLite 3.54, Apple M2): adding three nullable columns to 300 000 posted rows took about 15 ms per column, changed no rows, and left the immutability triggers intact. Schema evolution does not need row migration.

## Decision for v1

1. **Functional currency per entity** lives in `entities.currency_code`, validated against `currencies` (ISO 4217 exponent as reference data, invariant 1). Migration-001 seeds EUR only. Other codes arrive as reference-data rows.
2. **Every amount is in the functional currency's minor units.** `entry_lines.debit_minor` and `credit_minor` are the only amount columns. LED-1 balance is checked on them, so a balanced entry is balanced in the functional currency.
3. **The functional currency cannot change after postings.** Trigger `entities_currency_locked` (prefix `LED-7`). Changing it would reinterpret every stored amount.
4. **The UI accepts only the functional currency.** Foreign-currency entry is not offered in v1 (PRD non-scope via D6).
5. **No FX code exists in v1.** No rate table, no rounding rule for conversion, no ECB lookup. Any network lookup stays out of v1 (PRD §5).

## Future extension path (for Phase 4 or later; not built now)

The additive design, to be proven in a spike before any FX feature is scheduled:

- **Nullable columns on `entry_lines`:** `orig_currency_code`, `orig_amount_minor`, `fx_rate_numerator`, `fx_rate_denominator`, `fx_rate_date`. All NULL for functional-currency lines.
- **Exact rates:** a rate is an integer numerator and denominator, the precision of its source (PROMPT.md invariant 1). No floating point, no `parseFloat`.
- **Functional amount stays authoritative.** `debit_minor` and `credit_minor` remain the values LED-1 balances on. The original amount is descriptive. An FX line is still a functional-currency balanced line.
- **Rounding:** the conversion rounding step comes from the jurisdiction module, explicitly, once per line (LED-7).
- **Reference data:** rates are versioned reference data with validity dates (LED-9), not code.
- **Migration:** `ALTER TABLE … ADD COLUMN` with nullable columns, no default rewrite, immutability triggers unchanged (measured). CHECK constraints on the new columns must be tested against existing rows in the spike, because a CHECK on an added column is validated on the table's rows.
- **Canonical form:** the ADR 6 serialization gets a new version tag (`gogol-entry-v2`) that includes the original-currency fields, so v1 entries keep their hashes.
- **VAT (LED-9):** VAT treatment is snapshotted per line in Phase 4 as its own columns. This is separate from the currency columns and is decided in the Phase 4 ADR.

## Options considered

| Option | Verdict |
| --- | --- |
| Original-currency and rate columns now | Rejected by D6 and YAGNI: no v1 feature uses them, and they widen every posting path. |
| Separate ledger per currency | Rejected: the entity's books are one ledger with one functional currency. Multiplies reports and reconciliation. |
| Additive columns later (chosen path) | Proven cheap by the owner's measurement. The functional amount stays the single balancing value. |

## Consequences

- v1 cannot record a foreign-currency invoice. The user records the functional-currency amount and notes the original in the description (a user workaround, documented in the UI copy).
- Changing the functional currency is blocked once anything is posted. An entity created in the wrong currency must start over, which the UI says before the first posting.
- The reference currency table needs one seeded row in v1 (EUR), so the schema has a FK target. Other codes are added without a migration.
- Accounting treatment of foreign-currency items under the Finnish rules is outside this ADR and needs an accountant's review before the FX feature.
