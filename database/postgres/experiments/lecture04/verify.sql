-- Inspect the stored references after expansion.
select t.id, t.product_code, t.product_id
from tickets t
left join products p on p.id = t.product_id
where t.product_id is null
   or p.id is null
   or t.product_code is distinct from p.code;

-- TODO: Join products and return only tickets with a null ID, a missing
-- product, or a code and ID that refer to different products.
-- Expect no rows after the final backfill. Test your check with a deliberate
-- mismatch inside a transaction, then roll it back.