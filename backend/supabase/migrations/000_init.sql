-- 20251007_initial_schema.sql
-- Crossroads: complete baseline + hardening from scratch
-- - Extensions
-- - Enums
-- - Reference tables (currencies, jurisdictions)
-- - Core tables (users, brokers, locations (accounts), assets, listings, asset_prices, fx_rates, transactions, cashflows)
-- - Constraints, indexes, triggers, views, helper functions

---------------------------
-- Extensions
---------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto    WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_graphql  WITH SCHEMA graphql;
CREATE EXTENSION IF NOT EXISTS supabase_vault WITH SCHEMA vault;

---------------------------
-- Enums
---------------------------
CREATE TYPE public.asset_type AS ENUM (
    'equity','etf','commodity','cash','crypto','bond','stock','fund','other'
    );

-- locations = bewaarplaatsen/accounts van de user
CREATE TYPE public.location_type AS ENUM (
    'vault','bank','broker','exchange','custom'
    );

-- Transacties (portefeuille-mutations)
CREATE TYPE public.txn_type AS ENUM (
    'buy','sell','transfer_in','transfer_out','dividend_reinvest'
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

---------------------------
-- Referentie: currencies & jurisdictions
---------------------------
CREATE TABLE public.currencies (
                                   code char(3) PRIMARY KEY,
                                   name text,
                                   numeric_code char(3),
                                   decimals smallint DEFAULT 2 CHECK (decimals BETWEEN 0 AND 6)
);




-- Jurisdicties/markten (bronlanden/marktcodes)
CREATE TABLE public.jurisdictions (
                                      id bigserial PRIMARY KEY,
                                      country_code char(2) NOT NULL,  -- ISO 3166-1 alpha2
                                      name text NOT NULL,
                                      mic char(4)                     -- ISO 10383 (optioneel, voor markten)
);

-- Uniek per (country_code, mic), waarbij NULL mic = '' behandeld wordt
CREATE UNIQUE INDEX jurisdictions_country_mic_uidx
    ON public.jurisdictions (country_code, COALESCE(mic, ''));



---------------------------
-- Users
---------------------------
CREATE TABLE public.users (
                              id           bigserial PRIMARY KEY,
                              auth_id      uuid UNIQUE,  -- Supabase Auth koppeling (optioneel)
                              email        text NOT NULL,
                              name         text,
                              base_currency char(3) NOT NULL DEFAULT 'EUR',
                              created_at   timestamptz NOT NULL DEFAULT now(),
                              updated_at   timestamptz NOT NULL DEFAULT now(),
                              deleted_at   timestamptz
);

-- FK naar auth.users als die bestaat (in Supabase standaard aanwezig)
DO $$
    BEGIN
        IF to_regclass('auth.users') IS NOT NULL THEN
            ALTER TABLE public.users
                ADD CONSTRAINT users_auth_fk
                    FOREIGN KEY (auth_id) REFERENCES auth.users(id);
        END IF;
    END$$;

ALTER TABLE public.users
    ADD CONSTRAINT users_base_ccy_chk
        CHECK (base_currency = UPPER(base_currency) AND length(base_currency)=3);

ALTER TABLE public.users
    ADD CONSTRAINT users_base_ccy_fk
        FOREIGN KEY (base_currency) REFERENCES public.currencies(code);

CREATE UNIQUE INDEX users_email_uidx ON public.users(lower(email));
CREATE INDEX users_created_at_idx ON public.users(created_at DESC);

-- Triggers: updated_at + email normaliseren
CREATE OR REPLACE FUNCTION public.set_updated_at()
    RETURNS trigger AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.normalize_email()
    RETURNS trigger AS $$
BEGIN
    IF NEW.email IS NOT NULL THEN
        NEW.email := lower(btrim(NEW.email));
    END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON public.users
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_users_normalize_email
    BEFORE INSERT OR UPDATE ON public.users
    FOR EACH ROW EXECUTE FUNCTION public.normalize_email();

---------------------------
-- Brokers
---------------------------
CREATE TABLE public.brokers (
                                id            bigserial PRIMARY KEY,
                                user_id       bigint NOT NULL REFERENCES public.users(id),
                                name          text   NOT NULL,
                                country_code  char(2),                 -- land van de broker
                                jurisdiction_id bigint REFERENCES public.jurisdictions(id),
                                account_ccy   char(3) NOT NULL DEFAULT 'EUR',
                                created_at    timestamptz NOT NULL DEFAULT now(),
                                UNIQUE (user_id, name)
);

ALTER TABLE public.brokers
    ADD CONSTRAINT brokers_account_ccy_chk
        CHECK (account_ccy = UPPER(account_ccy) AND length(account_ccy)=3);

ALTER TABLE public.brokers
    ADD CONSTRAINT brokers_account_ccy_fk
        FOREIGN KEY (account_ccy) REFERENCES public.currencies(code);

---------------------------
-- Locations (user-accounts/bewaarplaatsen)
---------------------------
CREATE TABLE public.locations (
                                  id          bigserial PRIMARY KEY,
                                  user_id     bigint NOT NULL REFERENCES public.users(id),
                                  broker_id   bigint REFERENCES public.brokers(id),
                                  name        text NOT NULL,
                                  type        public.location_type NOT NULL DEFAULT 'vault',
                                  base_currency char(3),
                                  created_at  timestamptz NOT NULL DEFAULT now()
);

-- 1) Als broker_id NIET NULL is: uniek per (user, broker, name)
CREATE UNIQUE INDEX locations_user_broker_name_uidx
    ON public.locations(user_id, broker_id, name)
    WHERE broker_id IS NOT NULL;

