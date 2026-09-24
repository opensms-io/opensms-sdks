/**
 * The `webhooks` resource: endpoints, deliveries, replays, and signature
 * verification helpers.
 * @module
 */
import { toWire } from '../models.js';
import type {
  CreateWebhookParams,
  ListParams,
  Page,
  ReplayDeliveryParams,
  RequestOptions,
  StatusResult,
  UpdateWebhookParams,
  WebhookDelivery,
  WebhookEndpoint,
  WebhookEvent,
} from '../models.js';
import { constructEvent, verifySignature, type VerifyOptions } from '../webhook-signature.js';
import { Resource, seg, wireQuery } from './base.js';

/** Accessed as `client.webhooks`. */
export class Webhooks extends Resource {
  list(params: ListParams = {}, options?: RequestOptions): Promise<Page<WebhookEndpoint>> {
    return this.page({ method: 'GET', path: '/v1/webhooks', query: wireQuery(params) }, options);
  }

  /** Create an endpoint. The response carries `secret` once: store it. */
  create(params: CreateWebhookParams, options?: RequestOptions): Promise<WebhookEndpoint> {
    return this.one({ method: 'POST', path: '/v1/webhooks', json: toWire(params), idempotent: true }, options);
  }

  get(id: string, options?: RequestOptions): Promise<WebhookEndpoint> {
    return this.one({ method: 'GET', path: `/v1/webhooks/${seg(id)}` }, options);
  }

  /** Full replacement (`PUT`): `url`, `events` and `enabled` are all required. */
  update(id: string, params: UpdateWebhookParams, options?: RequestOptions): Promise<WebhookEndpoint> {
    return this.one(
      { method: 'PUT', path: `/v1/webhooks/${seg(id)}`, json: toWire(params), idempotent: true },
      options,
    );
  }

  delete(id: string, options?: RequestOptions): Promise<void> {
    return this.none({ method: 'DELETE', path: `/v1/webhooks/${seg(id)}`, idempotent: true }, options);
  }

  /** Queue a `webhook.test` delivery. */
  test(id: string, options?: RequestOptions): Promise<StatusResult> {
    return this.one({ method: 'POST', path: `/v1/webhooks/${seg(id)}/test`, idempotent: true }, options);
  }

  listDeliveries(id: string, params: ListParams = {}, options?: RequestOptions): Promise<Page<WebhookDelivery>> {
    return this.page({ method: 'GET', path: `/v1/webhooks/${seg(id)}/deliveries`, query: wireQuery(params) }, options);
  }

  /** Re-queue a delivery. `generation` comes from the delivery; `reason` is 5..1000 chars. */
  replayDelivery(
    id: string,
    deliveryId: number | string,
    params: ReplayDeliveryParams,
    options?: RequestOptions,
  ): Promise<StatusResult> {
    return this.one(
      {
        method: 'POST',
        path: `/v1/webhooks/${seg(id)}/deliveries/${seg(deliveryId, 'deliveryId')}/replay`,
        json: toWire(params),
        idempotent: true,
      },
      options,
    );
  }

  /** See {@link verifySignature}. */
  verifySignature(
    payload: string | Uint8Array,
    header: string | null | undefined,
    secret: string,
    options?: VerifyOptions,
  ): boolean {
    return verifySignature(payload, header, secret, options);
  }

  /** See {@link constructEvent}. */
  constructEvent(
    payload: string | Uint8Array,
    header: string | null | undefined,
    secret: string,
    options?: VerifyOptions,
  ): WebhookEvent {
    return constructEvent(payload, header, secret, options);
  }
}
