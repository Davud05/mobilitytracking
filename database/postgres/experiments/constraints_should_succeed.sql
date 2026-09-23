-- Valid writes for the invariants in 011_ticketing_integrity.sql.
-- The transaction is rolled back so the seeded database stays unchanged.
-- Run after the integrity migration.

begin;

-- Capacity may be lowered while reserved seats still fit.
update trips
set capacity = 100
where id = 'TRIP-M2-20260429-0800'
  and reserved_seats <= 100;

-- Reserved seats may occupy the whole vehicle.
update trips
set reserved_seats = capacity
where id = 'TRIP-M2-20260429-1200';

-- A zero price is allowed. Negative is not.
update products
set price = 0
where code = 'DAY';

-- New ticket: known user, trip, product, currency, status, and window.
insert into tickets (
    id, user_id, trip_id, ticket_code, status, product_code,
    valid_from_utc, valid_to_utc, price, currency
) values (
    'TICKET-OK', 'USER-1', 'TRIP-M2-20260429-1200', 'CODE-M2-0002', 'Active', 'SINGLE',
    '2026-04-29 11:45:00+00', '2026-04-29 14:00:00+00', 36.00, 'DKK'
);

-- A payment for that ticket, with a new external reference and the same currency.
insert into payments (
    id, user_id, ticket_id, external_payment_reference,
    amount, currency, status, created_utc
) values (
    'PAYMENT-OK', 'USER-1', 'TICKET-OK', 'gateway-capture-ok',
    36.00, 'DKK', 'Captured', '2026-04-29 11:40:00+00'
);

-- Validation must repeat the code that belongs to this ticket id.
insert into validations (
    id, ticket_id, ticket_code, vehicle_id, stop_id, device_id, result, validated_utc
) values (
    'VALIDATION-OK', 'TICKET-OK', 'CODE-M2-0002', 'METRO-M2-01', 'STOP-NORREPORT', 'DEVICE-02',
    'Accepted', '2026-04-29 12:05:00+00'
);

-- A known status change is allowed. Whether it should be audited is a later decision.
update tickets
set status = 'Validated'
where id = 'TICKET-OK';

-- Gap, kept on purpose: a disabled user can still buy a ticket.
-- No constraint in this lecture owns that rule.
insert into users (id, email, full_name, is_disabled) values
    ('USER-DISABLED', 'disabled@example.test', 'Disabled Rider', true);

insert into tickets (
    id, user_id, trip_id, ticket_code, status, product_code,
    valid_from_utc, valid_to_utc, price, currency
) values (
    'TICKET-DISABLED', 'USER-DISABLED', 'TRIP-M2-20260429-1200', 'CODE-M2-0003', 'Active', 'SINGLE',
    '2026-04-29 11:45:00+00', '2026-04-29 14:00:00+00', 36.00, 'DKK'
);

rollback;
