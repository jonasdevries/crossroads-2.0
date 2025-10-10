-- 20251007_initial_schema.sql
-- Crossroads: complete baseline + hardening from scratch
-- - Extensions
-- - Enums
-- - Reference tables (currencies, jurisdictions)
-- - Core tables (users, brokers, locations (accounts), assets, listings, asset_prices, fx_rates, transactions, cashflows)
-- - Constraints, indexes, triggers, views, helper functions

/* ---------------------------
   Extensions
---------------------------- */
CREATE EXTENSION IF NOT EXISTS pgcrypto            WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp"         WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements  WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_graphql          WITH SCHEMA graphql;
CREATE EXTENSION IF NOT EXISTS supabase_vault      WITH SCHEMA vault;

/* ---------------------------
   Enums
---------------------------- */
CREATE TYPE public.asset_type AS ENUM (
    'equity', 'etf', 'commodity', 'cash', 'crypto', 'bond', 'stock', 'fund', 'other'
    );

-- locations = bewaarplaatsen/accounts van de user
CREATE TYPE public.location_type AS ENUM (
    'vault', 'bank', 'broker', 'exchange', 'custom'
    );

-- Transacties (portefeuille-mutations)
CREATE TYPE public.txn_type AS ENUM (
    'buy', 'sell', 'transfer_in', 'transfer_out', 'dividend_reinvest'
    );

-- Cashflows (cash bewegingen/inkomsten/kosten)
CREATE TYPE public.cashflow_type AS ENUM (
    'deposit',
    'withdraw',
    'dividend',
    'coupon',
    'interest',
    'fee',
    'withholding_tax',
    'local_tax',
    'return_of_capital',
    'fx_in',
    'fx_out',
    'internal_transfer'
    );

/* ---------------------------
   Referentie: currencies & jurisdictions
---------------------------- */
CREATE TABLE public.currencies (
                                   code          CHAR(3) PRIMARY KEY,
                                   name          TEXT,
                                   numeric_code  CHAR(3),
                                   decimals      SMALLINT DEFAULT 2 CHECK (decimals BETWEEN 0 AND 6)
);

-- Jurisdicties/markten (bronlanden/marktcodes)
CREATE TABLE public.jurisdictions (
                                      id           BIGSERIAL PRIMARY KEY,
                                      country_code CHAR(2)  NOT NULL,  -- ISO 3166-1 alpha2
                                      name         TEXT     NOT NULL,
                                      mic          CHAR(4)           -- ISO 10383 (optioneel, voor markten)
);

-- Uniek per (country_code, mic), waarbij NULL mic = '' behandeld wordt
CREATE UNIQUE INDEX jurisdictions_country_mic_uidx
    ON public.jurisdictions (country_code, COALESCE(mic, ''));

/* ---------------------------
   Users
---------------------------- */
CREATE TABLE public.users (
                              id            BIGSERIAL PRIMARY KEY,
                              auth_id       UUID UNIQUE,  -- Supabase Auth koppeling (optioneel)
                              email         TEXT NOT NULL,
                              name          TEXT,
                              base_currency CHAR(3) NOT NULL DEFAULT 'EUR',
                              created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                              updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                              deleted_at    TIMESTAMPTZ
);

-- FK naar auth.users als die bestaat (in Supabase standaard aanwezig)
DO $$
    BEGIN
        IF TO_REGCLASS('auth.users') IS NOT NULL THEN
            ALTER TABLE public.users
                ADD CONSTRAINT users_auth_fk
                    FOREIGN KEY (auth_id) REFERENCES auth.users(id);
        END IF;
    END
$$;

ALTER TABLE public.users
    ADD CONSTRAINT users_base_ccy_chk
        CHECK (base_currency = UPPER(base_currency) AND LENGTH(base_currency) = 3);

ALTER TABLE public.users
    ADD CONSTRAINT users_base_ccy_fk
        FOREIGN KEY (base_currency) REFERENCES public.currencies(code);

CREATE UNIQUE INDEX users_email_uidx     ON public.users(LOWER(email));
CREATE INDEX        users_created_at_idx ON public.users(created_at DESC);

