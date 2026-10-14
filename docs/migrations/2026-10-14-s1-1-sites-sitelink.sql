START TRANSACTION;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261014080211_Outbox') THEN
    CREATE TABLE outbox_message (
        id uuid NOT NULL,
        kind character varying(100) NOT NULL,
        payload jsonb NOT NULL,
        idempotency_key character varying(200) NOT NULL,
        correlation_id character varying(64),
        created_at timestamp with time zone NOT NULL,
        available_at timestamp with time zone NOT NULL,
        attempts integer NOT NULL,
        last_error character varying(1000),
        processed_at timestamp with time zone,
        failed_at timestamp with time zone,
        resolved_at timestamp with time zone,
        resolved_by_staff_id uuid,
        resolution_note character varying(1000),
        CONSTRAINT pk_outbox_message PRIMARY KEY (id)
    );
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261014080211_Outbox') THEN
    CREATE INDEX ix_outbox_message_available_at ON outbox_message (available_at) WHERE processed_at IS NULL AND failed_at IS NULL;
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261014080211_Outbox') THEN
    CREATE UNIQUE INDEX ix_outbox_message_idempotency_key ON outbox_message (idempotency_key);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261014080211_Outbox') THEN
    INSERT INTO "__EFMigrationsHistory" (migration_id, product_version)
    VALUES ('20261014080211_Outbox', '10.0.11');
    END IF;
END $EF$;
COMMIT;

