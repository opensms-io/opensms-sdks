/**
 * The `compliance` resource: per-country sending rules and content rules.
 * @module
 */
import type { ContentRule, CountryRules, RequestOptions } from '../models.js';
import { Resource, seg } from './base.js';

/** Accessed as `client.compliance`. */
export class Compliance extends Resource {
  listCountries(options?: RequestOptions): Promise<CountryRules[]> {
    return this.array({ method: 'GET', path: '/v1/compliance/countries' }, options);
  }

  getCountry(iso2: string, options?: RequestOptions): Promise<CountryRules> {
    return this.one({ method: 'GET', path: `/v1/compliance/countries/${seg(iso2, 'iso2')}` }, options);
  }

  listContentRules(options?: RequestOptions): Promise<ContentRule[]> {
    return this.array({ method: 'GET', path: '/v1/content-rules' }, options);
  }
}