-- Triggers: updated_at + email normaliseren
CREATE OR REPLACE FUNCTION public.set_updated_at()
    RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.normalize_email()
    RETURNS TRIGGER AS $$
BEGIN
    IF NEW.email IS NOT NULL THEN
        NEW.email := LOWER(BTRIM(NEW.email));
    END IF;
    RETURN NEW;
END
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON public.users
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_users_normalize_email
    BEFORE INSERT OR UPDATE ON public.users
    FOR EACH ROW EXECUTE FUNCTION public.normalize_email();

/* ---------------------------
   Brokers
---------------------------- */
CREATE TABLE public.brokers (
                                id               BIGSERIAL PRIMARY KEY,
                                user_id          BIGINT NOT NULL REFERENCES public.users(id),
                                name             TEXT   NOT NULL,
                                country_code     CHAR(2),                         -- land van de broker
                                jurisdiction_id  BIGINT REFERENCES public.jurisdictions(id),
                                account_ccy      CHAR(3) NOT NULL DEFAULT 'EUR',
                                created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                                UNIQUE (user_id, name)
);

ALTER TABLE public.brokers
    ADD CONSTRAINT brokers_account_ccy_chk
        CHECK (account_ccy = UPPER(account_ccy) AND LENGTH(account_ccy) = 3);

ALTER TABLE public.brokers
    ADD CONSTRAINT brokers_account_ccy_fk
        FOREIGN KEY (account_ccy) REFERENCES public.currencies(code);

/* ---------------------------
   Locations (user-accounts/bewaarplaatsen)
---------------------------- */
CREATE TABLE public.locations (
                                  id            BIGSERIAL PRIMARY KEY,
                                  user_id       BIGINT NOT NULL REFERENCES public.users(id),
                                  broker_id     BIGINT REFERENCES public.brokers(id),
                                  name          TEXT   NOT NULL,
                                  type          public.location_type NOT NULL DEFAULT 'vault',
                                  base_currency CHAR(3),
                                  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 1) Als broker_id NIET NULL is: uniek per (user, broker, name)
CREATE UNIQUE INDEX locations_user_broker_name_uidx
    ON public.locations(user_id, broker_id, name)
    WHERE broker_id IS NOT NULL;

-- 2) Als broker_id NULL is: uniek per (user, name)
CREATE UNIQUE INDEX locations_user_name_nullbroker_uidx
    ON public.locations(user_id, name)
    WHERE broker_id IS NULL;

-- Case-insensitive varianten
CREATE UNIQUE INDEX locations_user_broker_name_ci_uidx
    ON public.locations(user_id, broker_id, LOWER(name))
    WHERE broker_id IS NOT NULL;

CREATE UNIQUE INDEX locations_user_name_nullbroker_ci_uidx
    ON public.locations(user_id, LOWER(name))
    WHERE broker_id IS NULL;

ALTER TABLE public.locations
    ADD CONSTRAINT locations_base_ccy_fk
        FOREIGN KEY (base_currency) REFERENCES public.currencies(code);

-- (optioneel) type-regel: broker-account vereist broker_id
ALTER TABLE public.locations
    ADD CONSTRAINT locations_type_rules_chk CHECK (
        (type <> 'broker') OR (type = 'broker' AND broker_id IS NOT NULL)
        );

-- locations: één naam per user (bv. 'jonasdevries')
ALTER TABLE public.locations
    ADD CONSTRAINT locations_user_name_key UNIQUE (user_id, name);

/* ---------------------------
   Assets & Listings
---------------------------- */
CREATE TABLE public.assets (
                               id                       BIGSERIAL PRIMARY KEY,
                               ticker                   TEXT,
                               name                     TEXT NOT NULL,
                               quote_ccy                CHAR(3) NOT NULL,
                               mic                      CHAR(4),                       -- primaire notering (optioneel)
                               unique_symbol            TEXT,                          -- bijv. ISIN+MIC of proprietary
                               type                     public.asset_type NOT NULL,
                               issuer_jurisdiction_id   BIGINT REFERENCES public.jurisdictions(id)
);

ALTER TABLE public.assets
    ADD CONSTRAINT assets_quote_ccy_chk
        CHECK (quote_ccy = UPPER(quote_ccy) AND LENGTH(quote_ccy) = 3);

