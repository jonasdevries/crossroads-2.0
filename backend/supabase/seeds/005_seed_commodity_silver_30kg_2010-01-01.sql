-- seed_commodity_silver_30kg_2010-01-01.sql
-- Zilver (30 kg) gekocht aan €399,00 / kg op 2010-01-01
-- - commodity asset (AG-1KG)
-- - user/broker/location worden idempotent aangemaakt indien nodig
-- - transaction is idempotent via ext_id

BEGIN;

-- 0) Precondities / basisgegevens (idempotent)
INSERT INTO public.currencies (code, name, decimals)
VALUES ('EUR','Euro',2)
ON CONFLICT (code) DO NOTHING;

-- Users (idempotent via WHERE NOT EXISTS op lower(email))
INSERT INTO public.users (email, name, base_currency)
SELECT 'jonas@good-it.be','Jonas','EUR'
WHERE NOT EXISTS (
    SELECT 1 FROM public.users WHERE lower(email) = 'jonas@good-it.be'
);


-- Broker voor self-custody (idempotent)
INSERT INTO public.brokers (user_id, name, country_code, account_ccy)
SELECT u.id, 'Self Custody', 'BE', 'EUR'
FROM public.users u
WHERE u.email = 'jonas@good-it.be'
ON CONFLICT (user_id, name) DO NOTHING;

-- Locatie “Kluis” (vault). broker_id is optioneel voor een vault.
INSERT INTO public.locations (user_id, broker_id, name, type, base_currency)
SELECT u.id, NULL, 'Kluis', 'vault', 'EUR'
FROM public.users u
WHERE u.email = 'jonas@good-it.be'
ON CONFLICT (user_id, name) DO NOTHING;

-- 1) Asset (commodity: zilveren baar 1kg), idempotent via unique_symbol
INSERT INTO public.assets (ticker, name, quote_ccy, mic, unique_symbol, type)
VALUES ('SILVER-1KG', 'Zilveren baar 1 kilogram LPPM', 'EUR', NULL, 'AG-1KG', 'commodity')
ON CONFLICT (unique_symbol) DO NOTHING;

-- 2) Transactie: buy 30 kg @ €399,00 per kg op 2010-01-01 (idempotent via ext_id)
WITH ctx AS (
    SELECT
        u.id  AS user_id,
        b.id  AS broker_id,
        l.id  AS location_id,
        a.id  AS asset_id
    FROM public.users u
             JOIN public.brokers  b ON b.user_id = u.id AND b.name = 'Self Custody'
             JOIN public.locations l ON l.user_id = u.id AND l.name = 'Kluis'
             JOIN public.assets    a ON a.unique_symbol = 'AG-1KG'
    WHERE u.email = 'jonas@good-it.be'
)
INSERT INTO public.transactions (
    user_id, broker_id, location_id, asset_id, listing_id,
    type, quantity, price, fee_amount, fee_currency, traded_at, note, ext_id
)
SELECT
    c.user_id, c.broker_id, c.location_id, c.asset_id, NULL,
    'buy'::public.txn_type,
    30.00000000,                 -- quantity (kg)
    399.00000000,                -- price per kg in EUR
    0,                           -- geen fee
    NULL,
    '2010-01-01 00:00:00+00'::timestamptz,
    'Seed: silver 30kg @ €399/kg (vault)',
    'seed:silver:30kg:2010-01-01'
FROM ctx c
ON CONFLICT (ext_id) DO NOTHING;

COMMIT;
