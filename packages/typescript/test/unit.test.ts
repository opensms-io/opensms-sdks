/**
 * Offline mock-transport tests: CONFORMANCE.md "Mock-transport unit tests" 1..20.
 * Every request goes through an injected fetch that records it and returns a
 * scripted response; sleeping is replaced by a recorder.
 */
import { describe, expect, it } from 'vitest';
import {
  constructEvent,
  Opensms,
  OpensmsError,
  VERSION,
  verifySignature,
  type ListBatchItemsParams,
  type Message,
} from '../src/index.js';

const KEY = 'sk_test_' + 'A'.repeat(32);
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

type Scripted =
  | { status: number; body?: unknown; text?: string; headers?: Record<string, string> }
  | { throws: Error };

interface Recorded {
  url: string;
  method: string;
  headers: Record<string, string>;
  body: unknown;
}

function harness(script: Scripted[], opts: { maxRetries?: number; baseUrl?: string } = {}) {
  const calls: Recorded[] = [];
  const sleeps: number[] = [];
  let i = 0;
  const fetchImpl = (async (url: string, init: RequestInit) => {
    const headers: Record<string, string> = {};
    for (const [k, v] of Object.entries((init.headers ?? {}) as Record<string, string>)) headers[k.toLowerCase()] = v;
    calls.push({ url, method: init.method ?? 'GET', headers, body: init.body });
    const step = script[Math.min(i, script.length - 1)]!;
    i++;
    if ('throws' in step) throw step.throws;
    const text = step.text ?? (step.body === undefined ? '' : JSON.stringify(step.body));
    const isProblem = step.status >= 400 && step.text === undefined;
    const h = new Headers({
      'content-type': isProblem ? 'application/problem+json' : 'application/json',
      ...(step.headers ?? {}),
    });
    return new Response(step.status === 204 ? null : text, { status: step.status, headers: h });
  }) as unknown as typeof fetch;
  const client = new Opensms({
    apiKey: KEY,
    fetch: fetchImpl,
    sleep: async (ms) => {
      sleeps.push(ms);
    },
    ...opts,
  });
  return { client, calls, sleeps };
}

const problem = (status: number, detail: string, extra: Record<string, unknown> = {}) => ({
  type: 'about:blank',
  title: 'Error',
  status,
  detail,
  ...extra,
});

const message = { id: '11111111-1111-4111-8111-111111111111', status: 'queued', price: '0.000000' };

async function catchErr(p: Promise<unknown>): Promise<OpensmsError> {
  try {
    await p;
  } catch (e) {
    expect(e).toBeInstanceOf(OpensmsError);
    return e as OpensmsError;
  }
  throw new Error('expected an OpensmsError');
}

describe('1. header injection', () => {
  it('sends auth, accept, user-agent and JSON content type, never workspace or environment', async () => {
    const { client, calls } = harness([{ status: 201, body: message }, { status: 200, body: message }]);
    await client.messages.send({ to: '+254700000012', text: 'hi' });
    await client.messages.get(message.id);
    for (const c of calls) {
      expect(c.headers.authorization).toBe(`Bearer ${KEY}`);
      expect(c.headers.accept).toBe('application/json');
      expect(c.headers['user-agent']).toBe(`opensms-typescript/${VERSION}`);
      expect(c.headers['x-workspace-id']).toBeUndefined();
      expect(c.headers['x-environment']).toBeUndefined();
    }
    expect(calls[0]!.headers['content-type']).toBe('application/json');
    expect(calls[1]!.headers['content-type']).toBeUndefined();
  });
});

describe('2. base URL', () => {
  it('defaults to https://api.opensms.io', async () => {
    const { client, calls } = harness([{ status: 200, body: { items: [], next_cursor: null } }]);
    expect(client.baseUrl).toBe('https://api.opensms.io');
    await client.messages.list();
    expect(calls[0]!.url).toBe('https://api.opensms.io/v1/messages');
  });
  it('strips trailing slashes from a custom base URL', async () => {
    const { client, calls } = harness([{ status: 201, body: message }], { baseUrl: 'http://host/' });
    await client.messages.send({ to: '+254700000012', text: 'x' });
    expect(calls[0]!.url).toBe('http://host/v1/messages');
  });
});

