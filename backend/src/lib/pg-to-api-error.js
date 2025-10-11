export function pgToApiError(e) {
    const msg = e?.message || '';
    if (/FX missing/i.test(msg)) return apiError(422, 'fx_missing', msg);
    if (/transactions_ext_id_key|cashflows_ext_id_key|duplicate key/i.test(msg))
        return apiError(409, 'conflict', msg);
    if (/txn_fee_currency_chk|tx_price_semantics_chk|fx_rates_canonical_chk|cashflows_ccy_chk|cashflows_type_min_rules_chk/i.test(msg))
        return apiError(400, 'bad_request', msg);
    return apiError(500, 'internal', 'Unexpected error', { pg: msg });
}

export function apiError(status, code, message, details) {
    const err = new Error(message);
    err.status = status;
    err.payload = { error: { code, message, details } };
    return err;
}