-- Step 7. Remove the legacy ticket reference.
-- Apply only after 032_require_ticket_product.sql, and after
-- experiments/lecture04/dependency_check.sql lists nothing except the two
-- product_code foreign keys from 011_ticketing_integrity.sql.
-- Those keys are dropped by name. CASCADE is not used, so any other dependent
-- object stops the migration. products.code stays as the business code.
-- "if exists" lets this run on a database where 011 was never applied.

begin;
set local lock_timeout = '3s';

alter table tickets
  drop constraint if exists tickets_product_fk;

alter table tickets
  drop constraint if exists tickets_product_currency_fk;

alter table tickets
  drop column product_code;

commit;
