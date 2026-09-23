# First relational slice

The first slice answers route maintenance and upcoming-trip queries. It is not the whole MobilityTicketing platform. Ticket purchase, validation, and revenue are later slices. The executable schema is `database/postgres/init/001_relational_baseline.sql`. The three queries are `database/postgres/queries/workload.sql`.

## Entities

| Entity | Key | Attributes determined by the key |
| --- | --- | --- |
| Operator | `id` | `name` |
| Route | `id` | `operator_id`, `city_id`, `mode`, `short_name` |
| Stop | `id` | `city_id`, `name` |
| Route stop | `(route_id, stop_sequence)` | `stop_id` |
| Trip | `id` | `route_id`, `service_date`, `scheduled_departure_utc`, `status` |

Those functional dependencies make every determinant a candidate key, so this slice is in BCNF. Nothing non-key determines another non-key attribute. `city_id` is repeated on routes and stops because a city is not its own entity yet. That is intentional duplication of an external code, not a transitive dependency inside the slice.

## Diagram

```mermaid
erDiagram
    operators ||--o{ routes : operates
    routes ||--o{ route_stops : orders
    stops ||--o{ route_stops : appears_on
    routes ||--o{ trips : schedules

    operators {
        text id PK
        text name
    }
    routes {
        text id PK
        text operator_id FK
        text city_id
        text mode
        text short_name
    }
    stops {
        text id PK
        text city_id
        text name
    }
    route_stops {
        text route_id PK_FK
        int stop_sequence PK
        text stop_id FK
    }
    trips {
        text id PK
        text route_id FK
        date service_date
        timestamptz scheduled_departure_utc
        text status
    }
```

## Primary key of route_stops

The primary key is `(route_id, stop_sequence)`.

`stop_sequence` is the position of a stop on one route. Two stops cannot share a position, and the upcoming-trip and route-maintenance screens need the stops in that order. The key matches the workload: "show the ordered stops belonging to a route" is a lookup by `route_id` ordered by `stop_sequence`.

`(route_id, stop_id)` is not the primary key. A route can visit the same stop twice, for example a loop that passes Nørreport in both directions, or a terminus that is both the first and last stop. If that pair were the key, the second visit could not be stored. The sequence key allows the repeat. A unique constraint on `(route_id, stop_id)` is therefore also omitted. The seed data happens to visit each stop once. That is sample data, not a rule.

`stop_sequence > 0` is a check constraint so position 0 or a negative position cannot be inserted.

## Workload queries

1. Next 20 scheduled trips for one route after a timestamp: filter `trips` on `route_id`, `status = 'Scheduled'`, and `scheduled_departure_utc`, then order and `limit 20`.
2. Ordered stops on a route: join `route_stops` to `stops` and order by `stop_sequence`.
3. All routes and the number of scheduled trips on a date: `routes` left join `trips`, so a route with no matching trip returns `0`.

"Scheduled" is a business filter. Cancelled trips stay in the table but do not count. The supplied seed uses the status value `Scheduled`.

## Assumptions, and where the schema differs from a fuller ER model

- A city is a code (`CPH`), not a `cities` table. The code is owned outside this slice.
- `mode` is text (`metro`, `bus`, `tram`). A lookup table can wait until the set needs descriptions or rules of its own.
- A route has one ordered stop list. Two directions of the same public line are two routes, or a later `direction` attribute. They are not modeled as one route with two patterns.
- A trip has one departure timestamp. There is no stop-level timetable yet, so "departures and delays" at a particular stop cannot be answered honestly. That difference is accepted for this slice: the released workload asks for trips on a route, not predicted arrival at each stop.
- `trips.status` is free text in the starter DDL. The allowed set is enforced in the lecture-2 migration, not in this slice.
- Capacity and reserved seats are not part of this slice. They are added, still unconstrained, by `010_ticketing_draft.sql`.
- Tickets, payments, and validations are a later slice. They are not required for these three queries.

## Observed result

`docs/evidence/workload.txt` is the run against the seed data.

- Q1 for `LINE-M2` after `2026-04-29 07:00:00+00` returns the 08:00 and 12:00 trips, in that order.
- Q2 returns Nørreport, Kongens Nytorv, Copenhagen Airport as sequences 1, 2, 3.
- Q3 on `2026-04-29` returns 2 scheduled trips for both `LINE-5C` and `LINE-M2`.
- The same count on `2026-04-30` returns 0 for both routes. The routes are still present, which is what the left join is for.

## What this slice does not claim

Rush-hour search, live delay, and ticket checks are not supported yet. An index on `(route_id, scheduled_departure_utc)` would be the next physical step if the trip query becomes hot. It is not required to make the model executable.
