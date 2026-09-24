/**
 * The `suppressions` resource: numbers that must never receive messages.
 * @module
 */
import { toWire } from '../models.js';
import type {
  CreateSuppressionParams,
  ListParams,
  Page,
  RequestOptions,
  Suppression,
  SuppressionImportResult,
} from '../models.js';
import { Resource, seg, wireQuery } from './base.js';

/** Accessed as `client.suppressions`. */
export class Suppressions extends Resource {
  list(params: ListParams = {}, options?: RequestOptions): Promise<Page<Suppression>> {
    return this.page({ method: 'GET', path: '/v1/compliance/suppressions', query: wireQuery(params) }, options);
  }

  /** Suppress one number. Never retried. */
  create(params: CreateSuppressionParams, options?: RequestOptions): Promise<Suppression> {
    return this.one({ method: 'POST', path: '/v1/compliance/suppressions', json: toWire(params) }, options);
  }

  /** Suppress many numbers at once. Never retried. */
  import(items: CreateSuppressionParams[], options?: RequestOptions): Promise<SuppressionImportResult> {
    return this.one(
      { method: 'POST', path: '/v1/compliance/suppressions/import', json: toWire({ items }) },
      options,
    );
  }

  delete(id: number | string, options?: RequestOptions): Promise<void> {
    return this.none({ method: 'DELETE', path: `/v1/compliance/suppressions/${seg(id)}` }, options);
  }
}
