import { getPool, closePool } from '../helpers/db.js';

// Allow skipping DB tests via env (same pattern as fx specs)
const skipDbTests = process.env.SKIP_DB_TESTS === '1';
const describeIfDb = skipDbTests ? describe.skip : describe;

if (skipDbTests) {
    // eslint-disable-next-line no-console
    console.warn(
        'Skipping DB specs because SKIP_DB_TESTS=1. Start Supabase locally and rerun to execute them.'
    );
}

describe('Commodities (transactions)', () => {
    const extIdsToCleanup = new Set();
    const tempIds = { broker: null, location: null, asset: null, listing: null };

    afterAll(async () => {
        const pool = getPool();

        if (extIdsToCleanup.size > 0) {
            await pool.query(
                `delete from public.transactions where ext_id = any($1::text[])`,
                [Array.from(extIdsToCleanup)]
            );
        }

        // best-effort cleanup van tijdelijk aangemaakte entiteiten (alleen als ze bestaan)
        if (tempIds.listing) {
            await pool.query(`delete from public.listings where id = $1`, [tempIds.listing]);
        }
        if (tempIds.asset) {
            await pool.query(`delete from public.assets where id = $1`, [tempIds.asset]);
        }
        if (tempIds.location) {
            await pool.query(`delete from public.locations where id = $1`, [tempIds.location]);
        }
        if (tempIds.broker) {
            await pool.query(`delete from public.brokers where id = $1`, [tempIds.broker]);
        }

        await closePool();
    });

    async function ctx() {
        const pool = getPool();
        const { rows } = await pool.query(
            `
      select
        u.id as user_id,
        b.id as broker_id,
        l.id as vault_location_id,
        a_pt.id as asset_pt_id,
        a_ag.id as asset_ag_id
      from public.users u
      join public.brokers b on b.user_id = u.id and b.name = 'Self Custody'
      join public.locations l on l.user_id = u.id and l.name = 'Kluis'
      join public.assets a_pt on a_pt.unique_symbol = 'PT-1KG-LPPM'
      join public.assets a_ag on a_ag.unique_symbol = 'AG-1KG'
      where u.email = 'jonas@good-it.be'
      `
        );
        if (!rows.length) {
            throw new Error('Seeds ontbreken: user/broker/location/assets niet gevonden');
        }
        return rows[0];
    }

    it('happy path: commodity buy in base currency (listing_id NULL) komt correct in DB', async () => {
        const pool = getPool();
        const c = await ctx();

        const extId = `test:commodity:ag-2kg:${Date.now()}`;
        extIdsToCleanup.add(extId);

        await pool.query(
            `
      insert into public.transactions (
        user_id, broker_id, location_id, asset_id, listing_id,
        type, quantity, price, fee_amount, fee_currency, traded_at, note, ext_id
      )
      values ($1,$2,$3,$4,null,'buy', 2.0, 399.00, 0, null, '2025-01-02T00:00:00Z', 'Test: AG 2kg @399', $5)
      `,
            [c.user_id, c.broker_id, c.vault_location_id, c.asset_ag_id, extId]
        );

        const { rows } = await pool.query(
            `select quantity, price, fee_amount, fee_currency, listing_id
       from public.transactions where ext_id = $1`,
            [extId]
        );
        expect(rows).toHaveLength(1);
        expect(Number(rows[0].quantity)).toBeCloseTo(2, 6);
        expect(Number(rows[0].price)).toBeCloseTo(399.0, 2);
        expect(Number(rows[0].fee_amount)).toBeCloseTo(0, 2);
        expect(rows[0].fee_currency).toBeNull();
        expect(rows[0].listing_id).toBeNull();
    });

    it('idempotentie: unique ext_id verhindert dubbele insert', async () => {
        const pool = getPool();
        const c = await ctx();

        const extId = `test:commodity:pt-dup:${Date.now()}`;
        extIdsToCleanup.add(extId);

        // eerste insert
        await pool.query(
            `
      insert into public.transactions (
        user_id, broker_id, location_id, asset_id, listing_id,
        type, quantity, price, fee_amount, fee_currency, traded_at, note, ext_id
      )
      values ($1,$2,$3,$4,null,'buy', 1.0, 41608.51, 0, null, '2025-09-04T00:00:00Z', 'Test: PT 1kg', $5)
      `,
            [c.user_id, c.broker_id, c.vault_location_id, c.asset_pt_id, extId]
        );

        // tweede insert met zelfde ext_id → moet falen op unieke constraint
        await expect(
            pool.query(
                `
        insert into public.transactions (
          user_id, broker_id, location_id, asset_id, listing_id,
          type, quantity, price, fee_amount, fee_currency, traded_at, note, ext_id
        )
        values ($1,$2,$3,$4,null,'buy', 1.0, 41608.51, 0, null, '2025-09-04T00:00:00Z', 'Test: PT 1kg', $5)
        `,
                [c.user_id, c.broker_id, c.vault_location_id, c.asset_pt_id, extId]
            )
        ).rejects.toThrow(/transactions_ext_id_key|duplicate key/i);
    });

    it('fee-regel: fee_amount > 0 vereist fee_currency', async () => {
        const pool = getPool();
        const c = await ctx();

        const extId = `test:commodity:fee-bad:${Date.now()}`;
        // geen cleanup nodig als insert faalt; maar voor de vorm:
        extIdsToCleanup.add(extId);

        await expect(
            pool.query(
                `
        insert into public.transactions (
          user_id, broker_id, location_id, asset_id, listing_id,
          type, quantity, price, fee_amount, fee_currency, traded_at, note, ext_id
        )
        values ($1,$2,$3,$4,null,'buy', 1.0, 100.00, 5.00, null, '2025-01-02T00:00:00Z', 'fee without currency', $5)
        `,
                [c.user_id, c.broker_id, c.vault_location_id, c.asset_ag_id, extId]
            )
        ).rejects.toThrow(/txn_fee_currency_chk/i);

        // correcte variant
        const okId = `test:commodity:fee-ok:${Date.now()}`;
        extIdsToCleanup.add(okId);
        await pool.query(
            `
      insert into public.transactions (
        user_id, broker_id, location_id, asset_id, listing_id,
        type, quantity, price, fee_amount, fee_currency, traded_at, note, ext_id
      )
      values ($1,$2,$3,$4,null,'buy', 1.0, 100.00, 5.00, 'EUR', '2025-01-02T00:00:00Z', 'fee ok', $5)
      `,
            [c.user_id, c.broker_id, c.vault_location_id, c.asset_ag_id, okId]
        );
    });

    it('prijs-semantieken: buy/sell vereisen price > 0', async () => {
        const pool = getPool();
        const c = await ctx();

        const extId = `test:commodity:price-zero:${Date.now()}`;
        extIdsToCleanup.add(extId);

        await expect(
            pool.query(
                `
        insert into public.transactions (
          user_id, broker_id, location_id, asset_id, listing_id,
          type, quantity, price, fee_amount, fee_currency, traded_at, note, ext_id
        )
        values ($1,$2,$3,$4,null,'buy', 1.0, 0, 0, null, '2025-01-02T00:00:00Z', 'price zero', $5)
        `,
                [c.user_id, c.broker_id, c.vault_location_id, c.asset_ag_id, extId]
            )
        ).rejects.toThrow(/tx_price_semantics_chk|price > 0/i);
    });

    it('listing/asset-consistentie: trigger weigert mismatch tussen asset_id en listing_id', async () => {
        const pool = getPool();
        const c = await ctx();

        // Maak tijdelijk asset + listing die NIET overeenkomen met AG-1KG
        const { rows: a } = await pool.query(
            `insert into public.assets (ticker,name,quote_ccy,mic,unique_symbol,type)
       values (null,'Dummy Asset X','EUR',null,$1,'commodity')
       returning id`,
            [`DUMMY-X-${Date.now()}`]
        );
        tempIds.asset = a[0].id;

        const { rows: li } = await pool.query(
            `insert into public.listings (asset_id, mic, ticker_local, quote_ccy)
       values ($1, 'XMIC', 'DUMMYX', 'EUR')
       returning id`,
            [tempIds.asset]
        );
        tempIds.listing = li[0].id;

        // Probeer transactie met asset_id = AG-1KG, maar listing_id = dummy listing → moet falen
        const extId = `test:commodity:listing-mismatch:${Date.now()}`;
        extIdsToCleanup.add(extId);

        await expect(
            pool.query(
                `
        insert into public.transactions (
          user_id, broker_id, location_id, asset_id, listing_id,
          type, quantity, price, fee_amount, fee_currency, traded_at, note, ext_id
        )
        values ($1,$2,$3,$4,$5,'buy', 1.0, 100.00, 0, null, '2025-01-02T00:00:00Z', 'mismatch listing', $6)
        `,
                [c.user_id, c.broker_id, c.vault_location_id, c.asset_ag_id, tempIds.listing, extId]
            )
        ).rejects.toThrow(/transactions\.asset_id.*listings\.asset_id|Listing .* not found|listing/i);
    });

    it('location-consistentie: broker-mismatch tussen transaction en location wordt geweigerd', async () => {
        const pool = getPool();
        const c = await ctx();

        // Maak extra broker en locatie die eraan hangt
        const { rows: b } = await pool.query(
            `insert into public.brokers (user_id,name,country_code,account_ccy)
             values ($1,'Another Broker','BE','EUR') returning id`,
            [c.user_id]
        );
        tempIds.broker = b[0].id;

        const { rows: loc } = await pool.query(
            `insert into public.locations (user_id, broker_id, name, type, base_currency)
       values ($1,$2,'Broker-Location-X','broker','EUR') returning id`,
            [c.user_id, tempIds.broker]
        );
        tempIds.location = loc[0].id;

        const extId = `test:commodity:loc-broker-mismatch:${Date.now()}`;
        extIdsToCleanup.add(extId);

        // Gebruik broker_id = Self Custody maar location_id = Broker-Location-X (van Another Broker) → fail
        await expect(
            pool.query(
                `
        insert into public.transactions (
          user_id, broker_id, location_id, asset_id, listing_id,
          type, quantity, price, fee_amount, fee_currency, traded_at, note, ext_id
        )
        values ($1,$2,$3,$4,null,'buy', 1.0, 100.00, 0, null, '2025-01-02T00:00:00Z', 'loc-broker mismatch', $5)
        `,
                [c.user_id, c.broker_id /* Self Custody */, tempIds.location, c.asset_ag_id, extId]
            )
        ).rejects.toThrow(/Location\.broker_id .* != Transaction\.broker_id|mismatch/i);

        // Controle: vault 'Kluis' (broker_id NULL) accepteert dezelfde transactie wél:
        const okId = `test:commodity:loc-vault-ok:${Date.now()}`;
        extIdsToCleanup.add(okId);
        await pool.query(
            `
      insert into public.transactions (
        user_id, broker_id, location_id, asset_id, listing_id,
        type, quantity, price, fee_amount, fee_currency, traded_at, note, ext_id
      )
      values ($1,$2,$3,$4,null,'buy', 1.0, 100.00, 0, null, '2025-01-02T00:00:00Z', 'vault ok', $5)
      `,
            [c.user_id, c.broker_id, c.vault_location_id, c.asset_ag_id, okId]
        );
    });
});
