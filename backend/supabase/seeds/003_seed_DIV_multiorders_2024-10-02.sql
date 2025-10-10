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
  ext_id,
  user_id, broker_id, location_id, asset_id, listing_id,
  type, quantity, price, fee_amount, fee_currency, traded_at, note
)
SELECT
    -- maak 'm uniek en voorspelbaar:
    format(
            'degiro-buy-%s-%s-%s-%s',
            to_char('2024-10-02'::date,'YYYYMMDD'),
            replace(a.unique_symbol, ' ', ''),
            100::text,
            2.99::text
    ) AS ext_id,
    u.id, b.id, l.id, a.id, li.id,
    'buy'::txn_type,
    100::numeric,
    2.99::numeric,
    0.50::numeric, 'EUR',
    '2024-10-02 00:00:00+00'::timestamptz,
    'Seed: multi-order buy DIV'
FROM public.users u
         JOIN public.brokers   b  ON b.user_id = u.id AND b.name = 'DeGiro'
         JOIN public.locations l  ON l.user_id = u.id AND l.broker_id = b.id AND l.name = 'DeGiro - jonasdevries'
         JOIN public.assets    a  ON a.unique_symbol = 'US4227041062'
         JOIN public.listings  li ON li.asset_id = a.id AND li.mic = 'XNYS'
WHERE u.email = 'jonas@good-it.be'
    ON CONFLICT (ext_id) DO UPDATE
                                SET quantity  = EXCLUDED.quantity,
                                price     = EXCLUDED.price,
                                fee_amount= EXCLUDED.fee_amount,
                                fee_currency = EXCLUDED.fee_currency,
                                traded_at = EXCLUDED.traded_at,
                                note      = EXCLUDED.note;



-- EUR↔CAD op 2024-10-02 16:54:32Z
-- We slaan slechts één rij op (canoniek via LEAST/GREATEST in fx_rates_upsert).
-- Richting EUR→CAD of CAD→EUR wordt bij gebruik on-the-fly bepaald (eventueel 1/rate).
SELECT public.fx_rates_upsert('EUR','CAD', '2024-10-02T16:54:32Z', 1.4883000000);



COMMIT;