describe('3. key validation', () => {
  it.each([undefined, '', 'pk_test_x', 'sk_test_short', 'not_a_key', 'sk_test_123456789012'])(
    'rejects %s at construction',
    (apiKey) => {
      expect(() => new Opensms({ apiKey: apiKey as string, fetch: (() => {}) as never })).toThrow(TypeError);
    },
  );
  it('accepts live and test keys and reports the environment', () => {
    const live = new Opensms({ apiKey: 'sk_live_' + 'B'.repeat(32) });
    const test = new Opensms({ apiKey: 'sk_test_' + 'B'.repeat(32) });
    expect(live.environment).toBe('live');
    expect(test.environment).toBe('sandbox');
    expect(new Opensms({ apiKey: 'sk_test_1234567890123' }).environment).toBe('sandbox');
  });
});

describe('4. body mapping', () => {
  it('maps camelCase params to exact snake_case keys and drops unset optionals', async () => {
    const { client, calls } = harness([{ status: 201, body: message }, { status: 201, body: message }]);
    await client.messages.send({
      to: '+254700000012',
      text: 'hi',
      senderId: 'ACME',
      trafficType: 'marketing',
      scheduledAt: new Date('2030-01-01T00:00:00Z'),
      callbackUrl: 'https://example.com/cb',
      metadata: { orderId: 7, nested: { someKey: 1 } },
    });
    const body = JSON.parse(calls[0]!.body as string);
    expect(Object.keys(body).sort()).toEqual(
      ['callback_url', 'metadata', 'scheduled_at', 'sender_id', 'text', 'to', 'traffic_type'].sort(),
    );
    expect(body.scheduled_at).toBe('2030-01-01T00:00:00.000Z');
    expect(body.metadata).toEqual({ orderId: 7, nested: { someKey: 1 } }); // free-form, untouched

    await client.messages.send({ to: '+254700000012', text: 'hi', senderId: undefined });
    const body2 = JSON.parse(calls[1]!.body as string);
    expect(body2).toEqual({ to: '+254700000012', text: 'hi' });
    expect(calls[1]!.body as string).not.toContain('null');
  });

  it('keeps template variables verbatim in contact group sends', async () => {
    const { client, calls } = harness([{ status: 200, body: { id: 'b1', status: 'running' } }]);
    await client.contactGroups.send('g1', { templateId: 't1', variables: { firstName: 'Ada' } });
    expect(JSON.parse(calls[0]!.body as string)).toEqual({ template_id: 't1', variables: { firstName: 'Ada' } });
  });
});

describe('5. Idempotency-Key', () => {
  it('generates a UUID for send, sends an explicit key verbatim, and none on get', async () => {
    const { client, calls } = harness([{ status: 201, body: message }]);
    await client.messages.send({ to: '+254700000012', text: 'a' });
    await client.messages.send({ to: '+254700000012', text: 'a' }, { idempotencyKey: 'my-key-1' });
    await client.messages.get(message.id);
    expect(calls[0]!.headers['idempotency-key']).toMatch(UUID_RE);
    expect(calls[0]!.headers['idempotency-key']).toHaveLength(36);
    expect(calls[1]!.headers['idempotency-key']).toBe('my-key-1');
    expect(calls[2]!.headers['idempotency-key']).toBeUndefined();
  });
  it('never sends a key on methods without idempotency support', async () => {
    const { client, calls } = harness([{ status: 200, body: { valid: true, attempts_left: 4 } }]);
    await client.otp.verify({ otpId: 'o1', code: '123456' }, { idempotencyKey: 'ignored' });
    expect(calls[0]!.headers['idempotency-key']).toBeUndefined();
  });
});

describe('6. retry on 429 with Retry-After', () => {
  it('waits the requested seconds and reuses the same Idempotency-Key', async () => {
    const { client, calls, sleeps } = harness([
      { status: 429, body: problem(429, 'rate limited'), headers: { 'Retry-After': '2' } },
      { status: 201, body: message },
    ]);
    const m = await client.messages.send({ to: '+254700000012', text: 'x' });
    expect(m.id).toBe(message.id);
    expect(calls).toHaveLength(2);
    expect(sleeps).toEqual([2000]);
    expect(calls[0]!.headers['idempotency-key']).toMatch(UUID_RE);
    expect(calls[1]!.headers['idempotency-key']).toBe(calls[0]!.headers['idempotency-key']);
  });
  it('honours an HTTP-date Retry-After', async () => {
    const at = new Date(Date.now() + 3000).toUTCString();
    const { client, sleeps } = harness([
      { status: 503, body: problem(503, 'busy'), headers: { 'Retry-After': at } },
      { status: 200, body: message },
    ]);
    await client.messages.get(message.id);
    expect(sleeps).toHaveLength(1);
    expect(sleeps[0]!).toBeGreaterThanOrEqual(0);
    expect(sleeps[0]!).toBeLessThanOrEqual(4000);
  });
});

