-- supabase/seeds/000_seed_reference.sql
BEGIN;

INSERT INTO public.currencies (code, name, decimals) VALUES
                                                         ('EUR','Euro',2),
                                                         ('USD','US Dollar',2),
                                                         ('CAD','Canadian Dollar',2),
                                                         ('GBP','British Pound',2),
                                                         ('CHF','Swiss Franc',2),
                                                         ('JPY','Japanese Yen',0),
                                                         ('AUD','Australian Dollar',2),
                                                         ('SEK','Swedish Krona',2),
                                                         ('NOK','Norwegian Krone',2)
ON CONFLICT (code) DO NOTHING;

-- ============================================
-- Seed FX (EUR, USD, GBP, CAD)
-- Vereist: migratie met public.fx_rates_upsert + constraints
-- ============================================

-- EUR/USD @ 2024-10-02
select public.fx_rates_upsert('EUR','USD', '2024-10-02T00:00:00Z', 1.2500000000);

-- GBP/EUR @ 2024-10-02
select public.fx_rates_upsert('GBP','EUR', '2024-10-02T00:00:00Z', 1.2000000000);

-- CAD/EUR @ 2024-10-02
select public.fx_rates_upsert('CAD','EUR', '2024-10-02T00:00:00Z', 0.6800000000);

-- Nieuwere EUR/USD @ 2024-10-02T00:00:05Z (latest-wins demo)
select public.fx_rates_upsert('EUR','USD', '2024-10-02T00:00:05Z', 1.3000000000);

-- USD/EUR *niet* opslaan — inverse wordt afgeleid on-the-fly
-- GBP/USD pad kan via pivot EUR: (GBP->EUR=1.2) * (EUR->USD=1.3) = 1.56


COMMIT;