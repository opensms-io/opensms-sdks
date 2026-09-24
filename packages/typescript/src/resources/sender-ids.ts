/**
 * The `senderIds` resource: sender ID registrations, availability checks,
 * fee quotes, documents and drafts.
 * @module
 */
import { toWire } from '../models.js';
import type {
  CreateSenderIdDraftParams,
  CreateSenderIdParams,
  ListParams,
  Page,
  RequestOptions,
  SenderDocument,
  SenderId,
  SenderIdCheckParams,
  SenderIdCheckResult,
  SenderIdDraft,
  SenderIdQuote,
  SenderIdQuoteParams,
  UpdateSenderIdDraftParams,
  UpdateSenderIdParams,
} from '../models.js';
import { Resource, seg, wireQuery } from './base.js';

/** Accessed as `client.senderIds`. */
export class SenderIds extends Resource {
  list(params: ListParams = {}, options?: RequestOptions): Promise<Page<SenderId>> {
    return this.page({ method: 'GET', path: '/v1/sender-ids', query: wireQuery(params) }, options);
  }

  get(id: string, options?: RequestOptions): Promise<SenderId> {
    return this.one({ method: 'GET', path: `/v1/sender-ids/${seg(id)}` }, options);
  }

  /** Register a sender ID. May charge fees, so it is never retried. */
  create(params: CreateSenderIdParams, options?: RequestOptions): Promise<SenderId> {
    return this.one({ method: 'POST', path: '/v1/sender-ids', json: toWire(params) }, options);
  }

  /** Amend a pending or rejected registration. */
  update(id: string, params: UpdateSenderIdParams, options?: RequestOptions): Promise<SenderId> {
    return this.one({ method: 'PATCH', path: `/v1/sender-ids/${seg(id)}`, json: toWire(params) }, options);
  }

  delete(id: string, options?: RequestOptions): Promise<void> {
    return this.none({ method: 'DELETE', path: `/v1/sender-ids/${seg(id)}` }, options);
  }

  /** Check whether a value is valid and available. */
  check(params: SenderIdCheckParams, options?: RequestOptions): Promise<SenderIdCheckResult> {
    return this.one({ method: 'GET', path: '/v1/sender-ids/check', query: wireQuery(params) }, options);
  }

  /** Registration fee quote; `countries` is sent comma separated. */
  quote(params: SenderIdQuoteParams, options?: RequestOptions): Promise<SenderIdQuote> {
    return this.one({ method: 'GET', path: '/v1/sender-ids/quote', query: wireQuery(params) }, options);
  }

  /** Uploaded sender documents (upload and download are console only). */
  listDocuments(options?: RequestOptions): Promise<SenderDocument[]> {
    return this.wrapped('items', { method: 'GET', path: '/v1/sender-documents' }, options);
  }

  listDrafts(params: ListParams = {}, options?: RequestOptions): Promise<Page<SenderIdDraft>> {
    return this.page({ method: 'GET', path: '/v1/sender-id-drafts', query: wireQuery(params) }, options);
  }

  /** Create a draft. Not idempotent, so never retried. */
  createDraft(params: CreateSenderIdDraftParams = {}, options?: RequestOptions): Promise<SenderIdDraft> {
    return this.one({ method: 'POST', path: '/v1/sender-id-drafts', json: toWire(params) }, options);
  }

  getDraft(id: string, options?: RequestOptions): Promise<SenderIdDraft> {
    return this.one({ method: 'GET', path: `/v1/sender-id-drafts/${seg(id)}` }, options);
  }

  /** Update a draft; `version` must be current (`409` on mismatch). */
  updateDraft(id: string, params: UpdateSenderIdDraftParams, options?: RequestOptions): Promise<SenderIdDraft> {
    return this.one({ method: 'PATCH', path: `/v1/sender-id-drafts/${seg(id)}`, json: toWire(params) }, options);
  }

  deleteDraft(id: string, options?: RequestOptions): Promise<void> {
    return this.none({ method: 'DELETE', path: `/v1/sender-id-drafts/${seg(id)}` }, options);
  }
}
