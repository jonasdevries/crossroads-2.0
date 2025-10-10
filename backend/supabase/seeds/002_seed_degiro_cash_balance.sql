INSERT INTO public.cashflows (
    ext_id,
    user_id, broker_id, account_location_id,
    type, amount, currency, occurred_at, note
)
SELECT
    'degiro-cash-deposit-2025-10-07-1690_75'::text AS ext_id,  -- leesbare, unieke sleutel
    u.id, b.id, l.id,
    'deposit', 1690.75, 'EUR', '2025-10-07'::timestamptz,
    'Seed: beginsaldo DeGiro EUR-rekening'
FROM public.users u
         JOIN public.brokers b   ON b.user_id = u.id AND b.name = 'DeGiro'
         JOIN public.locations l ON l.user_id = u.id AND l.broker_id = b.id AND l.name = 'DeGiro - jonasdevries'
WHERE u.email = 'jonas@good-it.be'
    ON CONFLICT (ext_id) DO UPDATE
                                SET amount      = EXCLUDED.amount,
                                currency    = EXCLUDED.currency,
                                occurred_at = EXCLUDED.occurred_at,
                                note        = EXCLUDED.note;
