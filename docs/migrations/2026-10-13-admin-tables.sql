START TRANSACTION;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261013092140_AdminTables') THEN
    CREATE TABLE role (
        id uuid NOT NULL,
        name character varying(100) NOT NULL,
        permissions text[] NOT NULL,
        is_system boolean NOT NULL,
        created_by_staff_id uuid,
        updated_by_staff_id uuid,
        created_at timestamp with time zone NOT NULL,
        updated_at timestamp with time zone NOT NULL,
        CONSTRAINT pk_role PRIMARY KEY (id)
    );
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261013092140_AdminTables') THEN
    CREATE UNIQUE INDEX ix_role_name_lower ON role (lower(name));
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261013092140_AdminTables') THEN
    CREATE TABLE staff_user (
        id uuid NOT NULL,
        email character varying(254) NOT NULL,
        display_name character varying(200),
        entra_object_id character varying(64),
        role_id uuid NOT NULL,
        active boolean NOT NULL,
        last_sign_in_at timestamp with time zone,
        created_by_staff_id uuid,
        updated_by_staff_id uuid,
        created_at timestamp with time zone NOT NULL,
        updated_at timestamp with time zone NOT NULL,
        CONSTRAINT pk_staff_user PRIMARY KEY (id),
        CONSTRAINT fk_staff_user_role_role_id FOREIGN KEY (role_id) REFERENCES role (id) ON DELETE RESTRICT
    );
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261013092140_AdminTables') THEN
    CREATE TABLE audit_log (
        id uuid NOT NULL,
        staff_user_id uuid NOT NULL,
        action character varying(200) NOT NULL,
        entity_type character varying(100) NOT NULL,
        entity_id uuid NOT NULL,
        changes jsonb NOT NULL,
        ip inet,
        occurred_at timestamp with time zone NOT NULL,
        CONSTRAINT pk_audit_log PRIMARY KEY (id),
        CONSTRAINT fk_audit_log_staff_user_staff_user_id FOREIGN KEY (staff_user_id) REFERENCES staff_user (id) ON DELETE RESTRICT
    );
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261013092140_AdminTables') THEN
    INSERT INTO role (id, created_at, created_by_staff_id, is_system, name, permissions, updated_at, updated_by_staff_id)
    VALUES ('0199dd00-0000-7000-8000-000000000001', TIMESTAMPTZ '2026-10-13T00:00:00Z', NULL, TRUE, 'Owner', ARRAY[]::text[], TIMESTAMPTZ '2026-10-13T00:00:00Z', NULL);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261013092140_AdminTables') THEN
    CREATE INDEX ix_audit_log_entity_type_entity_id ON audit_log (entity_type, entity_id);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261013092140_AdminTables') THEN
    CREATE INDEX ix_audit_log_occurred_at ON audit_log (occurred_at DESC);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261013092140_AdminTables') THEN
    CREATE INDEX ix_audit_log_staff_user_id ON audit_log (staff_user_id);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261013092140_AdminTables') THEN
    CREATE UNIQUE INDEX ix_staff_user_email ON staff_user (email);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261013092140_AdminTables') THEN
    CREATE UNIQUE INDEX ix_staff_user_entra_object_id ON staff_user (entra_object_id);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261013092140_AdminTables') THEN
    CREATE INDEX ix_staff_user_role_id ON staff_user (role_id);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261013092140_AdminTables') THEN
    INSERT INTO "__EFMigrationsHistory" (migration_id, product_version)
    VALUES ('20261013092140_AdminTables', '10.0.11');
    END IF;
END $EF$;
COMMIT;

