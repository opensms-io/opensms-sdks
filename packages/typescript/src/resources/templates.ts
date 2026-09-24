/**
 * The `templates` resource: reusable message bodies with `{{name}}` placeholders.
 * @module
 */
import { toWire } from '../models.js';
import type { CreateTemplateParams, ListParams, Page, RequestOptions, Template, UpdateTemplateParams } from '../models.js';
import { Resource, seg, wireQuery } from './base.js';

/** Accessed as `client.templates`. */
export class Templates extends Resource {
  list(params: ListParams = {}, options?: RequestOptions): Promise<Page<Template>> {
    return this.page({ method: 'GET', path: '/v1/templates', query: wireQuery(params) }, options);
  }

  create(params: CreateTemplateParams, options?: RequestOptions): Promise<Template> {
    return this.one({ method: 'POST', path: '/v1/templates', json: toWire(params), idempotent: true }, options);
  }

  get(id: string, options?: RequestOptions): Promise<Template> {
    return this.one({ method: 'GET', path: `/v1/templates/${seg(id)}` }, options);
  }

  update(id: string, params: UpdateTemplateParams, options?: RequestOptions): Promise<Template> {
    return this.one({ method: 'PATCH', path: `/v1/templates/${seg(id)}`, json: toWire(params) }, options);
  }

  delete(id: string, options?: RequestOptions): Promise<void> {
    return this.none({ method: 'DELETE', path: `/v1/templates/${seg(id)}` }, options);
  }
}
