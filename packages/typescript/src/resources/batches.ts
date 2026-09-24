/**
 * The `batches` resource: bulk sends created in `ready` state and started explicitly.
 * @module
 */
import { toWire } from '../models.js';
import type {
  Batch,
  BatchItem,
  BatchStopResult,
  BatchValidationReport,
  CreateBatchFromCsvParams,
  CreateBatchParams,
  ListBatchItemsParams,
  Page,
  RequestOptions,
} from '../models.js';
import { Resource, seg, wireQuery } from './base.js';

/** Accessed as `client.batches`. */
export class Batches extends Resource {
  /** Create a batch from JSON items. Invalid rows are counted, not rejected. */
  create(params: CreateBatchParams, options?: RequestOptions): Promise<Batch> {
    return this.one({ method: 'POST', path: '/v1/messages/batch', json: toWire(params), idempotent: true }, options);
  }

  /**
   * Create a batch from CSV text with a `to,text[,sender_id,...]` header row.
   * Sent as `text/csv`; `dedupe: false` is sent as a multipart upload because
   * the API reads that flag only from form fields.
   */
  createFromCsv(csv: string, params: CreateBatchFromCsvParams = {}, options?: RequestOptions): Promise<Batch> {
    if (typeof csv !== 'string' || csv === '') throw new TypeError('OpenSMS: `csv` must be a non-empty string.');
    let raw: { body: string | FormData; contentType?: string };
    if (params.dedupe === false) {
      const form = new FormData();
      form.append('file', new Blob([csv], { type: 'text/csv' }), 'batch.csv');
      form.append('dedupe', 'false');
      raw = { body: form };
    } else {
      raw = { body: csv, contentType: 'text/csv' };
    }
    return this.one({ method: 'POST', path: '/v1/messages/batch', raw, idempotent: true }, options);
  }

  /** Get a batch and its counters. */
  get(id: string, options?: RequestOptions): Promise<Batch> {
    return this.one({ method: 'GET', path: `/v1/batches/${seg(id)}` }, options);
  }

  /** Per-row validation report. */
  validation(id: string, options?: RequestOptions): Promise<BatchValidationReport> {
    return this.one({ method: 'GET', path: `/v1/batches/${seg(id)}/validation` }, options);
  }

  /** Start sending a `ready` batch. */
  start(id: string, options?: RequestOptions): Promise<Batch> {
    return this.one({ method: 'POST', path: `/v1/batches/${seg(id)}/start`, idempotent: true }, options);
  }

  /** Stop a batch and cancel unsent items. */
  stop(id: string, options?: RequestOptions): Promise<BatchStopResult> {
    return this.one({ method: 'POST', path: `/v1/batches/${seg(id)}/stop`, idempotent: true }, options);
  }

  /** Messages created by a started batch. */
  listItems(id: string, params: ListBatchItemsParams = {}, options?: RequestOptions): Promise<Page<BatchItem>> {
    return this.page({ method: 'GET', path: `/v1/batches/${seg(id)}/items`, query: wireQuery(params) }, options);
  }
}
