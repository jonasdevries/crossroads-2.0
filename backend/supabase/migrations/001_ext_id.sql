-- 002_ext_id_text.sql

-- Zorg dat pgcrypto bestaat, voor backfill (alleen nodig als je NULLS wil vullen met uuid-strings)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- TRANSACTIONS
DO $$
BEGIN
  -- Voeg toe als hij nog niet bestaat
  IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'transactions' AND column_name = 'ext_id'
  ) THEN
ALTER TABLE public.transactions ADD COLUMN ext_id text;
END IF;

  -- Converteer naar TEXT als het (nog) UUID is
  IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'transactions' AND column_name = 'ext_id'
        AND udt_name = 'uuid'
  ) THEN
ALTER TABLE public.transactions
ALTER COLUMN ext_id TYPE text USING ext_id::text;
END IF;
END $$;

-- Backfill (optioneel, voor bestaande rijen zonder ext_id)
UPDATE public.transactions
SET ext_id = gen_random_uuid()::text
WHERE ext_id IS NULL;

-- Niet-null + unieke index voor upsert
ALTER TABLE public.transactions
    ALTER COLUMN ext_id SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS transactions_ext_id_key
    ON public.transactions (ext_id);

-- CASHFLOWS
DO $$
BEGIN
  IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'cashflows' AND column_name = 'ext_id'
  ) THEN
ALTER TABLE public.cashflows ADD COLUMN ext_id text;
END IF;

  IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'cashflows' AND column_name = 'ext_id'
        AND udt_name = 'uuid'
  ) THEN
ALTER TABLE public.cashflows
ALTER COLUMN ext_id TYPE text USING ext_id::text;
END IF;
END $$;

UPDATE public.cashflows
SET ext_id = gen_random_uuid()::text
WHERE ext_id IS NULL;

ALTER TABLE public.cashflows
    ALTER COLUMN ext_id SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS cashflows_ext_id_key
    ON public.cashflows (ext_id);
