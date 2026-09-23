# Integrity map

Lecture 2 adds named constraints in `database/postgres/migrations/011_ticketing_integrity.sql`. The starter DDL is unchanged. A check on one row is not a claim about concurrent purchases or about the payment gateway.

## Classification

| Invariant | Class | Decision |
| --- | --- | --- |
| Capacity is not negative | Column check | `trips_capacity_non_negative` |
| Reserved seats are between 0 and capacity | Column check | `trips_reserved_seats_valid`. One row only. |
| Product, ticket, and payment amounts are not negative | Column check | `products_price_non_negative`, `tickets_price_non_negative`, `payments_amount_non_negative` |
| Currency is present and shaped like ISO 4217 | Not null + check | `^[A-Z]{3}$` on products, tickets, and payments |
| A ticket uses the product's currency | Composite foreign key | `tickets_product_currency_fk` on `(product_code, currency)` |
| A payment uses the ticket's currency | Composite foreign key | `payments_ticket_currency_fk` on `(ticket_id, currency)` |
| Ticket code identifies one ticket | Unique | `tickets_code_unique` |
| A payment refers to an existing ticket and user | Foreign key | `payments_ticket_fk`, `payments_user_fk` |
| A validation refers to an existing ticket | Foreign key | `validations_ticket_fk` |
| A validation cannot mix one ticket's id with another ticket's code | Composite foreign key | `validations_ticket_identity_fk` on `(ticket_id, ticket_code)` |
| Validity ends at or after it starts | Column check | `tickets_validity_window` |
| Status and validation result come from a known set | Column check | `trips_status_known`, `tickets_status_known`, `payments_status_known`, `validations_result_known` |
| One external payment reference is stored once | Unique | `payments_external_reference_unique`. Null references may repeat; a present reference may not. |
| Two purchases cannot oversell the same seats | More than one row, and concurrent | Not solved. The check sees one row's `reserved_seats` after someone has already written it. |
| `reserved_seats` equals the tickets actually held | More than one row | Not solved. Nothing recounts tickets. |
| Capturing a payment at the gateway and in PostgreSQL stays in step | External system | Not solved. The unique reference only helps after a reference is known. |
| A disabled user cannot buy | Domain decision | Not solved. `is_disabled` is stored and not consulted. The success script inserts such a ticket and rolls it back. |
| A validation is inside the ticket window and the ticket is still usable | More than one row | Not solved. The validation row does not compare itself with `tickets.valid_from_utc`. |
| Ticket price stays equal to the current product price | Domain decision | Rejected on purpose. `tickets.price` is a snapshot. A later product-price change must not rewrite sold tickets. |

Status vocabulary used by the checks:

- trip: `Scheduled`, `Cancelled`, `Departed`, `Completed`
- ticket: `Active`, `Validated`, `Expired`, `Cancelled`, `Refunded`
- payment: `Pending`, `Authorized`, `Captured`, `Failed`, `Refunded`
- validation result: `Accepted`, `Rejected`

The seed data and the lecture-3 cases use values inside those sets. Adding a status later is a migration, not an application-only string.

## Map

| Invariant | Affected tables and columns | Current protection | Missing protection or limitation | Expected failure | Evidence |
| --- | --- | --- | --- | --- | --- |
| Capacity cannot be negative | `trips.capacity` | `trips_capacity_non_negative` | None for a single row | SQLSTATE 23514 | Update to `-1` fails. Update to `100` with reserved seats still inside the limit succeeds. |
| Reserved seats fit the vehicle | `trips.reserved_seats`, `trips.capacity` | `trips_reserved_seats_valid` | Two transactions can both read the same remainder and both write | SQLSTATE 23514 | `reserved_seats = capacity + 1` fails. `reserved_seats = capacity` succeeds. |
| Amounts are not negative | `products.price`, `tickets.price`, `payments.amount` | three check constraints | Does not compare ticket price with product price | SQLSTATE 23514 | Product price `-1` fails. Product price `0` succeeds. Ticket price `-1` fails. |
| Currency is present and three letters | currency columns | not null + `*_currency_iso` | Does not prove the code is a real currency | SQLSTATE 23514 | `kr` fails. |
| Ticket currency matches the product | `tickets (product_code, currency)`, `products (code, currency)` | `tickets_product_currency_fk` | Snapshot price may still differ from the catalogue price | SQLSTATE 23503 | A new `SINGLE` ticket in `EUR` fails. Changing `TICKET-1` from `DKK` fails earlier, because `PAYMENT-1` still references `(TICKET-1, DKK)`. |
| Payment currency matches the ticket | `payments (ticket_id, currency)`, `tickets (id, currency)` | `payments_ticket_currency_fk` | Gateway currency is not checked against an external system | SQLSTATE 23503 | Payment currency `EUR` against a `DKK` ticket fails. |
| Ticket code is unambiguous | `tickets.ticket_code` | `tickets_code_unique` | Codes are not checked for format | SQLSTATE 23505 | Second insert of `CODE-M2-0001` fails. |
| Payment needs a real ticket | `payments.ticket_id` | `payments_ticket_fk` | Does not require the ticket to be `Active` | SQLSTATE 23503 | `NO-SUCH-TICKET` fails. |
| Validation needs a real ticket | `validations.ticket_id` | `validations_ticket_fk` | Does not require the ticket window to contain `validated_utc` | SQLSTATE 23503 | Covered by the identity foreign key when the id itself is missing. |
| Validation id and code are the same ticket | `validations (ticket_id, ticket_code)` | `validations_ticket_identity_fk` | A later update of `tickets.ticket_code` is rejected while validations point at the old pair, which is the behaviour we want | SQLSTATE 23503 | `TICKET-1` with `CODE-5C-0001` fails. The matching pair succeeds. |
| Validity window is ordered | `tickets.valid_from_utc`, `tickets.valid_to_utc` | `tickets_validity_window` | Equal endpoints are allowed | SQLSTATE 23514 | End before start fails. |
| Status comes from the known set | status and result columns | `*_status_known`, `validations_result_known` | The sets are a domain decision | SQLSTATE 23514 | Ticket status `Unknown` fails. Validation result `Maybe` fails. `Validated` succeeds. |
| External reference is stored once | `payments.external_payment_reference` | `payments_external_reference_unique` | Nulls are not collapsed. The gateway can still capture money we never store if the write is lost. | SQLSTATE 23505 | Second `gateway-capture-0001` fails. |
| Disabled user cannot buy | `users.is_disabled`, `tickets.user_id` | Column is stored | No constraint and no workflow | Insert succeeds | `TICKET-DISABLED` is accepted inside the rolled-back success script. |
| Seat count matches tickets held | `trips.reserved_seats`, `tickets` | Single-row check only | No cross-row equality | Not rejected | Left for the transactions lecture. |
| Gateway and database commit together | `payments`, external reference | Unique reference after the fact | No outbox or saga | Not rejected | Left for the transactions lecture. |

