-- 20251007_seed_degiro_cash_balance_today.sql
BEGIN;

INSERT INTO public.cashflows (
    user_id, broker_id, account_location_id,
    type, amount, currency, occurred_at, note
)
SELECT
    u.id, b.id, l.id,
    'deposit', 1690.75, 'EUR', '2025-10-07'::timestamptz,
    'Seed: beginsaldo DeGiro EUR-rekening'
FROM public.users u
         JOIN public.brokers b   ON b.user_id = u.id AND b.name = 'DeGiro'
         JOIN public.locations l ON l.user_id = u.id AND l.broker_id = b.id AND l.name = 'DeGiro - jonasdevries'
WHERE u.email = 'jonas@good-it.be'
  AND NOT EXISTS (
    SELECT 1
    FROM public.cashflows cf
    WHERE cf.user_id = u.id
      AND cf.broker_id = b.id
      AND cf.account_location_id = l.id
      AND cf.type = 'deposit'
      AND cf.amount = 1690.75
      AND cf.currency = 'EUR'
      AND cf.occurred_at = '2025-10-07'::timestamptz
      AND cf.note = 'Seed: beginsaldo DeGiro EUR-rekening'
);

COMMIT;