describe('7. retry on 503 without Retry-After', () => {
  it('backs off with full jitter within [0, 0.5 s]', async () => {
    const { client, calls, sleeps } = harness([
      { status: 503, body: problem(503, 'database unavailable') },
      { status: 200, body: message },
    ]);
    const m = await client.messages.get(message.id);
    expect(m.id).toBe(message.id);
    expect(calls).toHaveLength(2);
    expect(sleeps).toHaveLength(1);
    expect(sleeps[0]!).toBeGreaterThanOrEqual(0);
    expect(sleeps[0]!).toBeLessThanOrEqual(500);
  });
});

describe('8. retries exhausted', () => {
  it('throws the final 500 after exactly 3 requests', async () => {
    const { client, calls } = harness([{ status: 500, body: problem(500, 'boom') }], { maxRetries: 2 });
    const e = await catchErr(client.messages.get(message.id));
    expect(e.status).toBe(500);
    expect(calls).toHaveLength(3);
  });
  it('maxRetries 0 disables retries', async () => {
    const { client, calls } = harness([{ status: 500, body: problem(500, 'boom') }], { maxRetries: 0 });
    await catchErr(client.messages.get(message.id));
    expect(calls).toHaveLength(1);
  });
});

describe('9. Retry-After too large', () => {
  it('does not retry and exposes retryAfter', async () => {
    const { client, calls, sleeps } = harness([
      { status: 429, body: problem(429, 'slow down'), headers: { 'Retry-After': '120' } },
      { status: 200, body: message },
    ]);
    const e = await catchErr(client.messages.get(message.id));
    expect(e.status).toBe(429);
    expect(e.retryAfter).toBe(120);
    expect(calls).toHaveLength(1);
    expect(sleeps).toEqual([]);
  });
});

describe('10. no retry on client errors', () => {
  it.each([400, 401, 402, 403, 404, 409, 410, 413, 422])('status %i fails after 1 request', async (status) => {
    const { client, calls } = harness([{ status, body: problem(status, 'nope') }, { status: 201, body: message }]);
    const e = await catchErr(client.messages.send({ to: '+254700000012', text: 'x' }));
    expect(e.status).toBe(status);
    expect(calls).toHaveLength(1);
  });
});

describe('11. no retry for non-idempotent POSTs', () => {
  it('otp.verify on 503 fails after 1 request', async () => {
    const { client, calls } = harness([{ status: 503, body: problem(503, 'x') }, { status: 200, body: {} }]);
    const e = await catchErr(client.otp.verify({ otpId: 'o1', code: '123456' }));
    expect(e.status).toBe(503);
    expect(calls).toHaveLength(1);
  });
  it('messages.cancel on 503 fails after 1 request', async () => {
    const { client, calls } = harness([{ status: 503, body: problem(503, 'x') }, { status: 200, body: message }]);
    await catchErr(client.messages.cancel(message.id));
    expect(calls).toHaveLength(1);
  });
  it('other non-idempotent POSTs are not retried on a network error either', async () => {
    const { client, calls } = harness([{ throws: new TypeError('fetch failed') }]);
    await catchErr(client.suppressions.create({ e164: '+254700000099', reason: 'manual' }));
    await catchErr(client.suppressions.import([{ e164: '+254700000099', reason: 'manual' }]));
    await catchErr(client.senderIds.create({ value: 'ACME', kind: 'alphanumeric', countries: ['KE'], documents: [] }));
    await catchErr(client.senderIds.createDraft({}));
    expect(calls).toHaveLength(4);
  });
});

