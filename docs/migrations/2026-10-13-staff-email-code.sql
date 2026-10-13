START TRANSACTION;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261013113853_StaffEmailCode') THEN
    ALTER TABLE customer_login_code RENAME TO login_code;
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261013113853_StaffEmailCode') THEN
    ALTER TABLE login_code RENAME CONSTRAINT pk_customer_login_code TO pk_login_code;
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261013113853_StaffEmailCode') THEN
    ALTER INDEX ix_customer_login_code_expires_at RENAME TO ix_login_code_expires_at;
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261013113853_StaffEmailCode') THEN
    DROP INDEX ix_customer_login_code_email;
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261013113853_StaffEmailCode') THEN
    ALTER TABLE login_code ADD purpose character varying(20) NOT NULL DEFAULT 'Customer';
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261013113853_StaffEmailCode') THEN
    ALTER TABLE login_code ALTER COLUMN purpose DROP DEFAULT;
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261013113853_StaffEmailCode') THEN
    CREATE UNIQUE INDEX ix_login_code_purpose_email ON login_code (purpose, email);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261013113853_StaffEmailCode') THEN
    INSERT INTO "__EFMigrationsHistory" (migration_id, product_version)
    VALUES ('20261013113853_StaffEmailCode', '10.0.11');
    END IF;
END $EF$;
COMMIT;

START TRANSACTION;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261013114525_DropEntraObjectId') THEN
    DROP INDEX ix_staff_user_entra_object_id;
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261013114525_DropEntraObjectId') THEN
    ALTER TABLE staff_user DROP COLUMN entra_object_id;
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261013114525_DropEntraObjectId') THEN
    INSERT INTO "__EFMigrationsHistory" (migration_id, product_version)
    VALUES ('20261013114525_DropEntraObjectId', '10.0.11');
    END IF;
END $EF$; 
COMMIT;

