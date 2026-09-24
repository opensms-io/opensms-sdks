/**
 * The `sandbox` resource: rendered text of sandbox sends, including OTP codes.
 * @module
 */
import type { ListParams, Page, RequestOptions, SandboxMessage } from '../models.js';
import { Resource, wireQuery } from './base.js';

/** Accessed as `client.sandbox`. */
export class Sandbox extends Resource {
  listMessages(params: ListParams = {}, options?: RequestOptions): Promise<Page<SandboxMessage>> {
    return this.page({ method: 'GET', path: '/v1/sandbox/messages', query: wireQuery(params) }, options);
  }
}