-- 2) Als broker_id NULL is: uniek per (user, name)
CREATE UNIQUE INDEX locations_user_name_nullbroker_uidx
    ON public.locations(user_id, name)
    WHERE broker_id IS NULL;

-- combineer met Optie A:
CREATE UNIQUE INDEX locations_user_broker_name_ci_uidx
    ON public.locations(user_id, broker_id, lower(name))
    WHERE broker_id IS NOT NULL;

CREATE UNIQUE INDEX locations_user_name_nullbroker_ci_uidx
    ON public.locations(user_id, lower(name))
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


---------------------------
-- Assets & Listings
---------------------------
CREATE TABLE public.assets (
                               id          bigserial PRIMARY KEY,
                               ticker      text,
                               name        text NOT NULL,
                               quote_ccy   char(3) NOT NULL,
                               mic         char(4),                 -- primaire notering (optioneel)
                               unique_symbol text,                  -- bijv. ISIN+MIC of proprietary
                               type        public.asset_type NOT NULL,
                               issuer_jurisdiction_id bigint REFERENCES public.jurisdictions(id)
);

ALTER TABLE public.assets
    ADD CONSTRAINT assets_quote_ccy_chk
        CHECK (quote_ccy = UPPER(quote_ccy) AND length(quote_ccy)=3);

-- Unieke constraint
ALTER TABLE public.assets
    ADD CONSTRAINT assets_unique_symbol_key UNIQUE (unique_symbol);

ALTER TABLE public.assets
    ADD CONSTRAINT assets_quote_ccy_fk
        FOREIGN KEY (quote_ccy) REFERENCES public.currencies(code);

CREATE UNIQUE INDEX assets_unique_symbol_uidx
    ON public.assets(unique_symbol) WHERE unique_symbol IS NOT NULL;

-- Multi-listing support
CREATE TABLE public.listings (
                                 id         bigserial PRIMARY KEY,
                                 asset_id   bigint NOT NULL REFERENCES public.assets(id),
                                 mic        char(4) NOT NULL,
                                 ticker_local text,
                                 quote_ccy  char(3) NOT NULL,
                                 UNIQUE (asset_id, mic)
);

ALTER TABLE public.listings
    ADD CONSTRAINT listings_quote_ccy_fk
        FOREIGN KEY (quote_ccy) REFERENCES public.currencies(code);

---------------------------
-- Asset Prices
---------------------------
CREATE TABLE public.asset_prices (
                                     asset_id  bigint NOT NULL REFERENCES public.assets(id),
                                     ts        timestamptz NOT NULL,
                                     price     numeric(20,8) NOT NULL,
                                     PRIMARY KEY (asset_id, ts)
);

CREATE INDEX asset_prices_asset_ts_desc_idx
    ON public.asset_prices(asset_id, ts DESC);


