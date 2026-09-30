-- Step 4. A writer that starts from a product ID.
-- Run after 030_expand_product_identity.sql and before 033_drop_ticket_product_code.sql.
-- The function lives in pg_temp, so it disappears when this session ends and
-- does not show up in dependency_check.sql for step 7.
-- Change ticket_id and ticket_code for each new ticket, as with old_writer.sql:
--   -v ticket_id=LAB04-NEW-ID-2 -v ticket_code=LAB04-CODE-NEW-ID-2

-- After expansion, use this query to choose a product ID for your test.
select id, code, price, currency from products order by code;

create function pg_temp.create_ticket_from_product_id(
    p_ticket_id text,
    p_ticket_code text,
    p_user_id text,
    p_trip_id text,
    p_product_id uuid,
    p_agreed_price numeric,
    p_currency text,
    p_valid_from_utc timestamptz,
    p_valid_to_utc timestamptz,
    p_supplied_product_code text default null
)
returns text
language plpgsql
as $$
declare
    v_product_code text;
begin
    select code
    into v_product_code
    from products
    where id = p_product_id;

    if not found then
        raise exception 'unknown product id %', p_product_id
            using errcode = 'foreign_key_violation';
    end if;

    if p_supplied_product_code is not null
       and p_supplied_product_code <> v_product_code then
        raise exception 'product code % does not belong to product id % (%)',
            p_supplied_product_code, p_product_id, v_product_code
            using errcode = 'invalid_parameter_value';
    end if;

    insert into tickets
        (id, user_id, trip_id, ticket_code, status, product_id, product_code,
         valid_from_utc, valid_to_utc, price, currency)
    values
        (p_ticket_id, p_user_id, p_trip_id, p_ticket_code, 'Active', p_product_id, v_product_code,
         p_valid_from_utc, p_valid_to_utc, p_agreed_price, p_currency);

    return p_ticket_id;
end;
$$;

\if :{?ticket_id}
\else
\set ticket_id 'LAB04-NEW-ID-1'
\endif

\if :{?ticket_code}
\else
\set ticket_code 'LAB04-CODE-NEW-ID-1'
\endif

\if :{?product_id}
\else
select id as product_id from products where code = 'DAY' \gset
\endif

-- The agreed price is what the customer was charged. It is not read from the
-- catalogue, so a discount or an old price survives a later catalogue change.
\if :{?agreed_price}
\else
\set agreed_price 72.00
\endif

\if :{?agreed_currency}
\else
\set agreed_currency 'DKK'
\endif

select pg_temp.create_ticket_from_product_id(
    :'ticket_id', :'ticket_code', 'USER-2', 'TRIP-5C-20260429-1700',
    :'product_id'::uuid, :agreed_price, :'agreed_currency',
    '2026-04-29 16:45:00+00', '2026-04-29 19:00:00+00'
) as created_ticket;

-- Both references point at the same product. The ticket keeps the agreed
-- price even though the catalogue says something else.
select t.id,
       t.product_id,
       t.product_code,
       p.code as product_code_from_id,
       t.price as ticket_price,
       p.price as catalogue_price,
       t.currency
from tickets t
join products p on p.id = t.product_id
where t.id = :'ticket_id';

-- Unknown product ID. Expected: rejected by the writer with SQLSTATE 23503.
do $$
begin
    perform pg_temp.create_ticket_from_product_id(
        'LAB04-UNKNOWN-ID', 'LAB04-CODE-UNKNOWN-ID', 'USER-1', 'TRIP-M2-20260429-0800',
        gen_random_uuid(), 36.00, 'DKK',
        '2026-04-29 07:45:00+00', '2026-04-29 10:00:00+00');
    raise exception 'an unknown product id was accepted';
exception
    when foreign_key_violation then
        raise notice 'unknown product id rejected: %', sqlerrm;
end;
$$;

-- The DAY product ID with a supplied SINGLE code.
-- Expected: rejected by the writer with SQLSTATE 22023.
do $$
begin
    perform pg_temp.create_ticket_from_product_id(
        'LAB04-WRONG-CODE', 'LAB04-CODE-WRONG-CODE', 'USER-1', 'TRIP-M2-20260429-0800',
        (select id from products where code = 'DAY'), 80.00, 'DKK',
        '2026-04-29 07:45:00+00', '2026-04-29 10:00:00+00',
        'SINGLE');
    raise exception 'a product code from another product was accepted';
exception
    when invalid_parameter_value then
        raise notice 'mismatched product code rejected: %', sqlerrm;
end;
$$;

-- Neither rejected ticket was stored.
select count(*) as rejected_tickets_stored
from tickets
where id in ('LAB04-UNKNOWN-ID', 'LAB04-WRONG-CODE');
