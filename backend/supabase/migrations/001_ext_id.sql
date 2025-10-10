-- TRANSACTIONS
ALTER TABLE public.transactions
    ALTER COLUMN ext_id SET NOT NULL;
DO $$
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM pg_constraint
            WHERE conname = 'transactions_ext_id_key'
              AND conrelid = 'public.transactions'::regclass
        ) THEN
            ALTER TABLE public.transactions
                ADD CONSTRAINT transactions_ext_id_key UNIQUE (ext_id);
        END IF;
    END $$;

-- CASHFLOWS
ALTER TABLE public.cashflows
    ALTER COLUMN ext_id SET NOT NULL;
DO $$
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM pg_constraint
            WHERE conname = 'cashflows_ext_id_key'
              AND conrelid = 'public.cashflows'::regclass
        ) THEN
            ALTER TABLE public.cashflows
                ADD CONSTRAINT cashflows_ext_id_key UNIQUE (ext_id);
        END IF;
    END $$;