-- ============================================================
-- FX rates schema (from scratch) — no triggers, canonical storage
-- ============================================================

-- 1) Basistabel (canonieke opslag)
create table if not exists public.fx_rates (
                                               ccy_from text not null check (ccy_from ~ '^[A-Z]{3}$'),
                                               ccy_to   text not null check (ccy_to   ~ '^[A-Z]{3}$'),
                                               ts       timestamptz not null,
                                               rate     numeric(20,10) not null check (rate > 0),
    -- geen zelf-paren
                                               constraint fx_rates_ccy_diff_chk check (ccy_from <> ccy_to),
    -- canonieke orde afdwingen: kleinste alfabetisch links
                                               constraint fx_rates_canonical_chk check (ccy_from < ccy_to),
    -- unieke sleutel per (paar, tijd)
                                               constraint fx_rates_pk primary key (ccy_from, ccy_to, ts)
);

-- 2) Indexen (PK dekt de meeste lookups; extra ts-index kan nuttig zijn)
create index if not exists fx_rates_ts_idx on public.fx_rates (ts);

-- 3) Convenience upsert: accepteert elke volgorde, schrijft canoniek
--    (Geen triggers nodig; gebruik deze functie vanuit je app/tests.)
-- Replace fx_rates_upsert to invert when normalizing to canonical order
create or replace function public.fx_rates_upsert(
    p_from text,
    p_to   text,
    p_ts   timestamptz,
    p_rate numeric
) returns void
    language plpgsql
    set search_path = public
as $$
declare
    f text := least(p_from, p_to);
    t text := greatest(p_from, p_to);
    r numeric := p_rate;
begin
    -- If input is provided as the non-canonical direction, store the inverse
    if p_from > p_to then
        r := 1 / r;
    end if;

    insert into public.fx_rates (ccy_from, ccy_to, ts, rate)
    values (f, t, p_ts, r)
    on conflict (ccy_from, ccy_to, ts)
        do update set rate = excluded.rate;
end;
$$;


comment on function public.fx_rates_upsert(text,text,timestamptz,numeric)
    is 'Upsert FX rate; normaliseert volgorde met LEAST/GREATEST en bewaart 1 rij per paar+ts.';

-- 4) fx_convert: gebruikt canonieke opslag en berekent inverse on-the-fly
--    p_pivot is optioneel; bij pivot worden beide benen analoog behandeld.
create or replace function public.fx_convert(
    p_amount numeric,
    p_from   text,
    p_to     text,
    p_ts     timestamptz,
    p_pivot  text default null
) returns numeric
    language plpgsql
    set search_path = public
as $$
declare
    -- helpers om canoniek op te vragen
    a text := p_from;
    b text := p_to;

    r_pair numeric;   -- rate voor (a,b) op ts (canoniek opgehaald)
    r_leg1 numeric;   -- rate voor (from -> pivot)
    r_leg2 numeric;   -- rate voor (pivot -> to)
begin
    if p_amount is null then
        raise exception 'Amount is NULL';
    end if;

    if a = b then
        return p_amount;
    end if;

    -- ===== Direct / inverse voor (from,to)
    select rate into r_pair
    from public.fx_rates
    where ccy_from = least(a,b)
      and ccy_to   = greatest(a,b)
      and ts       = p_ts;

    if r_pair is not null then
        if a < b then
            -- richting in opslag is a->b (zelfde als from->to)
            return p_amount * r_pair;
        else
            -- richting in opslag is b->a; inverse toepassen
            return p_amount * (1 / r_pair);
        end if;
    end if;

    -- ===== Pivot path (optioneel)
    if p_pivot is not null then
        -- been 1: from -> pivot
        select rate into r_leg1
        from public.fx_rates
        where ccy_from = least(p_from, p_pivot)
          and ccy_to   = greatest(p_from, p_pivot)
          and ts       = p_ts;

        if r_leg1 is not null then
            if p_from > p_pivot then
                r_leg1 := 1 / r_leg1; -- opgeslagen als pivot->from, wij willen from->pivot
            end if;
        end if;

        -- been 2: pivot -> to
        select rate into r_leg2
        from public.fx_rates
        where ccy_from = least(p_pivot, p_to)
          and ccy_to   = greatest(p_pivot, p_to)
          and ts       = p_ts;

        if r_leg2 is not null then
            if p_pivot > p_to then
                r_leg2 := 1 / r_leg2; -- opgeslagen als to->pivot, wij willen pivot->to
            end if;
        end if;

        if r_leg1 is not null and r_leg2 is not null then
            return p_amount * r_leg1 * r_leg2;
        end if;
    end if;

    raise exception 'FX missing: %->% at % (pivot=%)', p_from, p_to, p_ts, coalesce(p_pivot,'∅');
