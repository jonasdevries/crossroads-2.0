-- 20251008_seed_commodity_platinum_1kg_2025-09-04.sql
BEGIN;

-- Precondities
DO $$
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM public.currencies WHERE code = 'EUR') THEN
            RAISE EXCEPTION 'Seed precondition: currency EUR ontbreekt in public.currencies';
        END IF;
    END $$;

-- User (als nog niet aanwezig)
INSERT INTO public.users (email, name, base_currency)
VALUES ('jonas@good-it.be', 'Jonas', 'EUR')
ON CONFLICT DO NOTHING;

-- Broker voor self-custody context (verplicht veld in transactions)
INSERT INTO public.brokers (user_id, name, country_code, account_ccy)
SELECT u.id, 'Self Custody', 'BE', 'EUR'
FROM public.users u
WHERE u.email = 'jonas@good-it.be'
ON CONFLICT (user_id, name) DO NOTHING;

-- Vault-locatie “Kluis” (zonder broker-binding)
INSERT INTO public.locations (user_id, broker_id, name, type, base_currency)
SELECT u.id, NULL, 'Kluis', 'vault', 'EUR'
FROM public.users u
WHERE u.email = 'jonas@good-it.be'
ON CONFLICT (user_id, name) DO NOTHING;

-- Asset: Platina baar 1 kilogram LPPM (commodity, geen listing nodig)
INSERT INTO public.assets (ticker, name, quote_ccy, mic, unique_symbol, type)
VALUES (NULL, 'Platina baar 1 kilogram LPPM', 'EUR', NULL, 'PT-1KG-LPPM', 'commodity')
ON CONFLICT (unique_symbol) DO NOTHING;

-- Transactie (buy 1 stuk @ €41.608,51) op 2025-09-04
WITH x AS (
    SELECT
        u.id  AS user_id,
        b.id  AS broker_id,
        l.id  AS location_id,
        a.id  AS asset_id
    FROM public.users u
             JOIN public.brokers b
                  ON b.user_id = u.id AND b.name = 'Self Custody'
             JOIN public.locations l
                  ON l.user_id = u.id AND l.name = 'Kluis'
             JOIN public.assets a
                  ON a.unique_symbol = 'PT-1KG-LPPM'
    WHERE u.email = 'jonas@good-it.be'
)
INSERT INTO public.transactions (
    user_id, broker_id, location_id, asset_id, listing_id,
    type, quantity, price, fee_amount, fee_currency, traded_at, note, ext_id
)
SELECT
    x.user_id,
    x.broker_id,
    x.location_id,
    x.asset_id,
    NULL,                                 -- geen beurslisting voor fysieke baar
    'buy'::public.txn_type,
    1.00000000,                           -- 1 kilogram (eenheidinformatie zit niet in schema)
    41608.51,                             -- EUR
    0,                                    -- geen fee
    NULL,
    '2025-09-04T00:00:00Z'::timestamptz,  -- handelsdatum
    'Seed: aankoop Platina baar 1kg LPPM',
    'seed:commodity:pt-1kg-lppm:2025-09-04'
FROM x
ON CONFLICT (ext_id) DO NOTHING;

COMMIT;
