/**
 * The `contacts` resource: the workspace address book.
 * @module
 */
import { toWire } from '../models.js';
import type { Contact, CreateContactParams, ListParams, Page, RequestOptions, UpdateContactParams } from '../models.js';
import { Resource, seg, wireQuery } from './base.js';

/** Accessed as `client.contacts`. */
export class Contacts extends Resource {
  list(params: ListParams = {}, options?: RequestOptions): Promise<Page<Contact>> {
    return this.page({ method: 'GET', path: '/v1/contacts', query: wireQuery(params) }, options);
  }

  /** Create a contact (`409` if the number already exists). */
  create(params: CreateContactParams, options?: RequestOptions): Promise<Contact> {
    return this.one({ method: 'POST', path: '/v1/contacts', json: toWire(params), idempotent: true }, options);
  }

  get(id: string, options?: RequestOptions): Promise<Contact> {
    return this.one({ method: 'GET', path: `/v1/contacts/${seg(id)}` }, options);
  }

  /** Partial update: omitted fields are kept. */
  update(id: string, params: UpdateContactParams, options?: RequestOptions): Promise<Contact> {
    return this.one({ method: 'PATCH', path: `/v1/contacts/${seg(id)}`, json: toWire(params) }, options);
  }

  delete(id: string, options?: RequestOptions): Promise<void> {
    return this.none({ method: 'DELETE', path: `/v1/contacts/${seg(id)}` }, options);
  }
}