START TRANSACTION;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261014082332_Sites') THEN
    CREATE TABLE site (
        id uuid NOT NULL,
        location_code character varying(20) NOT NULL,
        sitelink_site_id integer,
        name character varying(200) NOT NULL,
        display_name character varying(200),
        description character varying(4000),
        hero_image_url character varying(1000),
        address1 character varying(300),
        city character varying(100),
        region character varying(100),
        postal_code character varying(20),
        country character(2) NOT NULL,
        phone character varying(50),
        latitude numeric(9,6),
        longitude numeric(9,6),
        time_zone character varying(64) NOT NULL,
        currency character(3) NOT NULL,
        tax_percentage numeric(5,2) NOT NULL,
        tax_label character varying(20) NOT NULL,
        facility_type character varying(20) NOT NULL,
        active boolean NOT NULL,
        stripe_account_id character varying(100),
        created_by_staff_id uuid,
        updated_by_staff_id uuid,
        created_at timestamp with time zone NOT NULL,
        updated_at timestamp with time zone NOT NULL,
        CONSTRAINT pk_site PRIMARY KEY (id),
        CONSTRAINT ck_site_country CHECK (country IN ('SG', 'MY', 'KR')),
        CONSTRAINT ck_site_country_currency CHECK ((country, currency) IN (('SG', 'SGD'), ('MY', 'MYR'), ('KR', 'KRW'))),
        CONSTRAINT ck_site_currency CHECK (currency IN ('SGD', 'MYR', 'KRW')),
        CONSTRAINT ck_site_tax_percentage CHECK (tax_percentage >= 0 AND tax_percentage <= 100)
    );
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261014082332_Sites') THEN
    CREATE TABLE storage_type (
        id uuid NOT NULL,
        key character varying(50) NOT NULL,
        name character varying(100) NOT NULL,
        display_name character varying(100),
        icon_path character varying(500),
        image_path character varying(500),
        sort_order integer NOT NULL,
        active boolean NOT NULL,
        created_by_staff_id uuid,
        updated_by_staff_id uuid,
        created_at timestamp with time zone NOT NULL,
        updated_at timestamp with time zone NOT NULL,
        CONSTRAINT pk_storage_type PRIMARY KEY (id)
    );
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261014082332_Sites') THEN
    CREATE TABLE unit_sync_state (
        site_id uuid NOT NULL,
        last_time_polled_ticks bigint,
        last_synced_at timestamp with time zone,
        last_attempt_at timestamp with time zone,
        last_error character varying(1000),
        CONSTRAINT pk_unit_sync_state PRIMARY KEY (site_id),
        CONSTRAINT fk_unit_sync_state_site_site_id FOREIGN KEY (site_id) REFERENCES site (id) ON DELETE CASCADE
    );
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261014082332_Sites') THEN
    CREATE TABLE unit_size (
        id uuid NOT NULL,
        key character varying(50) NOT NULL,
        label character varying(100) NOT NULL,
        display_name character varying(100),
        description character varying(1000),
        unit_group character varying(100),
        image_path character varying(500),
        min_area_sqft numeric(10,2),
        max_area_sqft numeric(10,2),
        sort_order integer NOT NULL,
        storage_type_id uuid,
        created_by_staff_id uuid,
        updated_by_staff_id uuid,
        created_at timestamp with time zone NOT NULL,
        updated_at timestamp with time zone NOT NULL,
        CONSTRAINT pk_unit_size PRIMARY KEY (id),
        CONSTRAINT ck_unit_size_range CHECK (min_area_sqft IS NULL OR max_area_sqft IS NULL OR min_area_sqft <= max_area_sqft),
        CONSTRAINT fk_unit_size_storage_type_storage_type_id FOREIGN KEY (storage_type_id) REFERENCES storage_type (id) ON DELETE RESTRICT
    );
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261014082332_Sites') THEN
    CREATE TABLE unit (
        id uuid NOT NULL,
        site_id uuid NOT NULL,
        sitelink_unit_id integer NOT NULL,
        sitelink_unit_type_id integer NOT NULL,
        unit_name character varying(100) NOT NULL,
        description character varying(1000),
        width numeric(10,2) NOT NULL,
        length numeric(10,2) NOT NULL,
        area_sqft numeric(12,2) NOT NULL,
        floor integer,
        climate boolean NOT NULL,
        inside boolean NOT NULL,
        power boolean NOT NULL,
        alarm boolean NOT NULL,
        ada boolean NOT NULL,
        mobile boolean NOT NULL,
        standard_rate numeric(12,2),
        web_rate numeric(12,2),
        board_rate numeric(12,2),
        push_rate numeric(12,2),
        preferred_rate numeric(12,2),
        standard_security_deposit numeric(12,2),
        rented boolean NOT NULL,
        rentable boolean NOT NULL,
        waiting_list_reserved boolean NOT NULL,
        deleted_at timestamp with time zone,
        available boolean GENERATED ALWAYS AS (rentable AND NOT rented AND NOT waiting_list_reserved AND deleted_at IS NULL) STORED NOT NULL,
        storage_type_id uuid,
        unit_size_id uuid,
        last_synced_at timestamp with time zone,
        created_at timestamp with time zone NOT NULL,
        updated_at timestamp with time zone NOT NULL,
        CONSTRAINT pk_unit PRIMARY KEY (id),
        CONSTRAINT fk_unit_site_site_id FOREIGN KEY (site_id) REFERENCES site (id) ON DELETE RESTRICT,
        CONSTRAINT fk_unit_storage_type_storage_type_id FOREIGN KEY (storage_type_id) REFERENCES storage_type (id) ON DELETE RESTRICT,
        CONSTRAINT fk_unit_unit_size_unit_size_id FOREIGN KEY (unit_size_id) REFERENCES unit_size (id) ON DELETE RESTRICT
    );
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261014082332_Sites') THEN
    INSERT INTO storage_type (id, active, created_at, created_by_staff_id, display_name, icon_path, image_path, key, name, sort_order, updated_at, updated_by_staff_id)
    VALUES ('0199e000-0000-7000-8000-000000000001', TRUE, TIMESTAMPTZ '2026-10-14T00:00:00Z', NULL, NULL, NULL, NULL, 'self-storage', 'Self Storage', 1, TIMESTAMPTZ '2026-10-14T00:00:00Z', NULL);
    INSERT INTO storage_type (id, active, created_at, created_by_staff_id, display_name, icon_path, image_path, key, name, sort_order, updated_at, updated_by_staff_id)
    VALUES ('0199e000-0000-7000-8000-000000000002', FALSE, TIMESTAMPTZ '2026-10-14T00:00:00Z', NULL, NULL, NULL, NULL, 'workspace', 'Workspace', 2, TIMESTAMPTZ '2026-10-14T00:00:00Z', NULL);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261014082332_Sites') THEN
    CREATE UNIQUE INDEX ix_site_location_code ON site (location_code);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261014082332_Sites') THEN
    CREATE UNIQUE INDEX ix_site_sitelink_site_id ON site (sitelink_site_id);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261014082332_Sites') THEN
    CREATE UNIQUE INDEX ix_storage_type_key ON storage_type (key);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261014082332_Sites') THEN
    CREATE UNIQUE INDEX ix_unit_site_id_sitelink_unit_id ON unit (site_id, sitelink_unit_id);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261014082332_Sites') THEN
    CREATE INDEX ix_unit_site_id_unit_name ON unit (site_id, unit_name);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261014082332_Sites') THEN
    CREATE INDEX ix_unit_storage_type_id ON unit (storage_type_id);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261014082332_Sites') THEN
    CREATE INDEX ix_unit_unit_size_id ON unit (unit_size_id);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261014082332_Sites') THEN
    CREATE UNIQUE INDEX ix_unit_size_key ON unit_size (key);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261014082332_Sites') THEN
    CREATE INDEX ix_unit_size_storage_type_id ON unit_size (storage_type_id);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261014082332_Sites') THEN
    INSERT INTO "__EFMigrationsHistory" (migration_id, product_version)
    VALUES ('20261014082332_Sites', '10.0.11');
    END IF;
END $EF$;
COMMIT;

START TRANSACTION;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261014083039_SiteLinkCallMonth') THEN
    CREATE TABLE sitelink_call_month (
        month date NOT NULL,
        operation character varying(100) NOT NULL,
        calls bigint NOT NULL,
        CONSTRAINT pk_sitelink_call_month PRIMARY KEY (month, operation)
    );
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261014083039_SiteLinkCallMonth') THEN
    INSERT INTO "__EFMigrationsHistory" (migration_id, product_version)
    VALUES ('20261014083039_SiteLinkCallMonth', '10.0.11');
    END IF;
END $EF$;
COMMIT;