ALTER TABLE public.assets
    ADD CONSTRAINT assets_unique_symbol_key UNIQUE (unique_symbol);

ALTER TABLE public.assets
    ADD CONSTRAINT assets_quote_ccy_fk
        FOREIGN KEY (quote_ccy) REFERENCES public.currencies(code);

CREATE UNIQUE INDEX assets_unique_symbol_uidx
    ON public.assets(unique_symbol) WHERE unique_symbol IS NOT NULL;

-- Multi-listing support
CREATE TABLE public.listings (
                                 id            BIGSERIAL PRIMARY KEY,
                                 asset_id      BIGINT NOT NULL REFERENCES public.assets(id),
                                 mic           CHAR(4) NOT NULL,
                                 ticker_local  TEXT,
                                 quote_ccy     CHAR(3) NOT NULL,
                                 UNIQUE (asset_id, mic)
);

ALTER TABLE public.listings
    ADD CONSTRAINT listings_quote_ccy_fk
        FOREIGN KEY (quote_ccy) REFERENCES public.currencies(code);

/* ---------------------------
   Asset Prices
---------------------------- */
CREATE TABLE public.asset_prices (
                                     asset_id  BIGINT NOT NULL REFERENCES public.assets(id),
                                     ts        TIMESTAMPTZ NOT NULL,
                                     price     NUMERIC(20,8) NOT NULL,
                                     PRIMARY KEY (asset_id, ts)
);

CREATE INDEX asset_prices_asset_ts_desc_idx
    ON public.asset_prices(asset_id, ts DESC);

/* ============================================================
   FX rates schema (from scratch) — no triggers, canonical storage
============================================================ */
-- 1) Basistabel (canonieke opslag)
CREATE TABLE IF NOT EXISTS public.fx_rates (
                                               ccy_from TEXT NOT NULL CHECK (ccy_from ~ '^[A-Z]{3}$'),
                                               ccy_to   TEXT NOT NULL CHECK (ccy_to   ~ '^[A-Z]{3}$'),
                                               ts       TIMESTAMPTZ NOT NULL,
                                               rate     NUMERIC(20,10) NOT NULL CHECK (rate > 0),
    -- geen zelf-paren
                                               CONSTRAINT fx_rates_ccy_diff_chk     CHECK (ccy_from <> ccy_to),
    -- canonieke orde afdwingen: kleinste alfabetisch links
                                               CONSTRAINT fx_rates_canonical_chk    CHECK (ccy_from < ccy_to),
    -- unieke sleutel per (paar, tijd)
                                               CONSTRAINT fx_rates_pk               PRIMARY KEY (ccy_from, ccy_to, ts)
);

-- 2) Indexen (PK dekt de meeste lookups; extra ts-index kan nuttig zijn)
CREATE INDEX IF NOT EXISTS fx_rates_ts_idx
    ON public.fx_rates (ts);

-- 3) Convenience upsert: accepteert elke volgorde, schrijft canoniek (met inversie indien nodig)
CREATE OR REPLACE FUNCTION public.fx_rates_upsert(
    p_from TEXT,
    p_to   TEXT,
    p_ts   TIMESTAMPTZ,
    p_rate NUMERIC
) RETURNS VOID
    LANGUAGE plpgsql
    SET search_path = public
AS $$
DECLARE
    f TEXT := LEAST(p_from, p_to);
    t TEXT := GREATEST(p_from, p_to);
    r NUMERIC := p_rate;
BEGIN
    -- Als input in niet-canonieke richting komt, sla inverse op
    IF p_from > p_to THEN
        r := 1 / r;
    END IF;

    INSERT INTO public.fx_rates (ccy_from, ccy_to, ts, rate)
    VALUES (f, t, p_ts, r)
    ON CONFLICT (ccy_from, ccy_to, ts)
        DO UPDATE SET rate = EXCLUDED.rate;
END
$$;

COMMENT ON FUNCTION public.fx_rates_upsert(TEXT, TEXT, TIMESTAMPTZ, NUMERIC)
    IS 'Upsert FX rate; normaliseert volgorde (LEAST/GREATEST) en invert bij niet-canonieke input. Slaat 1 rij per paar+ts op.';

