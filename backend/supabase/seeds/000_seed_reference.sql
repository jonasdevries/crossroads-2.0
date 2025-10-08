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

COMMIT;