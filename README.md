# MobilityTicketing

Semester project for the MobilityTicketing case. The database is PostgreSQL. The starter schema is the permissive slice published with the lectures. Student work is the migration files, the workload queries, and the notes in `docs/`.

The init scripts are the lecture starter. They are not edited. Constraints and reporting objects are applied afterwards, because the reporting lab has to be able to store a bad duplicate and a status correction before lecture 2's unique constraint exists.

## Layout

| Path | What it is |
| --- | --- |
| `database/postgres/init/` | Starter schema and seed. Loaded only into an empty data directory. |
| `database/postgres/queries/workload.sql` | The three route and trip queries. |
| `database/postgres/migrations/011_ticketing_integrity.sql` | Lecture 2 constraints. |
| `database/postgres/migrations/020_reporting_function.sql` | Revenue function over `payments`. |
| `database/postgres/migrations/021_daily_revenue_trigger.sql` | Incomplete insert-only summary, kept incomplete on purpose. |
| `database/postgres/migrations/022_daily_captured_revenue.sql` | Materialized view, created empty. |
| `database/postgres/queries/base_revenue.sql` | Reference aggregate from the starter. |
| `database/postgres/queries/rebuild_daily_revenue.sql` | Rebuild path for the summary table. |
| `docs/lab.md` | First relational slice: diagram, key decision, assumptions. |
| `docs/integrity-map.md` | Lecture 2 integrity map, traces, and open issues. |
| `docs/reporting.md` | Lecture 3 comparison and recommendation. |
| `docs/assignments/` | The lab texts from the starters. |

## Start

Docker Desktop with Compose.

```bash
docker compose down -v
docker compose up -d
```

`down -v` is required when the init scripts should run again. PostgreSQL runs `docker-entrypoint-initdb.d` only while the data directory is empty. The database is `mobility` on `localhost:5432`, user `mobility`, password `mobility`.

From PowerShell, feed a file to `psql` with `cmd`, because PowerShell does not support `<`:

```powershell
cmd /c "docker compose exec -T postgres psql -U mobility -d mobility < database\postgres\queries\workload.sql"
```

## Suggested order

1. Start a clean database and run `workload.sql`. Notes: `docs/lab.md`.
2. Apply `020`, then `021`, then `022`. Run `database/postgres/experiments/reporting_observations.sql`. Notes: `docs/reporting.md`.
3. Start a clean database again. Apply `011_ticketing_integrity.sql`. Run the files in `database/postgres/experiments/constraints_should_fail.sql`, `constraints_extra_should_fail.sql`, and `constraints_should_succeed.sql`. Notes: `docs/integrity-map.md`.
4. Start a clean database again. Follow the run order in `docs/step7.md` for the product identity migration.

# Compulsory Assignment 1 review guide

