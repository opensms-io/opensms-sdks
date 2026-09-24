/**
 * The `contactGroups` resource: named sets of contacts and group sends.
 * @module
 */
import { toWire } from '../models.js';
import type {
  Batch,
  ContactGroup,
  ContactGroupSendParams,
  CreateContactGroupParams,
  ListParams,
  Page,
  RequestOptions,
  UpdateContactGroupParams,
} from '../models.js';
import { Resource, seg, wireQuery } from './base.js';

/** Accessed as `client.contactGroups`. */
export class ContactGroups extends Resource {
  list(params: ListParams = {}, options?: RequestOptions): Promise<Page<ContactGroup>> {
    return this.page({ method: 'GET', path: '/v1/contact-groups', query: wireQuery(params) }, options);
  }

  create(params: CreateContactGroupParams, options?: RequestOptions): Promise<ContactGroup> {
    return this.one({ method: 'POST', path: '/v1/contact-groups', json: toWire(params), idempotent: true }, options);
  }

  get(id: string, options?: RequestOptions): Promise<ContactGroup> {
    return this.one({ method: 'GET', path: `/v1/contact-groups/${seg(id)}` }, options);
  }

  update(id: string, params: UpdateContactGroupParams, options?: RequestOptions): Promise<ContactGroup> {
    return this.one({ method: 'PATCH', path: `/v1/contact-groups/${seg(id)}`, json: toWire(params) }, options);
  }

  delete(id: string, options?: RequestOptions): Promise<void> {
    return this.none({ method: 'DELETE', path: `/v1/contact-groups/${seg(id)}` }, options);
  }

  /** Send `text` or a template to every contact in the group. Returns a running Batch. */
  send(id: string, params: ContactGroupSendParams, options?: RequestOptions): Promise<Batch> {
    return this.one(
      { method: 'POST', path: `/v1/contact-groups/${seg(id)}/send`, json: toWire(params), idempotent: true },
      options,
    );
  }
}