-- 4) fx_convert: gebruikt canonieke opslag en berekent inverse on-the-fly; pivot optioneel
CREATE OR REPLACE FUNCTION public.fx_convert(
    p_amount NUMERIC,
    p_from   TEXT,
    p_to     TEXT,
    p_ts     TIMESTAMPTZ,
    p_pivot  TEXT DEFAULT NULL
) RETURNS NUMERIC
    LANGUAGE plpgsql
    SET search_path = public
AS $$
DECLARE
    a      TEXT := p_from;
    b      TEXT := p_to;
    r_pair NUMERIC;   -- rate voor (a,b) op ts (canoniek opgehaald)
    r_leg1 NUMERIC;   -- rate voor (from -> pivot)
    r_leg2 NUMERIC;   -- rate voor (pivot -> to)
BEGIN
    IF p_amount IS NULL THEN
        RAISE EXCEPTION 'Amount is NULL';
    END IF;

    IF a = b THEN
        RETURN p_amount;
    END IF;

    -- ===== Direct / inverse voor (from,to)
    SELECT rate INTO r_pair
    FROM public.fx_rates
    WHERE ccy_from = LEAST(a, b)
      AND ccy_to   = GREATEST(a, b)
      AND ts       = p_ts;

    IF r_pair IS NOT NULL THEN
        IF a < b THEN
            -- richting in opslag is a->b (zelfde als from->to)
            RETURN p_amount * r_pair;
        ELSE
            -- richting in opslag is b->a; inverse toepassen
            RETURN p_amount * (1 / r_pair);
        END IF;
    END IF;

    -- ===== Pivot path (optioneel)
    IF p_pivot IS NOT NULL THEN
        -- been 1: from -> pivot
        SELECT rate INTO r_leg1
        FROM public.fx_rates
        WHERE ccy_from = LEAST(p_from, p_pivot)
          AND ccy_to   = GREATEST(p_from, p_pivot)
          AND ts       = p_ts;

        IF r_leg1 IS NOT NULL THEN
            IF p_from > p_pivot THEN
                r_leg1 := 1 / r_leg1; -- opgeslagen als pivot->from, wij willen from->pivot
            END IF;
        END IF;

        -- been 2: pivot -> to
        SELECT rate INTO r_leg2
        FROM public.fx_rates
        WHERE ccy_from = LEAST(p_pivot, p_to)
          AND ccy_to   = GREATEST(p_pivot, p_to)
          AND ts       = p_ts;

        IF r_leg2 IS NOT NULL THEN
            IF p_pivot > p_to THEN
                r_leg2 := 1 / r_leg2; -- opgeslagen als to->pivot, wij willen pivot->to
            END IF;
        END IF;

        IF r_leg1 IS NOT NULL AND r_leg2 IS NOT NULL THEN
            RETURN p_amount * r_leg1 * r_leg2;
        END IF;
    END IF;

    RAISE EXCEPTION 'FX missing: %->% at % (pivot=%)', p_from, p_to, p_ts, COALESCE(p_pivot, '∅');
END
$$;

COMMENT ON FUNCTION public.fx_convert(NUMERIC, TEXT, TEXT, TIMESTAMPTZ, TEXT)
    IS 'Converteert bedrag op ts. Gebruikt canonieke opslag (ccy_from<ccy_to), inverse on-the-fly en optionele pivot.';

-- 5) Views: "latest" per paar (canoniek) en "expanded" (beide richtingen zichtbaar)
-- 5.1: nieuwste rij per canoniek paar
CREATE OR REPLACE VIEW public.fx_rates_latest_unordered AS
WITH latest AS (
    SELECT ccy_from, ccy_to, MAX(ts) AS ts
    FROM public.fx_rates
    GROUP BY ccy_from, ccy_to
)
SELECT r.ccy_from, r.ccy_to, r.ts, r.rate
FROM latest l
         JOIN public.fx_rates r
              ON r.ccy_from = l.ccy_from
                  AND r.ccy_to   = l.ccy_to
                  AND r.ts       = l.ts;

COMMENT ON VIEW public.fx_rates_latest_unordered
    IS 'Laatste koersen per canoniek paar (ccy_from<ccy_to).';

