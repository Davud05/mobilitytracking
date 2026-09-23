-- First relational slice: the three workload queries.
-- Assumptions are recorded in docs/lab.md.
--
--   docker compose exec -T postgres psql -U mobility -d mobility -f - < database/postgres/queries/workload.sql

\set route_id 'LINE-M2'
\set after_ts '2026-04-29 07:00:00+00'
\set service_date '2026-04-29'

\echo 'Q1: next 20 scheduled trips for a route after a timestamp'
select
    id,
    route_id,
    service_date,
    scheduled_departure_utc,
    status
from trips
where route_id = :'route_id'
  and status = 'Scheduled'
  and scheduled_departure_utc > :'after_ts'::timestamptz
order by scheduled_departure_utc
limit 20;

\echo 'Q2: ordered stops on a route'
select
    rs.stop_sequence,
    s.id as stop_id,
    s.name as stop_name,
    s.city_id
from route_stops rs
join stops s on s.id = rs.stop_id
where rs.route_id = :'route_id'
order by rs.stop_sequence;

\echo 'Q3: every route and its scheduled-trip count on a service date'
\echo '    (routes with no trips are kept by the left join)'
select
    r.id as route_id,
    r.short_name,
    r.operator_id,
    count(t.id) as scheduled_trips
from routes r
left join trips t
    on t.route_id = r.id
   and t.service_date = :'service_date'::date
   and t.status = 'Scheduled'
group by r.id, r.short_name, r.operator_id
order by r.id;

\echo 'Q3b: same query on a date with no trips, so both routes show zero'
select
    r.id as route_id,
    r.short_name,
    count(t.id) as scheduled_trips
from routes r
left join trips t
    on t.route_id = r.id
   and t.service_date = date '2026-04-30'
   and t.status = 'Scheduled'
group by r.id, r.short_name
order by r.id;