end;
$$;

comment on function public.fx_convert(numeric,text,text,timestamptz,text)
    is 'Converteert bedrag op ts. Gebruikt canonieke opslag (ccy_from<ccy_to), inverse on-the-fly en optionele pivot.';

-- 5) Views: "latest" per paar (canoniek) en "expanded" (beide richtingen zichtbaar)

-- 5.1: nieuwste rij per canoniek paar
create or replace view public.fx_rates_latest_unordered as
with latest as (
    select ccy_from, ccy_to, max(ts) as ts
    from public.fx_rates
    group by ccy_from, ccy_to
)
select r.ccy_from, r.ccy_to, r.ts, r.rate
from latest l
         join public.fx_rates r
              on r.ccy_from = l.ccy_from
                  and r.ccy_to   = l.ccy_to
                  and r.ts       = l.ts;

comment on view public.fx_rates_latest_unordered
    is 'Laatste koersen per canoniek paar (ccy_from<ccy_to).';

-- 5.2: expanded: toont beide richtingen zonder inverse fysiek op te slaan
create or replace view public.fx_rates_latest_expanded as
select ccy_from, ccy_to, ts, rate
from public.fx_rates_latest_unordered
union all
select ccy_to as ccy_from, ccy_from as ccy_to, ts, (1/rate) as rate
from public.fx_rates_latest_unordered;

comment on view public.fx_rates_latest_expanded
    is 'Laatste koersen in beide richtingen; inverse wordt afgeleid als 1/rate.';

-- ============================================================
-- Gebruikstips:
-- - Schrijf met: select public.fx_rates_upsert('EUR','USD', '2024-10-02T00:00Z', 1.25);
-- - Lees/latest (canoniek): select * from public.fx_rates_latest_unordered;
-- - Lees/latest (beide richtingen): select * from public.fx_rates_latest_expanded;
-- - Converteer: select public.fx_convert(100, 'EUR','USD', '2024-10-02T00:00Z', 'EUR');
-- ============================================================




---------------------------
-- Transactions
---------------------------
CREATE TABLE public.transactions (
                                     id            bigserial PRIMARY KEY,
                                     user_id       bigint NOT NULL REFERENCES public.users(id),
                                     broker_id     bigint NOT NULL REFERENCES public.brokers(id),
                                     location_id   bigint REFERENCES public.locations(id), -- account/bewaarplaats
                                     asset_id      bigint NOT NULL REFERENCES public.assets(id),
                                     listing_id    bigint REFERENCES public.listings(id),
                                     type          public.txn_type NOT NULL,
                                     quantity      numeric(20,8) NOT NULL,
                                     price         numeric(20,8)  NOT NULL,              -- in listing.quote_ccy of asset.quote_ccy
                                     fee_amount    numeric(20,8)  NOT NULL DEFAULT 0,
                                     fee_currency  char(3),
                                     traded_at     timestamptz NOT NULL,
                                     note          text
);

-- Basischecks
ALTER TABLE public.transactions
    ADD CONSTRAINT txn_qty_nonzero_chk CHECK (quantity <> 0),
    ADD CONSTRAINT txn_price_pos_chk    CHECK (price >= 0),
    ADD CONSTRAINT txn_fee_currency_chk CHECK (
        (fee_amount = 0 AND fee_currency IS NULL)
            OR
        (fee_amount > 0 AND fee_currency IS NOT NULL AND fee_currency = UPPER(fee_currency) AND length(fee_currency)=3)
        );

