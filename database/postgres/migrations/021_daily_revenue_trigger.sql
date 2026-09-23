-- Lecture 3: the supplied insert-only summary.
-- This trigger is intentionally incomplete. It runs only after INSERT and
-- only when the new row is already Captured. It does not see status
-- corrections, refunds, or deletes, and it does not backfill existing rows.
-- Those gaps are the point of the comparison in docs/reporting.md.
-- Do not treat daily_revenue_by_operator as an authority.
-- Rebuild path: database/postgres/queries/rebuild_daily_revenue.sql

create table daily_revenue_by_operator (
    operator_id text not null references operators (id),
    revenue_date date not null,
    captured_amount numeric not null default 0,
    captured_payments bigint not null default 0,
    primary key (operator_id, revenue_date)
);

create or replace function add_inserted_payment_to_daily_revenue()
returns trigger
language plpgsql
as $$
declare
    payment_operator_id text;
begin
    if new.status is distinct from 'Captured' then
        return new;
    end if;

    select r.operator_id
    into payment_operator_id
    from tickets t
    join trips tr on tr.id = t.trip_id
    join routes r on r.id = tr.route_id
    where t.id = new.ticket_id;

    insert into daily_revenue_by_operator (
        operator_id, revenue_date, captured_amount, captured_payments
    ) values (
        payment_operator_id, new.created_utc::date, new.amount, 1
    )
    on conflict (operator_id, revenue_date)
    do update set
        captured_amount = daily_revenue_by_operator.captured_amount + excluded.captured_amount,
        captured_payments = daily_revenue_by_operator.captured_payments + 1;

    return new;
end;
$$;

create trigger payments_daily_revenue_after_insert
after insert on payments
for each row
execute function add_inserted_payment_to_daily_revenue();
