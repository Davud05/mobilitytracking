-- Extra rejected writes beyond the supplied experiments file.
-- Run each statement after 011_ticketing_integrity.sql.
-- psql continues after an error unless ON_ERROR_STOP is set.

\set VERBOSITY verbose

-- Negative ticket price. Expected: tickets_price_non_negative, SQLSTATE 23514.
update tickets
set price = -1
where id = 'TICKET-1';

-- Currency that is not three letters. Expected: tickets_currency_iso, SQLSTATE 23514.
update tickets
set currency = 'kr'
where id = 'TICKET-1';

-- Changing a sold ticket's currency would rewrite the pair a payment already stores.
-- Expected: payments_ticket_currency_fk, SQLSTATE 23503.
update tickets
set currency = 'EUR'
where id = 'TICKET-1';

-- A new ticket whose currency is not the product currency.
-- Expected: tickets_product_currency_fk, SQLSTATE 23503.
insert into tickets (
    id, user_id, trip_id, ticket_code, status, product_code,
    valid_from_utc, valid_to_utc, price, currency
) values (
    'TICKET-WRONG-CURRENCY', 'USER-1', 'TRIP-M2-20260429-0800', 'CODE-WRONG-CURRENCY',
    'Active', 'SINGLE', '2026-04-29 08:00:00+00', '2026-04-29 09:00:00+00', 36, 'EUR'
);

-- Payment currency differs from the ticket. Expected: payments_ticket_currency_fk, SQLSTATE 23503.
update payments
set currency = 'EUR'
where id = 'PAYMENT-1';

-- Unknown validation result. Expected: validations_result_known, SQLSTATE 23514.
update validations
set result = 'Maybe'
where id = 'VALIDATION-1';

-- Validation stop that does not exist. Expected: validations_stop_fk, SQLSTATE 23503.
update validations
set stop_id = 'STOP-DOES-NOT-EXIST'
where id = 'VALIDATION-1';
