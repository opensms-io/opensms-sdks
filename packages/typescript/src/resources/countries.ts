/**
 * The `countries` resource: the public coverage catalog.
 * @module
 */
import type { Carrier, Country, CountryRules, RequestOptions, Route } from '../models.js';
import { Resource, seg } from './base.js';

/** Accessed as `client.countries`. */
export class Countries extends Resource {
  list(options?: RequestOptions): Promise<Country[]> {
    return this.array({ method: 'GET', path: '/v1/countries' }, options);
  }

  carriers(iso2: string, options?: RequestOptions): Promise<Carrier[]> {
    return this.array({ method: 'GET', path: `/v1/countries/${seg(iso2, 'iso2')}/carriers` }, options);
  }

  routes(iso2: string, options?: RequestOptions): Promise<Route[]> {
    return this.array({ method: 'GET', path: `/v1/countries/${seg(iso2, 'iso2')}/routes` }, options);
  }

  compliance(iso2: string, options?: RequestOptions): Promise<CountryRules> {
    return this.one({ method: 'GET', path: `/v1/countries/${seg(iso2, 'iso2')}/compliance` }, options);
  }
}
