-- Step 7. The writer no longer stores product_code.
-- The agreed price and currency are inputs and are stored on the ticket.
-- An unknown product_id inserts zero rows instead of a ticket without a product.
\set ticket_id 'LAB04-NEW-1'
\set ticket_code 'LAB04-CODE-NEW-1'
\set product_code 'DAY'
\set agreed_price 80.00
\set agreed_currency 'DKK'

insert into tickets
    (id, user_id, trip_id, ticket_code, status, product_id,
     valid_from_utc, valid_to_utc, price, currency)
select :'ticket_id', 'USER-2', 'TRIP-5C-20260429-1700', :'ticket_code', 'Active', p.id,
       '2026-04-29 16:45:00+00', '2026-04-29 19:00:00+00',
       :agreed_price, :'agreed_currency'
from products p
where p.code = :'product_code';
