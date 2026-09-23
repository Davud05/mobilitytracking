# Where reporting should execute

Daily captured revenue is derived from `payments`. The four read paths are:

| Approach | Object | Stored? |
| --- | --- | --- |
| Direct query | `database/postgres/queries/base_revenue.sql` | No |
| Function | `captured_revenue_for_day(operator, date)` | No |
| Materialized view | `daily_captured_revenue` | Yes, until the next refresh |
| Trigger summary | `daily_revenue_by_operator` | Yes, maintained only on insert |

The full grid is `docs/evidence/reporting.txt`. Null amounts in that file mean the approach returned no rows. An unpopulated materialized view is not an empty result: reading it raises SQLSTATE `55000` until `REFRESH MATERIALIZED VIEW`.

The experiment ran on the permissive starter schema, before migration `011`. The duplicate external reference can be stored in that schema. After `011` the same insert fails with `payments_external_reference_unique` and SQLSTATE `23505`.

## What each case did

Seed before any case: `PAYMENT-1` is 36 DKK captured for City Metro, `PAYMENT-2` is 36 DKK captured for City Bus, both on `2026-04-29`.

| Step | Write | Base and function | Trigger summary | Materialized view |
| --- | --- | --- | --- | --- |
| 01 baseline | none | Metro 36 / 1, Bus 36 / 1 | no rows | not populated |
| 02 captured insert | `PAY-CASE-CAPTURED`, 36, Captured | Metro 72 / 2, Bus 36 / 1 | Metro 36 / 1 | not populated |
| 03 failed insert | `PAY-CASE-FAILED`, 50, Failed | unchanged | unchanged | not populated |
| 04 Failed → Captured | status update | Metro 122 / 3, Bus 36 / 1 | still Metro 36 / 1 | not populated |
| 05 Captured → Refunded | `PAY-CASE-CAPTURED` refunded | Metro 86 / 2, Bus 36 / 1 | still Metro 36 / 1 | not populated |
| 06 delete | delete `PAY-CASE-FAILED` | Metro 36 / 1, Bus 36 / 1 | still Metro 36 / 1 | not populated |
| 07 duplicate delivery | second row with `gateway-capture-0001` | Metro 72 / 2, Bus 36 / 1 | Metro 72 / 2 | not populated |
| 08 refresh | `REFRESH MATERIALIZED VIEW` | Metro 72 / 2, Bus 36 / 1 | Metro 72 / 2, still no Bus row | Metro 72 / 2, Bus 36 / 1 |

The direct query and the function return the same numbers at every step. They read `payments` with `status = 'Captured'`.

## Where two approaches disagree

Step 04 is the clear case. The base query and the function say City Metro captured 122.00 across 3 payments. The trigger table still says 36 across 1 payment. The materialized view cannot be queried yet.

The 50 DKK row was inserted as `Failed`, so the insert trigger ignored it. The later update to `Captured` is invisible to an `AFTER INSERT` trigger. Revenue is understated, and nothing in the payment write tells the application that the summary is wrong.

Step 08 looks closer and is still wrong. After refresh, the materialized view matches the base query, including City Bus. The trigger total for Metro is also 72, but the composition is different:

| Row | Status after the run | In the base total | In the trigger total |
| --- | --- | --- | --- |
| `PAYMENT-1` (seed, Metro, 36) | Captured | yes | no, inserted before the trigger existed |
| `PAYMENT-2` (seed, Bus, 36) | Captured | yes | no |
| `PAY-CASE-CAPTURED` (36) | Refunded | no | yes, added on insert and never removed |
| `PAY-CASE-DUPLICATE` (36) | Captured | yes | yes |

Metro's 72 in the trigger is the refunded payment plus the duplicate. Metro's 72 in the base query is the original seed payment plus the duplicate. Same number, different payments. The trigger also has no City Bus row at all.

## Side-effect trace for one captured insert

Write: `INSERT` of `PAY-CASE-CAPTURED` (step 02), 36 DKK, status `Captured`, ticket `TICKET-1`.

