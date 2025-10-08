-- 20251007_seed_DIV_multiorders_2024-10-02.sql
BEGIN;

-- ✅ Precondities: vereiste currencies bestaan
DO $$
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM public.currencies WHERE code = 'CAD') THEN
            RAISE EXCEPTION 'Seed precondition: currency CAD ontbreekt in public.currencies';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM public.currencies WHERE code = 'EUR') THEN
            RAISE EXCEPTION 'Seed precondition: currency EUR ontbreekt in public.currencies';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM public.currencies WHERE code = 'USD') THEN
            RAISE EXCEPTION 'Seed precondition: currency USD ontbreekt in public.currencies';
        END IF;
    END $$;

-- 0) BASIS: user + broker + account (als je ze nog niet had)
INSERT INTO public.users (email, name, base_currency)
VALUES ('jonas@good-it.be','Jonas','EUR')
ON CONFLICT DO NOTHING;

INSERT INTO public.brokers (user_id, name, country_code, account_ccy)
SELECT u.id, 'DeGiro', 'NL', 'EUR'
FROM public.users u
WHERE u.email = 'jonas@good-it.be'
ON CONFLICT DO NOTHING;

INSERT INTO public.locations (user_id, broker_id, name, type, base_currency)
SELECT u.id, b.id, 'DeGiro - jonasdevries', 'broker', 'EUR'
FROM public.users u
         JOIN public.brokers b ON b.user_id=u.id AND b.name='DeGiro'
WHERE u.email='jonas@good-it.be'
ON CONFLICT DO NOTHING;

-- 1) Asset + listings (DIV.TO in CAD op XTSE en NEOE)
INSERT INTO public.assets (ticker, name, quote_ccy, mic, unique_symbol, type)
VALUES ('DIV', 'Diversified Royalty Corp', 'CAD', 'XTSE', 'CA2553311002', 'equity')
ON CONFLICT (unique_symbol) DO NOTHING;

-- XTSE listing
INSERT INTO public.listings (asset_id, mic, ticker_local, quote_ccy)
SELECT a.id, 'XTSE', 'DIV', 'CAD' FROM public.assets a
WHERE a.unique_symbol='CA2553311002'
ON CONFLICT (asset_id, mic) DO NOTHING;

-- NEOE listing
INSERT INTO public.listings (asset_id, mic, ticker_local, quote_ccy)
SELECT a.id, 'NEOE', 'DIV', 'CAD' FROM public.assets a
WHERE a.unique_symbol='CA2553311002'
ON CONFLICT (asset_id, mic) DO NOTHING;

-- 1.5) FX rates voor 2024-10-02 (canoniek; inverse wordt on-the-fly afgeleid)
--     We gebruiken dezelfde dag/timestamp als de orders.
--     EUR/USD = 1.25  en  CAD/EUR = 0.68  → CAD/USD via pivot = 0.68 * 1.25 = 0.85
SELECT public.fx_rates_upsert('EUR','USD', '2024-10-02T00:00:00Z', 1.2500000000);
SELECT public.fx_rates_upsert('CAD','EUR', '2024-10-02T00:00:00Z', 0.6800000000);

-- 2) Orders (allemaal 2024-10-02; price in CAD; fee in EUR via AutoFX)
--    Kolommen: (mic, qty, price_cad, fee_eur)
WITH base AS (
    SELECT
        u.id  AS user_id,
        b.id  AS broker_id,
        l.id  AS location_id,
        a.id  AS asset_id,
        li_xtse.id AS listing_xtse_id,
        li_neoe.id AS listing_neoe_id
    FROM public.users u
             JOIN public.brokers b ON b.user_id=u.id AND b.name='DeGiro'
             JOIN public.locations l ON l.user_id=u.id AND l.broker_id=b.id AND l.name='DeGiro - jonasdevries'
             JOIN public.assets a ON a.unique_symbol='CA2553311002'
             LEFT JOIN public.listings li_xtse ON li_xtse.asset_id=a.id AND li_xtse.mic='XTSE'
             LEFT JOIN public.listings li_neoe ON li_neoe.asset_id=a.id AND li_neoe.mic='NEOE'
    WHERE u.email='jonas@good-it.be'
)
INSERT INTO public.transactions (
    user_id, broker_id, location_id, asset_id, listing_id,
    type, quantity, price, fee_amount, fee_currency, traded_at, note
)
SELECT
    b.user_id, b.broker_id, b.location_id, b.asset_id,
    CASE o.mic WHEN 'XTSE' THEN b.listing_xtse_id ELSE b.listing_neoe_id END AS listing_id,
    'buy'::public.txn_type,
    o.qty, o.price_cad, o.fee_eur, 'EUR',
    '2024-10-02T00:00:00Z'::timestamptz,
    'Seed: multi-order buy DIV'
FROM base b
         CROSS JOIN (
    VALUES
        -- mic   , qty  , price , fee (AutoFX in EUR)
        ('XTSE',   100,  2.99 ,  0.50),
        ('XTSE', 29200,  2.99 ,146.66),
        ('XTSE',  2500,  2.99 , 12.56),
        ('NEOE',  2500,  2.99 , 12.56),
        ('XTSE',   100,  3.00 ,  0.50),
        ('XTSE',  1000,  3.00 ,  5.04),
        ('XTSE',   800,  3.00 ,  4.03),
        ('XTSE',  1200,  3.00 ,  6.05),
        ('XTSE',   100,  3.00 ,  0.50),
        ('XTSE',  2600,  3.00 , 13.10),
        ('XTSE',  9900,  3.00 , 49.89)
) AS o(mic, qty, price_cad, fee_eur)
ON CONFLICT DO NOTHING;


-- EUR↔CAD op 2024-10-02 16:54:32Z
-- We slaan slechts één rij op (canoniek via LEAST/GREATEST in fx_rates_upsert).
-- Richting EUR→CAD of CAD→EUR wordt bij gebruik on-the-fly bepaald (eventueel 1/rate).
SELECT public.fx_rates_upsert('EUR','CAD', '2024-10-02T16:54:32Z', 1.4883000000);



COMMIT;
