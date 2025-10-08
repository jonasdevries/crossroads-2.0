-- 20251007_seed_fx_DIV_2024-10-02.sql
BEGIN;

-- EUR→CAD = 1.4883 (DeGiro wisselkoers uit je screenshot)
-- Inverse CAD→EUR wordt automatisch gezet door trg_fx_inverse (1/1.4883 ≈ 0.6719075455)
INSERT INTO public.fx_rates (ccy_from, ccy_to, ts, rate)
VALUES ('EUR','CAD','2024-10-02 16:54:32+00', 1.4883)
ON CONFLICT DO NOTHING;

COMMIT;