-- 5.2: expanded: toont beide richtingen zonder inverse fysiek op te slaan
CREATE OR REPLACE VIEW public.fx_rates_latest_expanded AS
SELECT ccy_from, ccy_to, ts, rate
FROM public.fx_rates_latest_unordered
UNION ALL
SELECT ccy_to AS ccy_from, ccy_from AS ccy_to, ts, (1 / rate) AS rate
FROM public.fx_rates_latest_unordered;

COMMENT ON VIEW public.fx_rates_latest_expanded
    IS 'Laatste koersen in beide richtingen; inverse wordt afgeleid als 1/rate.';

/* ============================================================
   Gebruikstips:
   - Schrijf met:  SELECT public.fx_rates_upsert('EUR','USD','2024-10-02T00:00Z',1.25);
   - Lees/latest (canoniek):            SELECT * FROM public.fx_rates_latest_unordered;
   - Lees/latest (beide richtingen):    SELECT * FROM public.fx_rates_latest_expanded;
   - Converteer: SELECT public.fx_convert(100,'EUR','USD','2024-10-02T00:00Z','EUR');
============================================================ */

/* ---------------------------
   Transactions
---------------------------- */
CREATE TABLE public.transactions (
                                     id               BIGSERIAL PRIMARY KEY,
                                     user_id          BIGINT NOT NULL REFERENCES public.users(id),
                                     broker_id        BIGINT NOT NULL REFERENCES public.brokers(id),
                                     location_id      BIGINT REFERENCES public.locations(id), -- account/bewaarplaats
                                     asset_id         BIGINT NOT NULL REFERENCES public.assets(id),
                                     listing_id       BIGINT REFERENCES public.listings(id),
                                     type             public.txn_type NOT NULL,
                                     quantity         NUMERIC(20,8) NOT NULL,
                                     price            NUMERIC(20,8) NOT NULL,                 -- in listing.quote_ccy of asset.quote_ccy
                                     fee_amount       NUMERIC(20,8) NOT NULL DEFAULT 0,
                                     fee_currency     CHAR(3),
                                     traded_at        TIMESTAMPTZ NOT NULL,
                                     note             TEXT
);

-- Basischecks
ALTER TABLE public.transactions
    ADD CONSTRAINT txn_qty_nonzero_chk CHECK (quantity <> 0),
    ADD CONSTRAINT txn_price_pos_chk    CHECK (price >= 0),
    ADD CONSTRAINT txn_fee_currency_chk CHECK (
        (fee_amount = 0 AND fee_currency IS NULL)
            OR
        (fee_amount > 0 AND fee_currency IS NOT NULL AND fee_currency = UPPER(fee_currency) AND LENGTH(fee_currency) = 3)
        );

-- Overweeg een CHECK zodat 0 alleen bij transfer_in kan
ALTER TABLE public.transactions
    ADD CONSTRAINT tx_price_semantics_chk CHECK (
        (type = 'transfer_in' AND price >= 0)
            OR
        (type IN ('buy','sell') AND price > 0)
        );

-- Listing moet bij hetzelfde asset horen
CREATE OR REPLACE FUNCTION public.txn_check_listing_asset()
    RETURNS TRIGGER AS $$
DECLARE
    l_asset BIGINT;
BEGIN
    IF NEW.listing_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT asset_id INTO l_asset
    FROM public.listings
    WHERE id = NEW.listing_id;

    IF l_asset IS NULL THEN
        RAISE EXCEPTION 'Listing % not found', NEW.listing_id;
    END IF;

    IF l_asset <> NEW.asset_id THEN
        RAISE EXCEPTION 'transactions.asset_id (%) != listings.asset_id (%)', NEW.asset_id, l_asset;
    END IF;

    RETURN NEW;
END
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_txn_check_listing_asset
    BEFORE INSERT OR UPDATE ON public.transactions
    FOR EACH ROW EXECUTE FUNCTION public.txn_check_listing_asset();

-- Consistentie: location ↔ user/broker
CREATE OR REPLACE FUNCTION public.txn_check_location_consistency()
    RETURNS TRIGGER AS $$
DECLARE
    loc_user   BIGINT;
    loc_broker BIGINT;
