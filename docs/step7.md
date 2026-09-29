# Step 7: remove the old reference

Step 7 builds on the product-identity work already on `L-test`: `030_expand_product_identity.sql`, `031_backfill_ticket_product.sql`, and `033_require_ticket_product.sql`. The full run is in `docs/evidence/step7.txt`.

## Run order

Start from a clean database. Run every file from the repository root with:

```powershell
cmd /c "docker compose exec -T postgres psql -U mobility -d mobility -v ON_ERROR_STOP=1 < FILE"
```

1. `database/postgres/migrations/011_ticketing_integrity.sql`
2. `database/postgres/experiments/lecture04/baseline.sql`
3. `database/postgres/migrations/030_expand_product_identity.sql`
4. `database/postgres/experiments/lecture04/old_writer.sql`
5. `database/postgres/experiments/lecture04/new_writer.sql`
6. `database/postgres/migrations/031_backfill_ticket_product.sql`, twice
7. `database/postgres/experiments/lecture04/verify.sql`
8. `database/postgres/migrations/033_require_ticket_product.sql`
9. `database/postgres/experiments/lecture04/new_reader_product_id.sql`
10. `database/postgres/experiments/lecture04/dependency_check.sql`
11. `database/postgres/experiments/lecture04/view_blocks_drop.sql`, with `ON_ERROR_STOP=0`
12. `database/postgres/migrations/034_drop_ticket_product_code.sql`
13. `database/postgres/experiments/lecture04/new_writer_product_id.sql`
14. `database/postgres/experiments/lecture04/new_reader_product_id.sql`

## Step 4 writer

`new_writer.sql` takes a product ID and looks up that product's code, so the ticket stores both references for the same product. The agreed price is an input. The default test ticket `LAB04-NEW-ID-1` is `DAY` at 72.00 DKK while the catalogue says 80.00 DKK, so the stored price is visibly not copied from `products`.

Two cases are rejected by the writer, and neither ticket is stored:

- an unknown product ID, SQLSTATE `23503`;
- the `DAY` product ID with a supplied `SINGLE` code, SQLSTATE `22023`.

The database alone would accept the second case. `product_code` and `product_id` are two separate foreign keys, and neither checks that they name the same product. `verify.sql` is what catches such a row before `033`.

The writer is a function in `pg_temp`. It is removed when the session ends, so it does not appear in the step 7 dependency check. After `034`, the file fails, because it writes `product_code`.

## Reader and writer

`new_reader_product_id.sql` joins `products` only on `tickets.product_id`. It already returns every ticket before the drop, because `031` has filled `product_id` and `033` has made it required. The product code in its output comes from `products.code`.

`new_writer_product_id.sql` inserts a ticket without `product_code`. It looks the product up once, stores that product's id, and takes the agreed price and currency as inputs. An unknown product code inserts zero rows.

## Dependency check

`dependency_check.sql` looks in three places:

- `pg_depend`, for constraints, indexes, and views on the column;
- function source in `pg_proc`, because PostgreSQL does not record dependencies from function bodies;
- view and materialized-view definitions.

Before the drop it finds exactly two objects, both foreign keys from `011_ticketing_integrity.sql`:

- `tickets_product_fk`
- `tickets_product_currency_fk`

No function or view uses the column. The reporting objects in `020`–`022` join on `ticket_id`, not on `product_code`.

`view_blocks_drop.sql` creates a view on `product_code` inside a transaction. The check then lists the view as a third dependency, and the drop fails:

```text
ERROR:  cannot drop column product_code of table tickets because other objects depend on it
DETAIL:  view ticket_product_codes depends on column product_code of table tickets
```

The transaction is rolled back. This is the case `CASCADE` would have hidden by deleting the view.

## Drop

`034_drop_ticket_product_code.sql` drops the two foreign keys by name and then the column. It does not use `CASCADE`, so any dependency the check missed stops the migration. `if exists` on the constraints lets it run on a database where `011` was not applied.

After the drop:

- `tickets` has `product_id` and no `product_code`.
- `products.code` is still there, as the business code.
- The dependency check returns no rows.
- `TICKET-1` and `TICKET-2` are still `SINGLE` at 36.00 DKK, and `TICKET-3` is still `DAY` at 80.00 DKK.
- `LAB04-NEW-ID-1` from step 4 is still `DAY` at the agreed 72.00 DKK.
- The new writer adds `LAB04-NEW-1` as `DAY` at 80.00 DKK.
- `old_writer.sql` fails with `column "product_code" of relation "tickets" does not exist`.
- `old reader.sql` fails with `column "product_code" does not exist`.

The two failures are expected. The old interface is gone, and the rest of the application has to use `product_id`.