Submitted commit: branch `step8AI`, work up to `ceee719`. This guide was added on top of it.
Setup and reset instructions: [Start](#start)

## Where to find the work

Lecture 1: model, workload map and queries
- Model and diagram: [docs/lab.md](docs/lab.md#diagram)
- Workload queries: [database/postgres/queries/workload.sql](database/postgres/queries/workload.sql)
- Result: [docs/evidence/workload.txt](docs/evidence/workload.txt)

Lecture 2: constraints and tests
- Constraints: [database/postgres/migrations/011_ticketing_integrity.sql](database/postgres/migrations/011_ticketing_integrity.sql)
- Integrity map, traces and issues: [docs/integrity-map.md](docs/integrity-map.md)
- Tests: [constraints_should_fail.sql](database/postgres/experiments/constraints_should_fail.sql), [constraints_extra_should_fail.sql](database/postgres/experiments/constraints_extra_should_fail.sql), [constraints_should_succeed.sql](database/postgres/experiments/constraints_should_succeed.sql)
- Evidence: [integrity-fail.txt](docs/evidence/integrity-fail.txt), [integrity-extra-fail.txt](docs/evidence/integrity-extra-fail.txt), [integrity-succeed.txt](docs/evidence/integrity-succeed.txt)

Lecture 3: reporting experiment and comparison
- Approaches: [020_reporting_function.sql](database/postgres/migrations/020_reporting_function.sql), [021_daily_revenue_trigger.sql](database/postgres/migrations/021_daily_revenue_trigger.sql), [022_daily_captured_revenue.sql](database/postgres/migrations/022_daily_captured_revenue.sql)
- Experiment: [reporting_observations.sql](database/postgres/experiments/reporting_observations.sql), rebuild path [rebuild_daily_revenue.sql](database/postgres/queries/rebuild_daily_revenue.sql)
- Comparison and decision: [docs/reporting.md](docs/reporting.md)
- Evidence: [docs/evidence/reporting.txt](docs/evidence/reporting.txt)

Lecture 4: migration stages and verification
- Stages: [030_expand_product_identity.sql](database/postgres/migrations/030_expand_product_identity.sql), [031_backfill_ticket_product.sql](database/postgres/migrations/031_backfill_ticket_product.sql), [032_require_ticket_product.sql](database/postgres/migrations/032_require_ticket_product.sql), [033_drop_ticket_product_code.sql](database/postgres/migrations/033_drop_ticket_product_code.sql)
- Old and new application code: [database/postgres/experiments/lecture04/](database/postgres/experiments/lecture04/)
- Verification: [verify.sql](database/postgres/experiments/lecture04/verify.sql), [dependency_check.sql](database/postgres/experiments/lecture04/dependency_check.sql), [view_blocks_drop.sql](database/postgres/experiments/lecture04/view_blocks_drop.sql)
- Run order and notes: [docs/step7.md](docs/step7.md), evidence [docs/evidence/step7.txt](docs/evidence/step7.txt)
- EF Core comparison: [docs/step8.md](docs/step8.md)

## Two decisions worth discussing

### Revenue is read through a function over `payments`

We chose `captured_revenue_for_day`, which aggregates `payments` where `status = 'Captured'`. The alternatives were the insert-only trigger summary `daily_revenue_by_operator` and the materialized view `daily_captured_revenue`.

MobilityTicketing payments change after insert: a failed payment is later captured, a captured payment is refunded, a row is deleted, and a gateway can deliver the same capture twice. The trigger only sees a new `Captured` insert. In step 04 of [docs/evidence/reporting.txt](docs/evidence/reporting.txt) the function shows City Metro 122.00 across 3 payments while the trigger still shows 36 across 1. The materialized view is correct only after a refresh, and before the first refresh it raises SQLSTATE `55000`. `payments` stays the only authority. See [docs/reporting.md](docs/reporting.md#decision).

### Product identity is changed in expand, backfill and contract stages

We chose to add `tickets.product_id` next to `product_code` instead of replacing the column in one migration. `030` adds the column and a `NOT VALID` foreign key. `031` backfills from `product_code` and can be run again. `032` validates the key and sets `NOT NULL`. `033` drops `product_code` only after [dependency_check.sql](database/postgres/experiments/lecture04/dependency_check.sql) finds nothing that still reads it.

The alternative was a single migration that drops `product_code` and adds `product_id`. That breaks the old writer and old reader in [lecture04/](database/postgres/experiments/lecture04/) at the moment of deploy, and tickets sold during the change would have no product. With the staged version both old and new code work between `030` and `032`. `033` drops without `CASCADE`, and [view_blocks_drop.sql](database/postgres/experiments/lecture04/view_blocks_drop.sql) shows that a dependent view makes the drop fail instead of being removed silently. Evidence: [docs/evidence/step7.txt](docs/evidence/step7.txt).

## One limitation or open question

Two concurrent purchases can oversell a trip. `trips_reserved_seats_valid` checks `reserved_seats <= capacity` on the row that is written. It does not see what another transaction read at the same time, and nothing recounts `reserved_seats` against the tickets actually held. See Issue 1 in [docs/integrity-map.md](docs/integrity-map.md#issue-1).

Next we would run two sessions that buy the last seat of the same trip at the same time and record whether both commit. Then we would repeat it with a single conditional update, `set reserved_seats = reserved_seats + 1 where reserved_seats < capacity`, and treat zero updated rows as sold out. We are also unsure whether a seat is held at payment authorization or only when the payment is `Captured`.