describe('12. network errors', () => {
  it('retries a GET after transport failures and then succeeds', async () => {
    const { client, calls, sleeps } = harness([
      { throws: new TypeError('fetch failed') },
      { throws: new TypeError('fetch failed') },
      { status: 200, body: message },
    ]);
    const m = await client.messages.get(message.id);
    expect(m.id).toBe(message.id);
    expect(calls).toHaveLength(3);
    expect(sleeps).toHaveLength(2);
    expect(sleeps[1]!).toBeLessThanOrEqual(1000);
  });
  it('a persistent failure becomes status 0', async () => {
    const { client, calls } = harness([{ throws: new TypeError('fetch failed') }]);
    const e = await catchErr(client.messages.get(message.id));
    expect(e.status).toBe(0);
    expect(e.message).toContain('fetch failed');
    expect(calls).toHaveLength(3);
  });
  it('a per-attempt timeout is treated as a network error', async () => {
    let n = 0;
    const slow = ((_: string, init: RequestInit) =>
      new Promise((_resolve, reject) => {
        n++;
        init.signal?.addEventListener('abort', () => reject(new Error('timeout')));
      })) as unknown as typeof fetch;
    const client = new Opensms({ apiKey: KEY, fetch: slow, timeoutMs: 5, maxRetries: 1, sleep: async () => {} });
    const e = await catchErr(client.messages.get(message.id));
    expect(e.status).toBe(0);
    expect(n).toBe(2);
  });
});

describe('13. error mapping', () => {
  it('maps every problem field', async () => {
    const body = {
      type: 'https://api.opensms.io/problems/invalid_message_id',
      title: 'Bad Request',
      status: 400,
      detail: 'Message ID must be a valid UUID.',
      code: 'invalid_message_id',
      trace_id: 't1',
      errors: { to: ['bad'] },
    };
    const { client } = harness([{ status: 400, body }]);
    const e = await catchErr(client.messages.get('x'));
    expect(e.status).toBe(400);
    expect(e.type).toBe(body.type);
    expect(e.title).toBe('Bad Request');
    expect(e.detail).toBe(body.detail);
    expect(e.code).toBe('invalid_message_id');
    expect(e.traceId).toBe('t1');
    expect(e.errors?.to).toEqual(['bad']);
    expect(e.message).toBe(body.detail);
    expect(e.body).toEqual(body);
    expect(e.name).toBe('OpensmsError');
  });
  it('about:blank without code gives a null code', async () => {
    const { client } = harness([{ status: 400, body: problem(400, 'invalid cursor') }]);
    const e = await catchErr(client.messages.list({ cursor: 'garbage' }));
    expect(e.code).toBeNull();
    expect(e.type).toBe('about:blank');
  });
  it('captures X-Request-ID', async () => {
    const { client } = harness([
      { status: 422, body: problem(422, 'destination is suppressed'), headers: { 'X-Request-ID': 'r1' } },
    ]);
    const e = await catchErr(client.messages.send({ to: '+254700000012', text: 'x' }));
    expect(e.requestId).toBe('r1');
    expect(e.detail).toBe('destination is suppressed');
  });
  it('keeps an HTML body as raw text', async () => {
    const html = '<html><body>Bad gateway</body></html>';
    const { client } = harness([{ status: 502, text: html, headers: { 'content-type': 'text/html' } }], {
      maxRetries: 0,
    });
    const e = await catchErr(client.messages.get(message.id));
    expect(e.status).toBe(502);
    expect(e.detail).toBeNull();
    expect(e.title).toBeNull();
    expect(e.body).toBe(html);
    expect(e.message).toBe('OpenSMS request failed with status 502');
  });
});

describe('14. 204 handling', () => {
  it('contacts.delete returns void without parsing', async () => {
    const { client, calls } = harness([{ status: 204 }]);
    await expect(client.contacts.delete('c1')).resolves.toBeUndefined();
    expect(calls[0]!.method).toBe('DELETE');
    expect(calls[0]!.url).toBe('https://api.opensms.io/v1/contacts/c1');
  });
});

