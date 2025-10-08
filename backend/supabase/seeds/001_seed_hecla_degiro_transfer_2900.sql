BEGIN;

-- ================================================================
-- Seed 001: Basisdata + overzetting Hecla (HL) bij DeGiro (2900 stuks)
-- Vereist: migratie met transactions.ext_id + unique index
-- ================================================================

-- 1) Jurisdicties
INSERT INTO public.jurisdictions (country_code, name, mic) VALUES
                                                               ('US','United States',NULL),
                                                               ('NL','Netherlands',NULL),
                                                               ('US','United States - NYSE','XNYS')
ON CONFLICT DO NOTHING;

-- 2) User Jonas
INSERT INTO public.users (email, name, base_currency)
VALUES ('jonas@good-it.be','Jonas','EUR')
ON CONFLICT DO NOTHING;

-- 3) Broker DeGiro (NL)
INSERT INTO public.brokers (user_id, name, country_code, account_ccy)
SELECT u.id, 'DeGiro', 'NL', 'EUR'
FROM public.users u
WHERE u.email = 'jonas@good-it.be'
ON CONFLICT DO NOTHING;

-- 4) Account/Location bij DeGiro (naam: DeGiro - jonasdevries)
INSERT INTO public.locations (user_id, broker_id, name, type, base_currency)
SELECT u.id, b.id, 'DeGiro - jonasdevries', 'broker', 'EUR'
FROM public.users u
         JOIN public.brokers b ON b.user_id = u.id AND b.name = 'DeGiro'
WHERE u.email = 'jonas@good-it.be'
ON CONFLICT DO NOTHING;

-- 5) Asset: Hecla Mining (NYSE: HL), ISIN/unique_symbol: US4227041062, USD
--    issuer_jurisdiction_id = US (zonder MIC)
INSERT INTO public.assets (ticker, name, quote_ccy, mic, unique_symbol, type, issuer_jurisdiction_id)
SELECT 'HL', 'Hecla Mining', 'USD', 'XNYS', 'US4227041062', 'equity', j_us.id
FROM public.jurisdictions j_us
WHERE j_us.country_code = 'US' AND j_us.mic IS NULL
ON CONFLICT (unique_symbol) DO NOTHING;

-- 6) Listing op NYSE (XNYS)
INSERT INTO public.listings (asset_id, mic, ticker_local, quote_ccy)
SELECT a.id, 'XNYS', 'HL', 'USD'
FROM public.assets a
WHERE a.unique_symbol = 'US4227041062'
ON CONFLICT (asset_id, mic) DO NOTHING;

-- ---------------------------------------------------------------
-- 7) Validaties (fail-fast) vóór transactie-insert
--    (voorkomt dat de SELECT stilletjes 0 rijen oplevert)
-- ---------------------------------------------------------------
DO $$
    DECLARE
        v_missing text := '';
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM public.users WHERE email = 'jonas@good-it.be') THEN
            v_missing := v_missing || E'\n- users.email = jonas@good-it.be';
        END IF;

        IF NOT EXISTS (
            SELECT 1 FROM public.brokers b
                              JOIN public.users u ON u.id = b.user_id
            WHERE u.email = 'jonas@good-it.be' AND b.name = 'DeGiro'
        ) THEN
            v_missing := v_missing || E'\n- broker DeGiro voor user jonas@good-it.be';
        END IF;

        IF NOT EXISTS (
            SELECT 1
            FROM public.locations l
                     JOIN public.users u ON u.id = l.user_id
                     JOIN public.brokers b ON b.id = l.broker_id AND b.user_id = u.id AND b.name = 'DeGiro'
            WHERE u.email = 'jonas@good-it.be'
              AND l.name = 'DeGiro - jonasdevries'
        ) THEN
            v_missing := v_missing || E'\n- location "DeGiro - jonasdevries" (bij broker DeGiro)';
        END IF;

        IF NOT EXISTS (
            SELECT 1 FROM public.assets a
            WHERE a.unique_symbol = 'US4227041062'
        ) THEN
            v_missing := v_missing || E'\n- asset Hecla Mining (unique_symbol/isin = US4227041062)';
        END IF;

        IF NOT EXISTS (
            SELECT 1
            FROM public.listings li
                     JOIN public.assets a ON a.id = li.asset_id
            WHERE (a.unique_symbol = 'US4227041062')
              AND li.mic = 'XNYS'
        ) THEN
            v_missing := v_missing || E'\n- listing op XNYS voor Hecla';
        END IF;

        IF v_missing <> '' THEN
            RAISE EXCEPTION 'Seed prerequisites ontbreken:%', v_missing;
        END IF;
    END $$;

-- ---------------------------------------------------------------
-- 8) Transactie: TRANSFER_IN op 2022-09-14, quantity = 2900, géén fees
--    Idempotent via ext_id + upsert
-- ---------------------------------------------------------------
INSERT INTO public.transactions (
    ext_id,
    user_id, broker_id, location_id, asset_id, listing_id,
    type, quantity, price, fee_amount, fee_currency, traded_at, note
)
SELECT
    'degiro-transfer-hl-2022-09-14-2900' AS ext_id,
    u.id, b.id, l.id, a.id, li.id,
    'transfer_in'::txn_type,
    2900::numeric,
    0::numeric,     -- transfer: geen handelsprijs; gebruik NULL ipv 0 om kostbasis/performance niet te verstoren
    0::numeric,
    NULL::text,
    '2022-09-14 00:00:00+00'::timestamptz,
    'Seed: overzetting zonder kosten (2900 stuks)'
FROM public.users u
         JOIN public.brokers   b  ON b.user_id = u.id AND b.name = 'DeGiro'
         JOIN public.locations l  ON l.user_id = u.id AND l.broker_id = b.id AND l.name = 'DeGiro - jonasdevries'
         JOIN public.assets    a  ON (a.unique_symbol = 'US4227041062')
         JOIN public.listings  li ON li.asset_id = a.id AND li.mic = 'XNYS'
WHERE u.email = 'jonas@good-it.be'
ON CONFLICT (ext_id) DO UPDATE
    SET quantity  = EXCLUDED.quantity,
        price     = EXCLUDED.price,
        note      = EXCLUDED.note,
        traded_at = EXCLUDED.traded_at;

COMMIT;