BEGIN
    IF NEW.location_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT user_id, broker_id
    INTO loc_user, loc_broker
    FROM public.locations
    WHERE id = NEW.location_id;

    IF loc_user IS NULL THEN
        RAISE EXCEPTION 'Location % bestaat niet', NEW.location_id;
    END IF;

    IF loc_user <> NEW.user_id THEN
        RAISE EXCEPTION 'Location.user_id (%) != Transaction.user_id (%)', loc_user, NEW.user_id;
    END IF;

    IF loc_broker IS NOT NULL AND loc_broker <> NEW.broker_id THEN
        RAISE EXCEPTION 'Location.broker_id (%) != Transaction.broker_id (%)', loc_broker, NEW.broker_id;
    END IF;

    RETURN NEW;
END
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_txn_check_location
    BEFORE INSERT OR UPDATE ON public.transactions
    FOR EACH ROW EXECUTE FUNCTION public.txn_check_location_consistency();

-- Handige indexen
CREATE INDEX txn_user_time_idx   ON public.transactions(user_id,  traded_at DESC);
CREATE INDEX txn_asset_time_idx  ON public.transactions(asset_id, traded_at DESC);
CREATE INDEX txn_broker_time_idx ON public.transactions(broker_id, traded_at DESC);
CREATE INDEX txn_loc_time_idx    ON public.transactions(location_id, traded_at DESC);
CREATE INDEX txn_type_time_idx   ON public.transactions(type,     traded_at DESC);

/* ---------------------------
   Cashflows
---------------------------- */
CREATE TABLE public.cashflows (
                                  id                   BIGSERIAL PRIMARY KEY,
                                  user_id              BIGINT NOT NULL REFERENCES public.users(id),
                                  broker_id            BIGINT REFERENCES public.brokers(id),
                                  account_location_id  BIGINT REFERENCES public.locations(id),  -- bewaarplaats (optioneel)
                                  asset_id             BIGINT REFERENCES public.assets(id),     -- bijv. dividend/coupon
                                  jurisdiction_id      BIGINT REFERENCES public.jurisdictions(id),  -- bron/jurisdictie
                                  type                 public.cashflow_type NOT NULL,
                                  amount               NUMERIC(20,8) NOT NULL,
                                  currency             CHAR(3) NOT NULL,
                                  occurred_at          TIMESTAMPTZ NOT NULL,
                                  note                 TEXT,
);

ALTER TABLE public.cashflows
    ADD CONSTRAINT cashflows_ccy_chk
        CHECK (currency = UPPER(currency) AND LENGTH(currency) = 3);

ALTER TABLE public.cashflows
    ADD CONSTRAINT cashflows_currency_fk
        FOREIGN KEY (currency) REFERENCES public.currencies(code);

-- Type-geleide minimale regels (licht, niet te streng)
ALTER TABLE public.cashflows
    ADD CONSTRAINT cashflows_type_min_rules_chk CHECK (
        -- asset-gedreven inkomsten
        (type IN ('dividend','coupon','return_of_capital','withholding_tax','local_tax') AND asset_id IS NOT NULL)
            OR
            -- broker/account-gedreven fees/interest
        (type IN ('fee','interest') AND (broker_id IS NOT NULL OR account_location_id IS NOT NULL))
            OR
            -- stortingen/opnames/FX/transfer
        (type IN ('deposit','withdraw','fx_in','fx_out','internal_transfer'))
        );

CREATE INDEX cashflows_user_time_idx  ON public.cashflows(user_id,         occurred_at DESC);
CREATE INDEX cashflows_type_time_idx  ON public.cashflows(type,            occurred_at DESC);
CREATE INDEX cashflows_asset_time_idx ON public.cashflows(asset_id,        occurred_at DESC);
CREATE INDEX cashflows_juris_time_idx ON public.cashflows(jurisdiction_id, occurred_at DESC);

/* ---------------------------
   Extra: views voor rapportering
---------------------------- */
-- Laatste prijs per asset
CREATE OR REPLACE VIEW public.asset_prices_latest AS
SELECT DISTINCT ON (asset_id)
    asset_id, ts, price
FROM public.asset_prices
ORDER BY asset_id, ts DESC;

COMMIT;
