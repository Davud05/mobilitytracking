# Step 8: what EF Core produces

The project does not use EF Core. Instead of asking for a hand-written draft, a minimal EF Core model of `products` and `tickets` was built in `tools/efcore-step8/`, and the real `dotnet ef` generated the migration:

- `tools/efcore-step8/stages/Before.cs.txt`: tickets reference `products.code` through `product_code`.
- `tools/efcore-step8/stages/After.cs.txt`: products have `id uuid default gen_random_uuid()` as a unique key, and tickets reference it through a required `product_id`.
- `tools/efcore-step8/out/TicketProductId.cs`: the generated migration.
- `tools/efcore-step8/out/ticket_product_id.sql`: `dotnet ef migrations script --idempotent` for that migration.

Regenerate from the repository root with:

```powershell
docker run --rm -v "${PWD}\tools\efcore-step8:/work" mcr.microsoft.com/dotnet/sdk:8.0 bash -c "tr -d '\r' < /work/generate.sh | bash"
```

`dotnet ef` printed `An operation was scaffolded that may result in the loss of data` when it created the migration.

## What the generated migration does

In one migration, in this order:

1. drop the foreign key `tickets_product_fk`;
2. drop the index `IX_tickets_product_code`;
3. drop `tickets.product_code`;
4. add `tickets.product_id uuid NOT NULL DEFAULT '00000000-0000-0000-0000-000000000000'`;
5. add `products.id uuid NOT NULL DEFAULT gen_random_uuid()`;
6. add the unique constraint `products_id_unique`;
7. create an index on `tickets.product_id`;
8. add `tickets_product_id_fk` with `ON DELETE CASCADE`.

## Running it against the seeded database

The run is in `docs/evidence/step8-efcore-run.txt`. The database was clean, with `011_ticketing_integrity.sql` applied and an empty `__EFMigrationsHistory` table.

The first attempt stopped at step 2:

```text
ERROR:  index "IX_tickets_product_code" does not exist
```

EF assumes the database was created by its own first migration. This database was not.

After creating that index, the second attempt got through steps 1 to 7 and stopped at step 8:

```text
ERROR:  insert or update on table "tickets" violates foreign key constraint "tickets_product_id_fk"
DETAIL:  Key (product_id)=(00000000-0000-0000-0000-000000000000) is not present in table "products".
```

By then `product_code` had already been dropped, and every ticket had the same zero id. The whole script ran in one transaction, so the failure rolled everything back. Afterwards `tickets` still had `product_code`, and no EF migration was recorded.

The failure depends on existing data. With an empty `tickets` table no row violates the foreign key, so the same migration succeeds on a fresh development database and fails in a database that has sold tickets.

## Comparison

| Question | EF Core | Our SQL |
| --- | --- | --- |
| When `product_id` becomes required | Immediately, in the same migration. Existing rows get the zero UUID as a default. | Nullable in `030`. Required in `033`, after `031` has filled it and `verify.sql` returns zero rows. |
| Creation of the foreign key | Validated at once, with `ON DELETE CASCADE`. | `NOT VALID` in `030`, so old rows are not checked yet. Validated in `033`. Default `NO ACTION`: a product with tickets cannot be deleted. |
| How existing rows are updated | They are not. No statement copies `product_code` to `product_id`. | `031` looks up each ticket's `product_code` in `products` and stores that product's id. Running it again changes zero rows. |
| Removal of `product_code` | Step 3, before anything has been copied. | `034`, the last change, after `033` and after `dependency_check.sql`. |
| Anything destructive | Dropping `product_code` destroys the only link from a ticket to its product. `ON DELETE CASCADE` would delete sold tickets together with their product. `Down()` adds `product_code` back as `''` for every ticket, so rolling back does not restore the old codes. | No step deletes data before it is copied. The drop does not use `CASCADE`, and a view on the column stops it, which `view_blocks_drop.sql` shows. |

## What the tool can work out, and what it cannot

EF Core got the parts that follow from the two models:

- the new columns, their types, and the default `gen_random_uuid()` for `products.id`. That default is what gave every existing product its own id;
- the unique key on `products.id`, and an index and foreign key on `tickets.product_id`;
- the constraint names, taken from the model.

The rest depends on the rows already in the database and on the order of deployment. The model diff does not contain that information:

- **Backfill.** The model says only that `product_code` disappears and `product_id` appears. It does not say that the new value is found through the old one. That mapping is `031`.
- **Old writers keep running.** Until every writer has moved to `product_id`, tickets are still created with only `product_code`. Both columns have to exist, and the backfill has to be safe to rerun. EF has one migration and no notion of "while old code is still deployed".
- **Order.** Our order is expand, backfill, verify, require, then drop. EF drops the old column first, because a single migration only moves from the old model to the new one. Nothing in the model marks that order as unsafe.
- **Objects outside the model.** `tickets_product_currency_fk` from `011` is not in the EF model. EF did not drop it. PostgreSQL removed it implicitly, together with the column. A view or function on `product_code` would have been unknown to EF too. That is what `dependency_check.sql` looks for.
- **The real schema.** EF expected `IX_tickets_product_code` because its own first migration would have created it. It does not inspect the database. Its idempotent guard only checks `__EFMigrationsHistory`.
- **Delete behaviour.** `ON DELETE CASCADE` is EF's default for a required relationship. Whether deleting a product may delete sold tickets is a business rule, not something the model states.

With EF Core, the same change needs several migrations, each deployed on its own. The generated operations have to be edited, and the backfill written by hand with `migrationBuilder.Sql(...)`:

1. add a nullable `product_id` and an unvalidated foreign key, and keep `product_code`;
2. backfill with SQL, safe to run more than once;
3. validate the key, make `product_id` required, and set the delete behaviour to restrict;
4. after the dependency check, drop `product_code`.

That is the same sequence as `030`, `031`, `033`, and `034`. The tool can write each step's DDL. Knowing that the migration has to be split, and in what order, comes from the data and from which code is deployed.
