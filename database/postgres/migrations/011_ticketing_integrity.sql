-- Lecture 2: turn the permissive ticketing schema into named invariants.
-- The starter DDL in database/postgres/init is left unchanged.
-- Constraints that need more than one row, or an external system, are
-- classified in docs/integrity-map.md and are not pretended to be solved here.

begin;

alter table trips
    alter column capacity set not null,
    alter column reserved_seats set not null,
    alter column status set not null,
    add constraint trips_capacity_non_negative
        check (capacity >= 0),
    add constraint trips_reserved_seats_valid
        check (reserved_seats >= 0 and reserved_seats <= capacity),
    add constraint trips_status_known
        check (status in ('Scheduled', 'Cancelled', 'Departed', 'Completed'));

alter table products
    alter column name set not null,
    alter column price set not null,
    alter column currency set not null,
    add constraint products_price_non_negative
        check (price >= 0),
    add constraint products_currency_iso
        check (currency ~ '^[A-Z]{3}$'),
    add constraint products_code_currency_key
        unique (code, currency);

alter table users
    alter column email set not null,
    alter column full_name set not null,
    alter column is_disabled set not null,
    add constraint users_email_unique
        unique (email);

alter table tickets
    alter column user_id set not null,
    alter column trip_id set not null,
    alter column ticket_code set not null,
    alter column status set not null,
    alter column product_code set not null,
    alter column valid_from_utc set not null,
    alter column valid_to_utc set not null,
    alter column price set not null,
    alter column currency set not null,
    add constraint tickets_user_fk
        foreign key (user_id) references users (id),
    add constraint tickets_trip_fk
        foreign key (trip_id) references trips (id),
    add constraint tickets_product_fk
        foreign key (product_code) references products (code),
    add constraint tickets_product_currency_fk
        foreign key (product_code, currency) references products (code, currency),
    add constraint tickets_code_unique
        unique (ticket_code),
    add constraint tickets_id_code_key
        unique (id, ticket_code),
    add constraint tickets_id_currency_key
        unique (id, currency),
    add constraint tickets_status_known
        check (status in ('Active', 'Validated', 'Expired', 'Cancelled', 'Refunded')),
    add constraint tickets_price_non_negative
        check (price >= 0),
    add constraint tickets_currency_iso
        check (currency ~ '^[A-Z]{3}$'),
    add constraint tickets_validity_window
        check (valid_to_utc >= valid_from_utc);

alter table payments
    alter column user_id set not null,
    alter column ticket_id set not null,
    alter column amount set not null,
    alter column currency set not null,
    alter column status set not null,
    alter column created_utc set not null,
    add constraint payments_user_fk
        foreign key (user_id) references users (id),
    add constraint payments_ticket_fk
        foreign key (ticket_id) references tickets (id),
    add constraint payments_ticket_currency_fk
        foreign key (ticket_id, currency) references tickets (id, currency),
    add constraint payments_amount_non_negative
        check (amount >= 0),
    add constraint payments_currency_iso
        check (currency ~ '^[A-Z]{3}$'),
    add constraint payments_status_known
        check (status in ('Pending', 'Authorized', 'Captured', 'Failed', 'Refunded')),
    add constraint payments_external_reference_unique
        unique (external_payment_reference);

alter table validations
    alter column ticket_id set not null,
    alter column ticket_code set not null,
    alter column result set not null,
    alter column validated_utc set not null,
    add constraint validations_ticket_fk
        foreign key (ticket_id) references tickets (id),
    add constraint validations_ticket_identity_fk
        foreign key (ticket_id, ticket_code) references tickets (id, ticket_code),
    add constraint validations_stop_fk
        foreign key (stop_id) references stops (id),
    add constraint validations_result_known
        check (result in ('Accepted', 'Rejected'));

commit;
