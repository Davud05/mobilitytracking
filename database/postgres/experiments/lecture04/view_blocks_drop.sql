-- Step 7. Show that the dependency check finds a view, and that dropping the
-- column without CASCADE is refused while the view exists.
-- Run with ON_ERROR_STOP=0: the drop is expected to fail. Everything is rolled back.

begin;

create view ticket_product_codes as
select id, product_code
from tickets;

select pg_describe_object(d.classid, d.objid, d.objsubid) as dependent_object,
       d.deptype
from pg_depend d
join pg_attribute a
  on a.attrelid = d.refobjid
 and a.attnum = d.refobjsubid
where d.refobjid = 'tickets'::regclass
  and a.attname = 'product_code'
order by 1;

savepoint before_drop;

alter table tickets drop column product_code;

rollback to savepoint before_drop;

rollback;
