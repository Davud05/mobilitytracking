-- Step 7. Read the product only through product_id.
-- products.code is still shown, but it comes from products, not from tickets.
select t.id,
       t.product_id,
       p.code as product_code,
       p.name as product_name,
       t.price,
       t.currency
from tickets t
join products p on p.id = t.product_id
order by t.id;
