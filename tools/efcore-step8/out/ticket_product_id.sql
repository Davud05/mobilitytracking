START TRANSACTION;


DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "MigrationId" = '20260929122820_TicketProductId') THEN
    ALTER TABLE tickets DROP CONSTRAINT tickets_product_fk;
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "MigrationId" = '20260929122820_TicketProductId') THEN
    DROP INDEX "IX_tickets_product_code";
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "MigrationId" = '20260929122820_TicketProductId') THEN
    ALTER TABLE tickets DROP COLUMN product_code;
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "MigrationId" = '20260929122820_TicketProductId') THEN
    ALTER TABLE tickets ADD product_id uuid NOT NULL DEFAULT '00000000-0000-0000-0000-000000000000';
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "MigrationId" = '20260929122820_TicketProductId') THEN
    ALTER TABLE products ADD id uuid NOT NULL DEFAULT (gen_random_uuid());
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "MigrationId" = '20260929122820_TicketProductId') THEN
    ALTER TABLE products ADD CONSTRAINT products_id_unique UNIQUE (id);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "MigrationId" = '20260929122820_TicketProductId') THEN
    CREATE INDEX "IX_tickets_product_id" ON tickets (product_id);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "MigrationId" = '20260929122820_TicketProductId') THEN
    ALTER TABLE tickets ADD CONSTRAINT tickets_product_id_fk FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE;
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "MigrationId" = '20260929122820_TicketProductId') THEN
    INSERT INTO "__EFMigrationsHistory" ("MigrationId", "ProductVersion")
    VALUES ('20260929122820_TicketProductId', '8.0.10');
    END IF;
END $EF$;
COMMIT;