describe('15. pagination', () => {
  it('follows next_cursor and keeps the limit', async () => {
    const { client, calls } = harness([
      { status: 200, body: { items: [{ id: 'a' }, { id: 'b' }], next_cursor: 'c1' } },
      { status: 200, body: { items: [{ id: 'c' }], next_cursor: null } },
    ]);
    const ids: string[] = [];
    for await (const m of client.paginate(client.messages.list, { limit: 2 })) ids.push(m.id);
    expect(ids).toEqual(['a', 'b', 'c']);
    expect(calls).toHaveLength(2);
    const second = new URL(calls[1]!.url);
    expect(second.searchParams.get('cursor')).toBe('c1');
    expect(second.searchParams.get('limit')).toBe('2');
    expect(new URL(calls[0]!.url).searchParams.has('cursor')).toBe(false);
  });
  it('works with id-first lists through a closure and infers item types', async () => {
    const { client, calls } = harness([
      { status: 200, body: { items: [{ id: 'i1', to: '+254700000012' }], next_cursor: 'n1' } },
      { status: 200, body: { items: [{ id: 'i2' }], next_cursor: null } },
    ]);
    const tos: (string | undefined)[] = [];
    for await (const item of client.paginate((p: ListBatchItemsParams) => client.batches.listItems('b1', p), {
      limit: 1,
      status: 'delivered',
    })) {
      tos.push(item.to);
    }
    expect(tos).toEqual(['+254700000012', undefined]);
    expect(calls[1]!.url).toBe('https://api.opensms.io/v1/batches/b1/items?limit=1&status=delivered&cursor=n1');
  });
  it('decodes a page with nextCursor', async () => {
    const { client } = harness([{ status: 200, body: { items: [{ id: 'a', sender_id: 'X' }], next_cursor: 'n' } }]);
    const page = await client.messages.list({ limit: 1 });
    expect(page).toEqual({ items: [{ id: 'a', senderId: 'X' }], nextCursor: 'n' });
  });
});

describe('16. query encoding', () => {
  it('joins list values with commas', async () => {
    const { client, calls } = harness([{ status: 200, body: { quote_id: 'sq_1' } }]);
    const q = await client.senderIds.quote({ countries: ['KE', 'NG'] });
    expect(q.quoteId).toBe('sq_1');
    expect(calls[0]!.url).toBe('https://api.opensms.io/v1/sender-ids/quote?countries=KE,NG');
  });
  it('percent-encodes + and omits unset params', async () => {
    const { client, calls } = harness([{ status: 200, body: { items: [], next_cursor: null } }]);
    await client.messages.list({ status: 'delivered', to: '+2547', cursor: undefined, dateFrom: '2026-01-01' });
    expect(calls[0]!.url).toBe('https://api.opensms.io/v1/messages?status=delivered&to=%2B2547&date_from=2026-01-01');
  });
});

describe('17. path escaping', () => {
  it('escapes path parameters', async () => {
    const { client, calls } = harness([{ status: 200, body: message }]);
    await client.messages.get('a/b');
    expect(calls[0]!.url).toBe('https://api.opensms.io/v1/messages/a%2Fb');
  });
  it('rejects an empty id without a request', async () => {
    const { client, calls } = harness([{ status: 200, body: message }]);
    expect(() => client.messages.get('')).toThrow(TypeError);
    expect(() => client.webhooks.replayDelivery('w', '', { generation: 1, reason: 'xxxxx' })).toThrow(TypeError);
    expect(calls).toHaveLength(0);
  });
});

