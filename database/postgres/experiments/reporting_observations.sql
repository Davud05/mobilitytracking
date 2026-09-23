-- Compare the four revenue approaches after each lecture-3 case.
-- Apply 020, 021 and 022 first. Start from a clean container.
-- Do not apply 011 before this script: the duplicate-delivery case is meant
-- to be stored so the reporting mechanisms can be compared. Migration 011
-- rejects that insert, which is recorded as a separate result.

set timezone = 'UTC';

create temp table evidence (
    step text,
    approach text,
    operator_id text,
    revenue_date date,
    captured_amount numeric,
    captured_payments bigint
);

create or replace function capture_step(step_name text)
returns void
language plpgsql
as $$
declare
    inserted_rows integer;
begin
    insert into evidence
    select step_name, 'base', r.operator_id, p.created_utc::date, sum(p.amount), count(*)
    from payments p
    join tickets t on t.id = p.ticket_id
    join trips tr on tr.id = t.trip_id
    join routes r on r.id = tr.route_id
    where p.status = 'Captured'
    group by r.operator_id, p.created_utc::date;

    insert into evidence
    select step_name, 'function', operator_id, revenue_date, captured_amount, captured_payments
    from (
        select 'OP-METRO' as operator_id, date '2026-04-29' as revenue_date, captured_amount, captured_payments
        from captured_revenue_for_day('OP-METRO', date '2026-04-29')
        union all
        select 'OP-BUS', date '2026-04-29', captured_amount, captured_payments
        from captured_revenue_for_day('OP-BUS', date '2026-04-29')
    ) as function_rows
    where captured_payments > 0;

    begin
        insert into evidence
        select step_name, 'matview', operator_id, revenue_date, captured_amount, captured_payments
        from daily_captured_revenue;
        get diagnostics inserted_rows = row_count;
        if inserted_rows = 0 then
            insert into evidence values (step_name, 'matview', null, null, null, null);
        end if;
    exception
        when object_not_in_prerequisite_state then
            -- Created WITH NO DATA. An unpopulated view is not an empty result.
            insert into evidence values (step_name, 'matview', null, null, null, null);
    end;

    insert into evidence
    select step_name, 'trigger', operator_id, revenue_date, captured_amount, captured_payments
    from daily_revenue_by_operator;
    get diagnostics inserted_rows = row_count;
    if inserted_rows = 0 then
        insert into evidence values (step_name, 'trigger', null, null, null, null);
    end if;
end;
$$;

select capture_step('01 baseline');

insert into payments (
    id, user_id, ticket_id, external_payment_reference,
    amount, currency, status, created_utc
) values (
    'PAY-CASE-CAPTURED', 'USER-1', 'TICKET-1', 'gateway-case-captured',
    36, 'DKK', 'Captured', '2026-04-29 10:00:00+00'
);
select capture_step('02 captured insert');

insert into payments (
    id, user_id, ticket_id, external_payment_reference,
    amount, currency, status, created_utc
) values (
    'PAY-CASE-FAILED', 'USER-1', 'TICKET-1', 'gateway-case-failed',
    50, 'DKK', 'Failed', '2026-04-29 10:05:00+00'
);
select capture_step('03 failed insert');

update payments
set status = 'Captured'
where id = 'PAY-CASE-FAILED';
select capture_step('04 failed to captured');

update payments
set status = 'Refunded'
where id = 'PAY-CASE-CAPTURED';
select capture_step('05 captured to refunded');

delete from payments
where id = 'PAY-CASE-FAILED';
select capture_step('06 delete failed-then-captured');

insert into payments (
    id, user_id, ticket_id, external_payment_reference,
    amount, currency, status, created_utc
) values (
    'PAY-CASE-DUPLICATE', 'USER-1', 'TICKET-1', 'gateway-capture-0001',
    36, 'DKK', 'Captured', '2026-04-29 10:10:00+00'
);
select capture_step('07 duplicate delivery');

refresh materialized view daily_captured_revenue;
select capture_step('08 after matview refresh');

\echo 'Evidence: null amount means that approach returned no rows'
select step, approach, operator_id, revenue_date, captured_amount, captured_payments
from evidence
order by step, approach, operator_id nulls first;

drop function capture_step(text);
