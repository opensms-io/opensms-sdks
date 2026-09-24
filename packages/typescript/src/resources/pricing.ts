/**
 * The `pricing` resource: your workspace price list.
 * @module
 */
import type { PriceList, PricingParams, RequestOptions } from '../models.js';
import { Resource, wireQuery } from './base.js';

/** Accessed as `client.pricing`. */
export class Pricing extends Resource {
  get(params: PricingParams = {}, options?: RequestOptions): Promise<PriceList> {
    return this.one({ method: 'GET', path: '/v1/pricing', query: wireQuery(params) }, options);
  }
}
