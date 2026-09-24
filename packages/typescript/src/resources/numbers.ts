/**
 * The `numbers` resource: virtual numbers and their inbound rules. Everything
 * except `list` and `available` needs a live key.
 * @module
 */
import { toWire } from '../models.js';
import type {
  ListParams,
  NumberRule,
  NumberRuleParams,
  NumberSearchParams,
  Page,
  PhoneNumber,
  RequestOptions,
} from '../models.js';
import { Resource, seg, wireQuery } from './base.js';

/** Accessed as `client.numbers`. */
export class Numbers extends Resource {
  list(params: ListParams = {}, options?: RequestOptions): Promise<Page<PhoneNumber>> {
    return this.page({ method: 'GET', path: '/v1/numbers', query: wireQuery(params) }, options);
  }

  /** Numbers available to assign. */
  available(params: NumberSearchParams, options?: RequestOptions): Promise<PhoneNumber[]> {
    return this.array({ method: 'GET', path: '/v1/numbers/available', query: wireQuery(params) }, options);
  }

  /** Assign a number to the workspace (charges the wallet). */
  assign(params: NumberSearchParams, options?: RequestOptions): Promise<PhoneNumber> {
    return this.one({ method: 'POST', path: '/v1/numbers', json: toWire(params), idempotent: true }, options);
  }

  release(id: string, options?: RequestOptions): Promise<void> {
    return this.none({ method: 'DELETE', path: `/v1/numbers/${seg(id)}` }, options);
  }

  listRules(id: string, params: ListParams = {}, options?: RequestOptions): Promise<Page<NumberRule>> {
    return this.page({ method: 'GET', path: `/v1/numbers/${seg(id)}/rules`, query: wireQuery(params) }, options);
  }

  createRule(id: string, rule: NumberRuleParams, options?: RequestOptions): Promise<NumberRule> {
    return this.one(
      { method: 'POST', path: `/v1/numbers/${seg(id)}/rules`, json: toWire(rule), idempotent: true },
      options,
    );
  }

  updateRule(id: string, ruleId: string, rule: NumberRuleParams, options?: RequestOptions): Promise<NumberRule> {
    return this.one(
      { method: 'PUT', path: `/v1/numbers/${seg(id)}/rules/${seg(ruleId, 'ruleId')}`, json: toWire(rule) },
      options,
    );
  }

  deleteRule(id: string, ruleId: string, options?: RequestOptions): Promise<void> {
    return this.none({ method: 'DELETE', path: `/v1/numbers/${seg(id)}/rules/${seg(ruleId, 'ruleId')}` }, options);
  }
}
