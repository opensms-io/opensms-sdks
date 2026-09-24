/**
 * The `lookups` resource: number validity, carrier and porting checks.
 * @module
 */
import { toWire } from '../models.js';
import type { CreateLookupParams, Lookup, RequestOptions } from '../models.js';
import { Resource, seg } from './base.js';

/** Accessed as `client.lookups`. */
export class Lookups extends Resource {
  /** Request a lookup. Returns the completed result or a pending one to poll. */
  create(params: CreateLookupParams, options?: RequestOptions): Promise<Lookup> {
    return this.one({ method: 'POST', path: '/v1/lookup', json: toWire(params), idempotent: true }, options);
  }

  /** Get a lookup. */
  get(id: string, options?: RequestOptions): Promise<Lookup> {
    return this.one({ method: 'GET', path: `/v1/lookup/${seg(id)}` }, options);
  }
}