describe('18. webhook signature vector', () => {
  const secret = 'whsec_c2RrLWNvbmZvcm1hbmNlLXRlc3QtdmVjdG9yLTAwMDE';
  const t = 1790208000;
  const body =
    '{"id":"evt_01","type":"message.delivered","workspace_id":"00000000-0000-0000-0000-000000000001","environment":"sandbox","created_at":"2026-09-24T00:00:00Z","data":{"id":"00000000-0000-0000-0000-000000000002","status":"delivered"}}';
  const digest = 'eeb2ec420dd348b253dae35c1f3bce03d261109eb8788e3ad836072e894fac23';
  const header = `t=${t},v1=${digest}`;

  it('body is the 230-byte vector', () => {
    expect(new TextEncoder().encode(body).length).toBe(230);
  });
  it.each([
    ['header above', body, header, secret, t, true],
    ['now + 300 (inclusive)', body, header, secret, t + 300, true],
    ['now + 301', body, header, secret, t + 301, false],
    ['now - 301', body, header, secret, t - 301, false],
    ['tampered body', body.replace('"status":"delivered"', '"status":"failed"'), header, secret, t, false],
    ['secret without whsec_', body, header, secret.slice('whsec_'.length), t, false],
    ['order swapped', body, `v1=${digest},t=${t}`, secret, t, true],
    ['extra v0', body, `${header},v0=abc`, secret, t, false],
    ['t only', body, `t=${t}`, secret, t, false],
    ['uppercase hex', body, `t=${t},v1=${digest.toUpperCase()}`, secret, t, true],
  ])('%s', (_name, payload, h, s, now, expected) => {
    expect(verifySignature(payload, h, s, { now })).toBe(expected);
    expect(verifySignature(new TextEncoder().encode(payload), h, s, { now })).toBe(expected);
  });
  it('empty secret and missing header are invalid', () => {
    expect(verifySignature(body, header, '', { now: t })).toBe(false);
    expect(verifySignature(body, null, secret, { now: t })).toBe(false);
  });
  it('constructEvent returns the event, or throws coded errors', () => {
    const ev = constructEvent(body, header, secret, { now: t });
    expect(ev.type).toBe('message.delivered');
    expect(ev.workspaceId).toBe('00000000-0000-0000-0000-000000000001');
    expect(ev.data.status).toBe('delivered');

    const tampered = body.replace('"status":"delivered"', '"status":"failed"');
    let e: OpensmsError | undefined;
    try {
      constructEvent(tampered, header, secret, { now: t });
    } catch (err) {
      e = err as OpensmsError;
    }
    expect(e).toBeInstanceOf(OpensmsError);
    expect(e!.status).toBe(0);
    expect(e!.code).toBe('invalid_signature');

    e = undefined;
    try {
      constructEvent(body, header, secret, { now: t + 301 });
    } catch (err) {
      e = err as OpensmsError;
    }
    expect(e!.code).toBe('expired_signature');
  });
  it('is also available on client.webhooks', () => {
    const { client } = harness([]);
    expect(client.webhooks.verifySignature(body, header, secret, { now: t })).toBe(true);
    expect(client.webhooks.constructEvent(body, header, secret, { now: t }).id).toBe('evt_01');
  });
});

describe('19. batch CSV', () => {
  it('posts text/csv with the raw body and an Idempotency-Key', async () => {
    const { client, calls } = harness([{ status: 202, body: { id: 'b1', status: 'ready', total: 1 } }]);
    const csv = 'to,text\n+254700000014,csv run\n';
    const b = await client.batches.createFromCsv(csv);
    expect(b.status).toBe('ready');
    expect(calls[0]!.url).toBe('https://api.opensms.io/v1/messages/batch');
    expect(calls[0]!.headers['content-type']).toBe('text/csv');
    expect(calls[0]!.body).toBe(csv);
    expect(calls[0]!.headers['idempotency-key']).toMatch(UUID_RE);
  });
  it('switches to multipart for dedupe: false', async () => {
    const { client, calls } = harness([{ status: 202, body: { id: 'b1' } }]);
    await client.batches.createFromCsv('to,text\n+254700000014,x\n', { dedupe: false });
    const form = calls[0]!.body as FormData;
    expect(form).toBeInstanceOf(FormData);
    expect(form.get('dedupe')).toBe('false');
    expect(calls[0]!.headers['content-type']).toBeUndefined();
  });
});

describe('20. decimal strings and unknown fields', () => {
  it('keeps price a string and ignores unknown fields', async () => {
    const { client } = harness([
      {
        status: 200,
        body: { ...message, price: '0.000000', country_iso2: 'KE', brand_new_field: { x_y: 1 }, metadata: { run_id: 'r' } },
      },
    ]);
    const m: Message = await client.messages.get(message.id);
    expect(m.price).toBe('0.000000');
    expect(typeof m.price).toBe('string');
    expect(m.countryIso2).toBe('KE');
    expect(m.metadata).toEqual({ run_id: 'r' });
  });
});

