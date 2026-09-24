/**
 * HTTP transport: the only code that talks to the network. Owns
 * authentication headers, JSON encoding, per-attempt timeouts, the
 * Idempotency-Key, retries with backoff, and turning non-2xx responses into
 * {@link OpensmsError}. Resources depend on this, never on `fetch` directly.
 * @module
 */
import { OpensmsError } from './errors.js';
import type { OpensmsOptions } from './models.js';
import { uuidv4 } from './internal/uuid.js';
import { VERSION } from './version.js';

export const DEFAULT_BASE_URL = 'https://api.opensms.io';
const DEFAULT_TIMEOUT_MS = 30_000;
const DEFAULT_MAX_RETRIES = 2;
const MAX_RETRY_AFTER_SECONDS = 60;
const RETRYABLE_STATUS = new Set([429, 500, 502, 503, 504]);
const USER_AGENT = `opensms-typescript/${VERSION}`;
const KEY_PATTERN = /^sk_(test|live)_.{13,}$/s;

const defaultSleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

/** One API call, already in wire form (snake_case body and query). */
export interface RequestSpec {
  method: 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE';
  /** Path starting with `/v1/`, with every parameter already escaped. */
  path: string;
  /** Query parameters. `undefined`/`null` are skipped; arrays are comma joined. */
  query?: Record<string, unknown>;
  /** JSON body (serialized here). */
  json?: unknown;
  /** Non-JSON body: CSV text or multipart form data. */
  raw?: { body: string | FormData; contentType?: string };
  /**
   * Send an Idempotency-Key. `true` generates one unless `idempotencyKey` is
   * given. POSTs are retried only when a key is sent.
   */
  idempotent?: boolean;
  idempotencyKey?: string;
  signal?: AbortSignal;
}

/** Validate a secret key the same way the API does (`auth.ValidSecret`). */
export function isValidApiKey(key: unknown): key is string {
  return typeof key === 'string' && KEY_PATTERN.test(key);
}

export class Transport {
  readonly baseUrl: string;
  readonly environment: 'sandbox' | 'live';
  private readonly apiKey: string;
  private readonly timeoutMs: number;
  private readonly maxRetries: number;
  private readonly fetchImpl: typeof fetch;
  private readonly sleep: (ms: number) => Promise<void>;

  constructor(options: OpensmsOptions) {
    if (!options || !isValidApiKey(options.apiKey)) {
      throw new TypeError(
        'OpenSMS: `apiKey` must start with sk_test_ or sk_live_ followed by more than 12 characters.',
      );
    }
    const f = options.fetch ?? (globalThis as { fetch?: typeof fetch }).fetch;
    if (typeof f !== 'function') {
      throw new TypeError('OpenSMS: no global fetch found. Use Node 18+ or pass `fetch` in the options.');
    }
    const maxRetries = options.maxRetries ?? DEFAULT_MAX_RETRIES;
    if (!Number.isInteger(maxRetries) || maxRetries < 0) {
      throw new TypeError('OpenSMS: `maxRetries` must be a non-negative integer.');
    }
    this.apiKey = options.apiKey;
    this.environment = options.apiKey.startsWith('sk_live_') ? 'live' : 'sandbox';
    this.baseUrl = (options.baseUrl ?? DEFAULT_BASE_URL).replace(/\/+$/, '');
    this.timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
    this.maxRetries = maxRetries;
    this.fetchImpl = f;
    this.sleep = options.sleep ?? defaultSleep;
  }

  /**
   * Perform a request and return the decoded JSON body (`undefined` for an
   * empty body such as `204`). Throws {@link OpensmsError} on a final non-2xx
   * response or a transport failure that survives all attempts.
   */
  async request(spec: RequestSpec): Promise<unknown> {
    const url = this.baseUrl + spec.path + buildQuery(spec.query);
    const headers: Record<string, string> = {
      Authorization: `Bearer ${this.apiKey}`,
      Accept: 'application/json',
      'User-Agent': USER_AGENT,
    };
    let body: string | FormData | undefined;
    if (spec.raw) {
      body = spec.raw.body;
      if (spec.raw.contentType) headers['Content-Type'] = spec.raw.contentType;
    } else if (spec.json !== undefined) {
      body = JSON.stringify(spec.json);
      headers['Content-Type'] = 'application/json';
    }
    const idemKey = spec.idempotencyKey ?? (spec.idempotent ? uuidv4() : undefined);
    if (idemKey !== undefined) headers['Idempotency-Key'] = idemKey;
    const retryable = spec.method !== 'POST' || idemKey !== undefined;

    for (let attempt = 1; ; attempt++) {
      const canRetry = retryable && attempt <= this.maxRetries;
      let res: Response;
      let text: string;
      const controller = new AbortController();
      const onAbort = () => controller.abort(spec.signal?.reason);
      spec.signal?.addEventListener('abort', onAbort, { once: true });
      const timer = setTimeout(() => controller.abort(new Error('timeout')), this.timeoutMs);
      try {
        if (spec.signal?.aborted) throw spec.signal.reason ?? new Error('aborted');
        res = await this.fetchImpl(url, { method: spec.method, headers, body, signal: controller.signal });
        text = res.status === 204 ? '' : await res.text();
      } catch (err) {
        if (spec.signal?.aborted) {
          throw new OpensmsError({ status: 0, message: 'OpenSMS request aborted', cause: err });
        }
        if (canRetry) {
          await this.sleep(backoffMs(attempt));
          continue;
        }
        throw new OpensmsError({
          status: 0,
          message: `OpenSMS request failed: ${err instanceof Error ? err.message : String(err)}`,
          cause: err,
        });
      } finally {
        clearTimeout(timer);
        spec.signal?.removeEventListener('abort', onAbort);
      }

      if (res.status >= 200 && res.status < 300) return decodeJson(text);

      const retryAfter = parseRetryAfter(res.headers.get('retry-after'));
      const error = OpensmsError.fromResponse(res.status, text, res.headers, retryAfter);
      if (!canRetry || !RETRYABLE_STATUS.has(res.status)) throw error;
      if (retryAfter !== null && retryAfter > MAX_RETRY_AFTER_SECONDS) throw error;
      await this.sleep(retryAfter !== null ? retryAfter * 1000 : backoffMs(attempt));
    }
  }
}

/** Full-jitter exponential backoff: `random(0, min(8 s, 0.5 s * 2^(n-1)))`. */
function backoffMs(attempt: number): number {
  return Math.random() * Math.min(8000, 500 * 2 ** (attempt - 1));
}

/** Parse `Retry-After` (integer seconds or an HTTP date) into seconds. */
export function parseRetryAfter(value: string | null, now: number = Date.now()): number | null {
  if (value === null) return null;
  const v = value.trim();
  if (/^\d+$/.test(v)) return Number(v);
  const at = Date.parse(v);
  if (Number.isNaN(at)) return null;
  return Math.max(0, Math.ceil((at - now) / 1000));
}

function buildQuery(params: Record<string, unknown> | undefined): string {
  if (!params) return '';
  const sp = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) {
    if (v === undefined || v === null) continue;
    sp.append(k, Array.isArray(v) ? v.map(String).join(',') : v instanceof Date ? v.toISOString() : String(v));
  }
  // Commas are legal in a query and keep list values readable (`countries=KE,NG`).
  const s = sp.toString().replace(/%2C/gi, ',');
  return s ? `?${s}` : '';
}

function decodeJson(text: string): unknown {
  if (text === '') return undefined;
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}
