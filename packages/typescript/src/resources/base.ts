/**
 * Shared plumbing for resource classes: id checks, path escaping and the
 * call helpers that decode responses into models. Not part of the public API.
 * @module
 */
import type { RequestSpec, Transport } from '../transport.js';
import { fromWire, pageFromWire, toWire, type Page, type RequestOptions } from '../models.js';

/** Escape one path segment after checking it is a non-empty string. */
export function seg(value: string | number, name = 'id'): string {
  if ((typeof value !== 'string' && typeof value !== 'number') || String(value) === '') {
    throw new TypeError(`OpenSMS: \`${name}\` must be a non-empty string.`);
  }
  return encodeURIComponent(String(value));
}

/** Convert params to wire form for use as a query object. */
export function wireQuery(params: object | undefined): Record<string, unknown> | undefined {
  return params ? (toWire(params) as Record<string, unknown>) : undefined;
}

type Spec = Omit<RequestSpec, 'idempotencyKey' | 'signal'>;

export abstract class Resource {
  /** @internal */
  constructor(protected readonly http: Transport) {
    // Bind every method so `client.messages.list` can be passed around (e.g. to `paginate`).
    const proto = Object.getPrototypeOf(this) as Record<string, unknown>;
    for (const name of Object.getOwnPropertyNames(proto)) {
      const fn = proto[name];
      if (name !== 'constructor' && typeof fn === 'function') {
        (this as Record<string, unknown>)[name] = (fn as (...a: unknown[]) => unknown).bind(this);
      }
    }
  }

  private dispatch(spec: Spec, opts?: RequestOptions): Promise<unknown> {
    return this.http.request({
      ...spec,
      idempotencyKey: spec.idempotent ? opts?.idempotencyKey : undefined,
      signal: opts?.signal,
    });
  }

  /** Call and decode a single object. */
  protected async one<T>(spec: Spec, opts?: RequestOptions): Promise<T> {
    return fromWire<T>(await this.dispatch(spec, opts));
  }

  /** Call and decode a `{ items, next_cursor }` page. */
  protected async page<T>(spec: Spec, opts?: RequestOptions): Promise<Page<T>> {
    return pageFromWire<T>(await this.dispatch(spec, opts));
  }

  /** Call and decode a bare JSON array. */
  protected async array<T>(spec: Spec, opts?: RequestOptions): Promise<T[]> {
    const raw = await this.dispatch(spec, opts);
    return Array.isArray(raw) ? fromWire<T[]>(raw) : [];
  }

  /** Call and decode a list wrapped in `{ [key]: [...] }`. */
  protected async wrapped<T>(key: string, spec: Spec, opts?: RequestOptions): Promise<T[]> {
    const raw = (await this.dispatch(spec, opts)) as Record<string, unknown> | undefined;
    const list = raw?.[key];
    return Array.isArray(list) ? fromWire<T[]>(list) : [];
  }

  /** Call an endpoint that answers `204 No Content`. */
  protected async none(spec: Spec, opts?: RequestOptions): Promise<void> {
    await this.dispatch(spec, opts);
  }
}
