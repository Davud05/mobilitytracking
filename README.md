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