1. Constraints checked on the permissive schema: primary key of `payments`. Foreign keys and the status check are not present yet. This is why the duplicate in step 07 is accepted.
2. `payments_daily_revenue_after_insert` runs after the row is inserted, because `NEW.status` is `Captured`.
3. The trigger function joins `tickets` → `trips` → `routes` and finds `OP-METRO`.
4. It inserts `(OP-METRO, 2026-04-29, 36, 1)` into `daily_revenue_by_operator`. A later captured insert on the same day takes the `ON CONFLICT` branch and adds to that row.
5. The summary write is in the same transaction as the payment. If the trigger raises, the payment insert rolls back with it. A reporting defect can therefore reject a sale.
6. At commit, the base query and the function both show Metro 72. The trigger shows only the 36 it just wrote, because the seed payment was never backfilled. The materialized view is still unpopulated, so a report that reads it fails instead of showing a stale zero.
7. The application observes one new payment row. It does not observe the summary unless it queries `daily_revenue_by_operator`.

## Responsibility matrix

| | Direct query | Function | Materialized view | Insert trigger |
| --- | --- | --- | --- | --- |
| Correctness | Matches `payments` | Same query, one operator and date | Matches `payments` only after refresh | Wrong after update, refund, delete, and for rows that existed before the trigger |
| Freshness | This transaction | This transaction | Whenever someone runs `REFRESH` | Immediate for a new `Captured` insert only |
| Write cost | None | None | None on the payment path. Refresh scans `payments`. | Extra lookup and upsert on every insert, inside the payment transaction |
| Read cost | Aggregate on each report | Same aggregate | One indexed lookup | One primary-key lookup |
| Hidden side effects | None | None | A reader can hit `55000` or a stale copy without a write failing | A second table changes, and a trigger error aborts the sale |
| Rebuild | Not stored | Not stored | `REFRESH MATERIALIZED VIEW daily_captured_revenue` | `database/postgres/queries/rebuild_daily_revenue.sql` deletes and reloads from `payments` |
| Operational complexity | Lowest | Low: one definition for callers | Someone must own the refresh schedule and notice staleness | Highest: backfill, corrections, refunds, deletes, and duplicate delivery all have to be designed |

Authority for every stored copy is `payments`. The summary table and the materialized view are caches. If they disagree with a query on `payments` where `status = 'Captured'`, the cache is wrong.

## Issue

- Evidence: step 04 in `docs/evidence/reporting.txt`. Base and function show Metro `122.00` / `3`. The trigger shows Metro `36` / `1`.
- Problem: `add_inserted_payment_to_daily_revenue` returns without writing when the inserted status is not `Captured`, and it has no `UPDATE` or `DELETE` trigger.
- Consequence: a failed payment that later captures, or a captured payment that is refunded, changes operator revenue in the source and leaves the published total behind.
- Specific improvement: do not publish `daily_revenue_by_operator` for this case. Read `captured_revenue_for_day`. Keep the rebuild script as the recovery path if a summary is introduced later, and make that rebuild the only writer.
- Open question: is "daily" a figure operators need during the day, or a closed figure after capture corrections have landed? The answer decides whether a refreshed materialized view is worth operating.

## Decision

Use the function. `payments` stays the only authority.

The current workload includes failed payments, corrections to `Captured`, refunds, deletes, and duplicate gateway deliveries. An insert-only trigger handles one of those six events. The direct query is the right definition, and the function is that definition with a name, so application code does not copy the joins. It is current in the same transaction, it has no second copy to rebuild, and a bug in the function cannot roll back a sale unless the application calls it in that transaction and then writes.

The materialized view is acceptable later, as a cache, if a report is too heavy to aggregate on demand. It already has the unique index required for `REFRESH MATERIALIZED VIEW CONCURRENTLY`. It is not current until refresh, and an unpopulated view errors rather than returning zero. `payments` would still be the authority, and the refresh would be the rebuild path.

The trigger-maintained table is the wrong owner for this case. It couples reporting to payment insert, misses the corrections the lab actually contains, and can show a total that matches the source by accident while describing different payments. Duplicate delivery is also not a reporting problem. Migration `011` rejects the second `gateway-capture-0001` before any of the four approaches see it.

This does not decide ticket-purchase concurrency or how a gateway capture is coordinated with the local payment row. Those stay open for later lectures.
