/**
 * The `messages` resource: send, list, inspect and cancel SMS.
 * @module
 */
import { toWire } from '../models.js';
import type { Attempt, ListMessagesParams, Message, Page, RequestOptions, SendMessageParams } from '../models.js';
import { Resource, seg, wireQuery } from './base.js';

/** Accessed as `client.messages`. */
export class Messages extends Resource {
  /** Send one SMS. Idempotent: the SDK sends an Idempotency-Key and retries safely. */
  send(params: SendMessageParams, options?: RequestOptions): Promise<Message> {
    return this.one({ method: 'POST', path: '/v1/messages', json: toWire(params), idempotent: true }, options);
  }

  /** List messages, newest first. */
  list(params: ListMessagesParams = {}, options?: RequestOptions): Promise<Page<Message>> {
    return this.page({ method: 'GET', path: '/v1/messages', query: wireQuery(params) }, options);
  }

  /** Get one message. */
  get(id: string, options?: RequestOptions): Promise<Message> {
    return this.one({ method: 'GET', path: `/v1/messages/${seg(id)}` }, options);
  }

  /** Provider submission attempts for a message. */
  attempts(id: string, options?: RequestOptions): Promise<Attempt[]> {
    return this.array({ method: 'GET', path: `/v1/messages/${seg(id)}/attempts` }, options);
  }

  /** Cancel a `queued` or `scheduled` message (`409` otherwise). Never retried. */
  cancel(id: string, options?: RequestOptions): Promise<Message> {
    return this.one({ method: 'POST', path: `/v1/messages/${seg(id)}/cancel` }, options);
  }
}
