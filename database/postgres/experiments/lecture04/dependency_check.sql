-- Step 7. Find everything that still uses tickets.product_code before dropping it.
-- Run after 032_require_ticket_product.sql.

-- Objects PostgreSQL records as depending on the column:
-- constraints, indexes, and views.
select pg_describe_object(d.classid, d.objid, d.objsubid) as dependent_object,
       d.deptype
from pg_depend d
join pg_attribute a
  on a.attrelid = d.refobjid
 and a.attnum = d.refobjsubid
where d.refobjid = 'tickets'::regclass
  and a.attname = 'product_code'
order by 1;

-- Function bodies are stored as text, so pg_depend does not track them.
select p.proname as function_name
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.prosrc ilike '%product_code%'
order by 1;

-- Views, searched by definition as a second check.
select viewname
from pg_views
where schemaname = 'public'
  and definition ilike '%product_code%'
union all
select matviewname
from pg_matviews
where schemaname = 'public'
  and definition ilike '%product_code%'
order by 1;
