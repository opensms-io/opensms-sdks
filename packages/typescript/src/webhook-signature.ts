/**
 * Webhook signature verification, usable without an API key.
 *
 * The API sends `X-OpenSMS-Signature: t=<unix seconds>,v1=<hex>` where
 * `v1 = hex(HMAC-SHA256(secret, "<t>.<raw body>"))` and `secret` is the full
 * `whsec_...` endpoint secret used verbatim. Parsing mirrors the server's
 * `internal/webhooks/signature.go`.
 * @module
 */
import { OpensmsError } from './errors.js';
import { fromWire, type WebhookEvent } from './models.js';
import { hmacSha256, toHex } from './internal/sha256.js';

/** Name of the signature header. */
export const SIGNATURE_HEADER = 'X-OpenSMS-Signature';

export interface VerifyOptions {
  /** Maximum age (and clock skew) in seconds. Defaults to `300`; the boundary is inclusive. */
  toleranceSeconds?: number;
  /** Current time in unix seconds. Defaults to the system clock. */
  now?: number;
}

type Outcome = 'valid' | 'invalid' | 'expired';

const encoder = new TextEncoder();
const decoder = new TextDecoder();

function bytesOf(payload: string | Uint8Array): Uint8Array {
  return typeof payload === 'string' ? encoder.encode(payload) : payload;
}

function parseHeader(header: string): { t: string; v1: string } | null {
  const fields: Record<string, string> = {};
  for (const rawPart of header.split(',')) {
    const part = rawPart.trim();
    const eq = part.indexOf('=');
    if (eq < 0) return null;
    const k = part.slice(0, eq);
    const v = part.slice(eq + 1);
    if (k === '' || v === '' || Object.prototype.hasOwnProperty.call(fields, k)) return null;
    fields[k] = v;
  }
  const keys = Object.keys(fields);
  if (keys.length !== 2 || fields.t === undefined || fields.v1 === undefined) return null;
  return { t: fields.t, v1: fields.v1 };
}

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function check(
  payload: string | Uint8Array,
  header: string | null | undefined,
  secret: string,
  opts: VerifyOptions,
): Outcome {
  const tolerance = opts.toleranceSeconds ?? 300;
  if (typeof secret !== 'string' || secret.trim() === '' || !(tolerance >= 0)) return 'invalid';
  if (typeof header !== 'string' || header === '') return 'invalid';
  const parsed = parseHeader(header);
  if (!parsed) return 'invalid';
  // Same order as the server: timestamp, then freshness, then the digest.
  if (!/^[+-]?\d+$/.test(parsed.t)) return 'invalid';
  const t = Number(parsed.t);
  if (!Number.isSafeInteger(t)) return 'invalid';
  const now = opts.now ?? Math.floor(Date.now() / 1000);
  if (Math.abs(now - t) > tolerance) return 'expired';
  if (!/^[0-9a-fA-F]{64}$/.test(parsed.v1)) return 'invalid';
  const body = bytesOf(payload);
  const prefix = encoder.encode(`${parsed.t}.`);
  const message = new Uint8Array(prefix.length + body.length);
  message.set(prefix);
  message.set(body, prefix.length);
  const expected = toHex(hmacSha256(encoder.encode(secret), message));
  return constantTimeEqual(expected, parsed.v1.toLowerCase()) ? 'valid' : 'invalid';
}

/**
 * Return `true` when `header` is a valid, fresh signature of `payload`.
 * Pass the raw request body exactly as received, before any JSON parsing.
 */
export function verifySignature(
  payload: string | Uint8Array,
  header: string | null | undefined,
  secret: string,
  options: VerifyOptions = {},
): boolean {
  return check(payload, header, secret, options) === 'valid';
}

/**
 * Verify the signature and parse the event envelope. Throws
 * {@link OpensmsError} with `status 0` and `code` `invalid_signature` or
 * `expired_signature`. The envelope keys are camelCased; `data` is returned
 * exactly as sent.
 */
export function constructEvent(
  payload: string | Uint8Array,
  header: string | null | undefined,
  secret: string,
  options: VerifyOptions = {},
): WebhookEvent {
  const outcome = check(payload, header, secret, options);
  if (outcome === 'expired') {
    throw new OpensmsError({
      status: 0,
      code: 'expired_signature',
      message: 'Webhook signature timestamp is outside the tolerance window.',
    });
  }
  if (outcome !== 'valid') {
    throw new OpensmsError({ status: 0, code: 'invalid_signature', message: 'Webhook signature is invalid.' });
  }
  const text = typeof payload === 'string' ? payload : decoder.decode(payload);
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch (err) {
    throw new OpensmsError({ status: 0, code: 'invalid_payload', message: 'Webhook body is not JSON.', cause: err });
  }
  const envelope = (raw ?? {}) as Record<string, unknown>;
  const { data, ...rest } = envelope;
  return { ...fromWire<Omit<WebhookEvent, 'data'>>(rest), data: (data ?? {}) as WebhookEvent['data'] };
}