describe('resource wiring', () => {
  it('exposes all 18 resources and 83 methods', () => {
    const { client } = harness([]);
    const expected: Record<string, string[]> = {
      messages: ['send', 'list', 'get', 'attempts', 'cancel'],
      batches: ['create', 'get', 'validation', 'start', 'stop', 'listItems'],
      otp: ['send', 'verify'],
      lookups: ['create', 'get'],
      contacts: ['list', 'create', 'get', 'update', 'delete'],
      contactGroups: ['list', 'create', 'get', 'update', 'delete', 'send'],
      templates: ['list', 'create', 'get', 'update', 'delete'],
      webhooks: ['list', 'create', 'get', 'update', 'delete', 'test', 'listDeliveries', 'replayDelivery'],
      inbound: ['list', 'reply'],
      numbers: ['list', 'available', 'assign', 'release', 'listRules', 'createRule', 'updateRule', 'deleteRule'],
      senderIds: [
        'list', 'get', 'create', 'update', 'delete', 'check', 'quote', 'listDocuments',
        'listDrafts', 'createDraft', 'getDraft', 'updateDraft', 'deleteDraft',
      ],
      suppressions: ['list', 'create', 'import', 'delete'],
      compliance: ['listCountries', 'getCountry', 'listContentRules'],
      wallet: ['balances', 'ledger', 'createTopup'],
      pricing: ['get'],
      analytics: ['overview', 'byCountry', 'byCarrier', 'bySenderId', 'timeseries'],
      sandbox: ['listMessages'],
      countries: ['list', 'carriers', 'routes', 'compliance'],
    };
    let count = 0;
    for (const [res, methods] of Object.entries(expected)) {
      for (const m of methods) {
        expect(typeof (client as unknown as Record<string, Record<string, unknown>>)[res]![m]).toBe('function');
        count++;
      }
    }
    expect(Object.keys(expected)).toHaveLength(18);
    expect(count).toBe(83);
  });

  it('routes a representative call per resource to the right method and path', async () => {
    const { client, calls } = harness([{ status: 200, body: {} }]);
    await client.webhooks.update('w1', { url: 'https://x', events: ['a'], enabled: true });
    await client.webhooks.replayDelivery('w1', 42, { generation: 3, reason: 'retry please' });
    await client.numbers.updateRule('n1', 'r1', { match: 'any', action: 'webhook', target: 'https://x' });
    await client.senderIds.updateDraft('d1', { version: 1, sampleMessage: 'hi' });
    await client.wallet.ledger({ limit: 1, before: 99 });
    await client.analytics.bySenderId({ range: '7d' });
    await client.countries.compliance('KE');
    await client.otp.verify({ otpId: 'o1', code: '123456' });
    const seen = calls.map((c) => `${c.method} ${c.url.replace('https://api.opensms.io', '')}`);
    expect(seen).toEqual([
      'PUT /v1/webhooks/w1',
      'POST /v1/webhooks/w1/deliveries/42/replay',
      'PUT /v1/numbers/n1/rules/r1',
      'PATCH /v1/sender-id-drafts/d1',
      'GET /v1/wallet/ledger?limit=1&before=99',
      'GET /v1/analytics/by-sender-id?range=7d',
      'GET /v1/countries/KE/compliance',
      'POST /v1/otp/verify',
    ]);
    expect(JSON.parse(calls[1]!.body as string)).toEqual({ generation: 3, reason: 'retry please' });
    expect(JSON.parse(calls[3]!.body as string)).toEqual({ version: 1, sample_message: 'hi' });
    expect(JSON.parse(calls[7]!.body as string)).toEqual({ otp_id: 'o1', code: '123456' });
    expect(calls[0]!.headers['idempotency-key']).toMatch(UUID_RE); // PUT webhooks is "opt"
  });

  it('decodes envelopes: wallet data, sender documents items, otp camelCase', async () => {
    const { client } = harness([
      { status: 200, body: { data: [{ id: 'w', balance: '10.000000', environment: 'sandbox' }] } },
    ]);
    expect(await client.wallet.balances()).toEqual([{ id: 'w', balance: '10.000000', environment: 'sandbox' }]);
    const h2 = harness([{ status: 200, body: { items: [{ id: 'd', is_current: true }] } }]);
    expect(await h2.client.senderIds.listDocuments()).toEqual([{ id: 'd', isCurrent: true }]);
    const h3 = harness([{ status: 200, body: { valid: false, attempts_left: 4 } }]);
    expect(await h3.client.otp.verify({ otpId: 'o', code: '000000' })).toEqual({ valid: false, attemptsLeft: 4 });
  });
});
