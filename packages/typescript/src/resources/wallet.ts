/**
 * The `wallet` resource: balances, ledger and top-ups.
 * @module
 */
import { toWire } from '../models.js';
import type { CreateTopupParams, LedgerEntry, LedgerParams, RequestOptions, Topup, WalletBalance } from '../models.js';
import { Resource, wireQuery } from './base.js';

/** Accessed as `client.wallet`. */
export class Wallet extends Resource {
  /** One balance per wallet (currency and environment). */
  balances(options?: RequestOptions): Promise<WalletBalance[]> {
    return this.wrapped('data', { method: 'GET', path: '/v1/wallet' }, options);
  }

  /**
   * Ledger entries, newest first. Pages by `before` (the smallest `id` seen);
   * stop when fewer than `limit` entries come back.
   */
  ledger(params: LedgerParams = {}, options?: RequestOptions): Promise<LedgerEntry[]> {
    return this.wrapped('data', { method: 'GET', path: '/v1/wallet/ledger', query: wireQuery(params) }, options);
  }

  /** Start a payment-provider top-up (live keys only). */
  createTopup(params: CreateTopupParams, options?: RequestOptions): Promise<Topup> {
    return this.one({ method: 'POST', path: '/v1/wallet/topups', json: toWire(params), idempotent: true }, options);
  }
}
