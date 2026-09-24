/**
 * The `inbound` resource: messages received on your numbers.
 * @module
 */
import { toWire } from '../models.js';
import type { InboundMessage, InboundReplyParams, ListParams, Message, Page, RequestOptions } from '../models.js';
import { Resource, seg, wireQuery } from './base.js';

/** Accessed as `client.inbound`. */
export class Inbound extends Resource {
  list(params: ListParams = {}, options?: RequestOptions): Promise<Page<InboundMessage>> {
    return this.page({ method: 'GET', path: '/v1/inbound', query: wireQuery(params) }, options);
  }

  /** Reply to an inbound message (live keys only). Returns the sent Message. */
  reply(id: string, params: InboundReplyParams, options?: RequestOptions): Promise<Message> {
    return this.one(
      { method: 'POST', path: `/v1/inbound/${seg(id)}/reply`, json: toWire(params), idempotent: true },
      options,
    );
  }
}
