BEGIN;

-- ---------------------------------------------------------------
-- Seed 002: FX demo (canonieke richting + inverse via trigger)
-- Vereist:
--  - public.currencies bevat 'EUR','USD','CAD'
--  - public.fx_rates bestaat met PK (ccy_from, ccy_to, ts)
--  - trigger trg_fx_inverse actief (alleen NEW.ccy_from < NEW.ccy_to)
-- ---------------------------------------------------------------

-- Fail-fast: controleer vereiste valuta's
DO $$
    DECLARE
        miss text := '';
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM public.currencies WHERE code = 'EUR') THEN
            miss := miss || E'\n- currency EUR ontbreekt';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM public.currencies WHERE code = 'USD') THEN
            miss := miss || E'\n- currency USD ontbreekt';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM public.currencies WHERE code = 'CAD') THEN
            miss := miss || E'\n- currency CAD ontbreekt';
        END IF;
        IF miss <> '' THEN
            RAISE EXCEPTION 'FX demo prerequisites ontbreken:%', miss;
        END IF;
    END $$;

-- 1) Init: schrijf canonieke paren (let op lexicografische volgorde)
--    CAD < EUR < USD, dus:
--    - CAD/EUR en EUR/USD zijn canoniek en triggeren inverse insert
INSERT INTO public.fx_rates (ccy_from, ccy_to, ts, rate) VALUES
                                                             ('CAD','EUR','2024-10-02 12:00:00+00', 0.6800000000),  -- ⇒ EUR/CAD = 1/0.68
                                                             ('EUR','USD','2024-10-02 12:00:00+00', 1.0500000000)   -- ⇒ USD/EUR = 1/1.05
ON CONFLICT (ccy_from, ccy_to, ts) DO UPDATE
    SET rate = EXCLUDED.rate;

-- 2) Nieuwe notering (latere ts) voor EUR/USD: inverse moet mee updaten
INSERT INTO public.fx_rates (ccy_from, ccy_to, ts, rate) VALUES
    ('EUR','USD','2024-10-03 12:00:00+00', 1.0600000000)   -- ⇒ USD/EUR = 1/1.06
ON CONFLICT (ccy_from, ccy_to, ts) DO UPDATE
    SET rate = EXCLUDED.rate;

-- 3) (Optioneel) derde paar CAD/USD via canonieke CAD/USD
--    CAD < USD, dus dit triggert ook USD/CAD inverse
INSERT INTO public.fx_rates (ccy_from, ccy_to, ts, rate) VALUES
    ('CAD','USD','2024-10-03 12:00:00+00', 0.7200000000)   -- ⇒ USD/CAD = 1/0.72
ON CONFLICT (ccy_from, ccy_to, ts) DO UPDATE
    SET rate = EXCLUDED.rate;

COMMIT;