-- Overweeg een CHECK zodat 0 alleen bij transfer_in kan
ALTER TABLE public.transactions
    ADD CONSTRAINT tx_price_semantics_chk
        CHECK (
            (type = 'transfer_in' AND price >= 0)
                OR (type IN ('buy','sell') AND price > 0)
            );

-- transactions: gebruik een externe id om idempotent te seeden
ALTER TABLE public.transactions
    ADD COLUMN IF NOT EXISTS ext_id text,
    ADD CONSTRAINT transactions_ext_id_key UNIQUE (ext_id);


-- Listing moet bij hetzelfde asset horen
CREATE OR REPLACE FUNCTION public.txn_check_listing_asset()
    RETURNS trigger AS $$
DECLARE l_asset bigint;
BEGIN
    IF NEW.listing_id IS NULL THEN RETURN NEW; END IF;
    SELECT asset_id INTO l_asset FROM public.listings WHERE id = NEW.listing_id;
    IF l_asset IS NULL THEN
        RAISE EXCEPTION 'Listing % not found', NEW.listing_id;
    END IF;
    IF l_asset <> NEW.asset_id THEN
        RAISE EXCEPTION 'transactions.asset_id (%) != listings.asset_id (%)', NEW.asset_id, l_asset;
    END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_txn_check_listing_asset
    BEFORE INSERT OR UPDATE ON public.transactions
    FOR EACH ROW EXECUTE FUNCTION public.txn_check_listing_asset();

-- Consistentie: location ↔ user/broker
CREATE OR REPLACE FUNCTION public.txn_check_location_consistency()
    RETURNS trigger AS $$
DECLARE
    loc_user   bigint;
    loc_broker bigint;
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
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_txn_check_location
    BEFORE INSERT OR UPDATE ON public.transactions
    FOR EACH ROW EXECUTE FUNCTION public.txn_check_location_consistency();

-- Handige indexen
CREATE INDEX txn_user_time_idx    ON public.transactions(user_id, traded_at DESC);
CREATE INDEX txn_asset_time_idx   ON public.transactions(asset_id, traded_at DESC);
CREATE INDEX txn_broker_time_idx  ON public.transactions(broker_id, traded_at DESC);
CREATE INDEX txn_loc_time_idx     ON public.transactions(location_id, traded_at DESC);
CREATE INDEX txn_type_time_idx    ON public.transactions(type, traded_at DESC);

---------------------------
-- Cashflows
---------------------------
CREATE TABLE public.cashflows (
                                  id             bigserial PRIMARY KEY,
                                  user_id        bigint NOT NULL REFERENCES public.users(id),
                                  broker_id      bigint REFERENCES public.brokers(id),
                                  account_location_id bigint REFERENCES public.locations(id),  -- bewaarplaats (optioneel)
                                  asset_id       bigint REFERENCES public.assets(id),          -- bijv. dividend/coupon
                                  jurisdiction_id bigint REFERENCES public.jurisdictions(id),  -- bron/jurisdictie
                                  type           public.cashflow_type NOT NULL,
                                  amount         numeric(20,8) NOT NULL,
                                  currency       char(3) NOT NULL,
                                  occurred_at    timestamptz NOT NULL,
                                  note           text
);

ALTER TABLE public.cashflows
    ADD CONSTRAINT cashflows_ccy_chk CHECK (currency = UPPER(currency) AND length(currency)=3);

ALTER TABLE public.cashflows
    ADD CONSTRAINT cashflows_currency_fk FOREIGN KEY (currency) REFERENCES public.currencies(code);

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

CREATE INDEX cashflows_user_time_idx ON public.cashflows(user_id, occurred_at DESC);
CREATE INDEX cashflows_type_time_idx ON public.cashflows(type, occurred_at DESC);
CREATE INDEX cashflows_asset_time_idx ON public.cashflows(asset_id, occurred_at DESC);
CREATE INDEX cashflows_juris_time_idx ON public.cashflows(jurisdiction_id, occurred_at DESC);

---------------------------
-- Extra: views voor rapportering
---------------------------
-- Laatste prijs per asset
CREATE OR REPLACE VIEW public.asset_prices_latest AS
SELECT DISTINCT ON (asset_id)
    asset_id, ts, price
FROM public.asset_prices
ORDER BY asset_id, ts DESC;

COMMIT;