## State-transition trace

### Ticket purchase

1. `users`, `products`, and `trips` must already contain the referenced rows.
2. Insert one `tickets` row: user, trip, product, unique code, status `Active`, snapshot price, product currency, and a window with `valid_to_utc >= valid_from_utc`.
3. Insert one `payments` row that references that ticket and user. Amount is non-negative, currency equals the ticket currency, status is one of the known payment statuses, and the external reference is new.
4. The application may then update `trips.reserved_seats`. The database checks the new value against capacity on that row. It does not lock the remaining seats against a concurrent buyer.
5. Either both inserts commit, or neither does. This migration does not itself open that transaction. The foreign keys only say the ticket must exist by the end of the statement that writes the payment.

### Ticket validation

1. The ticket row must exist.
2. Insert one `validations` row whose `(ticket_id, ticket_code)` pair exists on `tickets`. `stop_id` may be null; if it is present it must exist in `stops`.
3. `result` is `Accepted` or `Rejected`.
4. A later update of the ticket to `Validated` is a separate write. This migration does not perform it.
5. The validation row remains even if the ticket later becomes `Expired` or `Refunded`.

## Delete and update behaviour

Historical tickets, payments, and validations are evidence. They are not cascade-deleted.

| Relationship | Delete | Update |
| --- | --- | --- |
| `tickets.user_id` → `users` | Restrict. A user with tickets is retained or retired by a status, not removed. | Changing `users.id` is rejected while tickets point at it. |
| `tickets.trip_id` → `trips` | Restrict. A departed trip is history. | The trip key stays. Status may move through the known set. Capacity may change only while the reserved-seat check still holds. |
| `tickets.product_code` → `products` | Restrict while tickets reference the product. | Catalogue price may change. Sold `tickets.price` is not updated, because it is a snapshot. |
| `payments.ticket_id` → `tickets` | Restrict. A payment without its ticket cannot be explained. | Ticket id and code stay. Status may change. Currency cannot change while a payment references the old `(id, currency)` pair. |
| `validations.ticket_id` → `tickets` | Restrict. An inspection result is kept for disputes. | The ticket code cannot be rewritten while a validation stores the old pair. |
| `validations.stop_id` → `stops` | Restrict if a validation names the stop. | Stop name can change; the stop id should not. |
| `routes.operator_id` → `operators` | Restrict. Revenue and routes need the operator. | Operator id is stable. |

Soft delete and a retention period are not implemented. They are a policy question: payments and validations should be kept for reporting and disputes, then removed by an explicit retention job rather than by `ON DELETE CASCADE`.

## Issue register

### Issue 1

- Evidence: `trips_reserved_seats_valid` rejects `reserved_seats > capacity` on the row that was written. It does not look at other transactions.
- Problem: two buyers can read the same free seats and both commit an increment that the check only sees afterwards, or not at all if each writes a legal value computed from a stale read.
- Consequence: the vehicle can be oversold even though every committed row satisfies the check.
- Specific improvement: in the transactions lecture, serialize the increment with one update of the trip row, for example `set reserved_seats = reserved_seats + 1 where reserved_seats < capacity`, and handle zero updated rows as sold out.
- Open question: is a held seat reserved at payment authorization or only when the payment is `Captured`?

### Issue 2

- Evidence: the success script inserts a ticket for `USER-DISABLED` and the statement is accepted.
- Problem: `users.is_disabled` has no owner in the database.
- Consequence: every application that sells tickets must remember the rule, and a script can bypass it.
- Specific improvement: decide whether the rule is "no new ticket for a disabled account" and then enforce it in the purchase transaction. A foreign key cannot express it. A trigger could, but only after the product decision is explicit.
- Open question: may a disabled account still hold and validate tickets bought before the account was disabled?

## Runs

Rejected writes: `database/postgres/experiments/constraints_should_fail.sql` and `constraints_extra_should_fail.sql`.

Accepted writes, rolled back: `database/postgres/experiments/constraints_should_succeed.sql`.

The captured PostgreSQL results are in `docs/evidence/integrity-fail.txt`, `docs/evidence/integrity-extra-fail.txt`, and `docs/evidence/integrity-succeed.txt`.
