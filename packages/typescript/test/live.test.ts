/**
 * Live conformance scenario (CONFORMANCE.md "Live scenario", steps 1..29).
 * Runs only when OPENSMS_BASE_URL and OPENSMS_API_KEY are set; skipped otherwise.
 * Steps run in order and share state, so a failed step can cascade.
 *
 *   source ../../spec/fixtures/credentials.sh && npm run test:live
 */
import { describe, expect, it } from 'vitest';
import { Opensms, OpensmsError, type Message } from '../src/index.js';

// The package ships no @types/node; the tests only need process.env.
declare const process: { env: Record<string, string | undefined> };

const BASE = process.env.OPENSMS_BASE_URL;
const KEY = process.env.OPENSMS_API_KEY;
const RO_KEY = process.env.OPENSMS_READONLY_API_KEY;
const LIVE = Boolean(BASE && KEY);

const RUN = Array.from({ length: 8 }, () => Math.floor(Math.random() * 16).toString(16)).join('');
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const ZERO = '00000000-0000-0000-0000-000000000000';
const T = 180_000;

const digits = (n: number) => Array.from({ length: n }, () => Math.floor(Math.random() * 10)).join('');
const randomPhone = () => '+2547' + digits(8);
/**
 * Destination for sends. CONFORMANCE.md uses +254700000012, but the API's
 * admission limiter caps sends per destination per hour for the workspace, and
 * every SDK's live suite shares one workspace. A per-run random number in the
 * same Safaricom range (+25470...) keeps parallel runs from exhausting that
 * quota. Override with OPENSMS_TEST_TO.
 */
const DEST = process.env.OPENSMS_TEST_TO ?? '+25470' + digits(7);
const DEST2 = '+25470' + digits(7);
const randomUpper = (n: number) =>
  Array.from({ length: n }, () => String.fromCharCode(65 + Math.floor(Math.random() * 26))).join('');

function makeClient(apiKey = KEY!): Opensms {
  return new Opensms({ apiKey, baseUrl: BASE, timeoutMs: 60_000 });
}

/** Assert the call rejects with OpensmsError(status, detail). */
async function expectErr(p: Promise<unknown>, status: number, detail: string): Promise<OpensmsError> {
  let caught: unknown;
  try {
    await p;
  } catch (e) {
    caught = e;
  }
  expect(caught, `expected OpensmsError ${status} ${detail}`).toBeInstanceOf(OpensmsError);
  const e = caught as OpensmsError;
  expect({ status: e.status, detail: e.detail }).toEqual({ status, detail });
  return e;
}

/** Poll `fn` until it returns a truthy value or the deadline passes. */
async function poll<T>(fn: () => Promise<T | undefined | null | false>, deadlineMs = 20_000, everyMs = 500): Promise<T> {
  const end = Date.now() + deadlineMs;
  let last: unknown;
  for (;;) {
    try {
      const v = await fn();
      if (v) return v;
    } catch (e) {
      last = e;
    }
    if (Date.now() > end) throw new Error(`poll deadline exceeded${last ? `: ${String(last)}` : ''}`);
    await new Promise((r) => setTimeout(r, everyMs));
  }
}

describe.skipIf(!LIVE)('live conformance (typescript)', () => {
  const client = LIVE ? makeClient() : (undefined as unknown as Opensms);
  const s: Record<string, string | number> = {};

  it('1. constructor rejects bad keys locally', () => {
    expect(() => new Opensms({ apiKey: 'not_a_key', baseUrl: BASE })).toThrow(TypeError);
    expect(() => new Opensms({ apiKey: 'sk_test_short', baseUrl: BASE })).toThrow(TypeError);
  });

  it('2. auth error is a 401 problem and is not retried', async () => {
    let calls = 0;
    const counting = ((url: string, init: RequestInit) => {
      calls++;
      return fetch(url, init);
    }) as typeof fetch;
    const bad = new Opensms({ apiKey: 'sk_test_' + 'A'.repeat(32), baseUrl: BASE, fetch: counting, timeoutMs: 60_000 });
    const e = await expectErr(bad.messages.list({ limit: 1 }), 401, 'missing or invalid API key');
    expect(e.type).toBe('about:blank');
    expect(e.title).toBe('Unauthorized');
    expect(e.code).toBeNull();
    expect(calls).toBe(1);
  }, T);

  it('3. send', async () => {
    const m = await client.messages.send({
      to: DEST,
      text: `conformance typescript ${RUN}`,
      metadata: { sdk: 'typescript', run: RUN },
    });
    expect(m.id).toMatch(UUID_RE);
    expect(m.to).toBe(DEST);
    expect(m.senderId).toBe('OPENSMS');
    expect(m.trafficType).toBe('transactional');
    expect(['queued', 'sending', 'sent', 'delivered']).toContain(m.status);
    expect(m.parts).toBe(1);
    expect(m.encoding).toBe('gsm7');
    expect(m.countryIso2).toBe('KE');
    expect(m.currency).toBe('KES');
    expect(m.price).toBe('0.000000');
    expect(m.metadata?.run).toBe(RUN);
    s.M = m.id;
  }, T);

  it('4. idempotent replay and key reuse conflict', async () => {
    const K = `sdk-ts-${RUN}-${Date.now()}`;
    const P = { to: randomPhone(), text: `idem ${RUN}` };
    const a = await client.messages.send(P, { idempotencyKey: K });
    const b = await client.messages.send(P, { idempotencyKey: K });
    expect(b.id).toBe(a.id);
    await expectErr(
      client.messages.send({ ...P, text: `idem changed ${RUN}` }, { idempotencyKey: K }),
      409,
      'Idempotency-Key was already used with a different request',
    );
  }, T);

  it('5. get and wait for delivery', async () => {
    const m = await poll(async () => {
      const x = await client.messages.get(String(s.M));
      return x.status === 'delivered' ? x : undefined;
    });
    expect(m.deliveredAt).toBeTruthy();
    expect(m.sentAt).toBeTruthy();
    expect(m.text).toBe(`conformance typescript ${RUN}`);
  }, T);

  it('6. list, cursor, errors and the pagination helper', async () => {
    const p1 = await client.messages.list({ limit: 1 });
    expect(p1.items).toHaveLength(1);
    expect(p1.nextCursor).not.toBeNull();
    const p2 = await client.messages.list({ limit: 1, cursor: p1.nextCursor! });
    expect(p2.items).toHaveLength(1);
    expect(p2.items[0]!.id).not.toBe(p1.items[0]!.id);
    await expectErr(client.messages.list({ limit: 1, cursor: 'garbage' }), 400, 'invalid cursor');
    await expectErr(client.messages.list({ status: 'bogus' }), 400, 'invalid status');
    const seen: Message[] = [];
    for await (const m of client.paginate(client.messages.list, { limit: 2 })) {
      seen.push(m);
      if (seen.length >= 3) break;
    }
    expect(seen).toHaveLength(3);
  }, T);

  it('7. attempts', async () => {
    const attempts = await client.messages.attempts(String(s.M));
    expect(attempts.length).toBeGreaterThanOrEqual(1);
    const a = attempts[0]!;
    expect(a.sequence).toBe(1);
    expect(a.routeName?.startsWith('Mock provider (sandbox)')).toBe(true);
    expect(a.status).toBe('delivered');
    expect(a.price).toBe('0.000000');
  }, T);

  it('8. validation error', async () => {
    const e = await expectErr(client.messages.send({ to: '12345', text: 'x' }), 400, 'to must be an E.164 phone number');
    expect(e.title).toBe('Bad Request');
    expect(e.type).toBe('about:blank');
  }, T);

  it('9. coded error', async () => {
    const e = await expectErr(client.messages.get('not-a-uuid'), 400, 'Message ID must be a valid UUID.');
    expect(e.code).toBe('invalid_message_id');
    expect(e.type).toBe('https://api.opensms.io/problems/invalid_message_id');
  }, T);

  it('10. not found', async () => {
    await expectErr(client.messages.get(ZERO), 404, 'message not found');
  }, T);

  it('11. schedule and cancel', async () => {
    const m = await client.messages.send({
      to: randomPhone(),
      text: `scheduled ${RUN}`,
      scheduledAt: new Date(Date.now() + 2 * 3600_000),
    });
    expect(m.status).toBe('scheduled');
    const c = await client.messages.cancel(m.id);
    expect(c.status).toBe('cancelled');
    expect(c.cancelledAt).toBeTruthy();
    const detail = 'message cannot be cancelled in its current state';
    await expectErr(client.messages.cancel(m.id), 409, detail);
    await expectErr(client.messages.cancel(String(s.M)), 409, detail);
  }, T);

  it('12. batch lifecycle', async () => {
    const b = await client.batches.create({
      items: [
        { to: DEST, text: `b1 ${RUN}` },
        { to: DEST2, text: `b2 ${RUN}` },
        { to: 'bad', text: 'x' },
      ],
    });
    expect(b.status).toBe('ready');
    expect(b.total).toBe(3);
    expect(b.invalid).toBe(1);
    expect(b.sent).toBe(0);
    const v = await client.batches.validation(b.id);
    expect(v.rows).toHaveLength(3);
    expect(v.valid).toBe(2);
    expect(v.rows![2]!.valid).toBe(false);
    expect(v.rows![2]!.error).toBe('to must be an E.164 phone number');
    const g = await client.batches.get(b.id);
    expect({ total: g.total, invalid: g.invalid, sent: g.sent }).toEqual({ total: 3, invalid: 1, sent: 0 });
    const started = await client.batches.start(b.id);
    expect(started.status).toBe('running');
    const items = await poll(async () => {
      const p = await client.batches.listItems(b.id);
      return p.items.length === 2 ? p.items : undefined;
    });
    for (const it of items) {
      expect(it.to).toBeTruthy();
      expect(it.status).toBeTruthy();
    }
  }, T);

  it('13. batch stop', async () => {
    const b = await client.batches.create({ items: [{ to: DEST, text: `stop ${RUN}` }] });
    const stopped = await client.batches.stop(b.id);
    expect(stopped).toEqual({ id: b.id, status: 'stopped', cancelled: 0 });
    await expectErr(client.batches.start(b.id), 409, 'batch is not ready to start');
    await expectErr(client.batches.get(ZERO), 404, 'batch not found');
  }, T);

  it('14. CSV batch', async () => {
    const b = await client.batches.createFromCsv(`to,text\n+254700000014,csv ${RUN}\n`);
    expect(b.status).toBe('ready');
    expect(b.total).toBe(1);
    expect(b.invalid).toBe(0);
  }, T);

  it('15. OTP send, read code from sandbox, verify', async () => {
    const before = Date.now() - 5_000;
    const { otpId } = await client.otp.send({ to: DEST, length: 6, ttlSeconds: 300 });
    expect(otpId).toMatch(UUID_RE);
    const code = await poll(async () => {
      const page = await client.sandbox.listMessages({ limit: 50 });
      for (const m of page.items) {
        const match = /Your OpenSMS verification code is (\d{6})/.exec(m.text ?? '');
        if (m.trafficType === 'otp' && m.to === DEST && match && Date.parse(m.createdAt ?? '') >= before) {
          return match[1];
        }
      }
      return undefined;
    });
    const wrong = code === '000000' ? '111111' : '000000';
    expect(await client.otp.verify({ otpId, code: wrong })).toEqual({ valid: false, attemptsLeft: 4 });
    expect(await client.otp.verify({ otpId, code: code! })).toEqual({ valid: true, attemptsLeft: 3 });
    await expectErr(client.otp.send({ to: DEST, template: 'no placeholder' }), 400, 'template must contain {{code}}');
    await expectErr(client.otp.verify({ otpId: ZERO, code: '123456' }), 404, 'OTP not found');
  }, T);

  it('16. lookup', async () => {
    const l = await client.lookups.create({ to: DEST });
    expect(l.state).toBe('completed');
    expect(l.country).toBe('KE');
    expect(l.source).toBe('mock');
    expect(l.price).toBe('0.000000');
    const g = await client.lookups.get(l.id);
    expect({ id: g.id, state: g.state }).toEqual({ id: l.id, state: l.state });
    const e = await expectErr(client.lookups.get(ZERO), 404, 'Lookup not found.');
    expect(e.code).toBe('not_found');
  }, T);

  it('17. contacts', async () => {
    const R1 = randomPhone();
    const c = await client.contacts.create({ e164: R1, name: `Ada ${RUN}`, attributes: { tier: 'gold' } });
    expect(c.e164).toBe(R1);
    const g = await client.contacts.get(c.id);
    expect(g).toEqual(c);
    const u = await client.contacts.update(c.id, { name: `Ada L ${RUN}` });
    expect(u.name).toBe(`Ada L ${RUN}`);
    expect(u.attributes?.tier).toBe('gold');
    let found = false;
    for await (const x of client.paginate(client.contacts.list, { limit: 200 })) {
      if (x.id === c.id) {
        found = true;
        break;
      }
    }
    expect(found).toBe(true);
    await expectErr(client.contacts.create({ e164: R1 }), 409, 'A record with this phone number or name already exists.');
    s.contactId = c.id;
  }, T);

  it('18. contact groups', async () => {
    const contactId = String(s.contactId);
    const grp = await client.contactGroups.create({ name: `grp ${RUN}`, contactIds: [contactId] });
    expect(grp.contactIds).toEqual([contactId]);
    const upd = await client.contactGroups.update(grp.id, { name: `grp2 ${RUN}` });
    expect(upd.name).toBe(`grp2 ${RUN}`);
    const b = await client.contactGroups.send(grp.id, { text: `Hi ${RUN}` });
    expect(b.status).toBe('running');
    expect(b.total).toBe(1);
    const empty = await client.contactGroups.create({ name: `empty ${RUN}` });
    await expectErr(
      client.contactGroups.send(empty.id, { text: 'x' }),
      422,
      'Group must contain between 1 and 1000 contacts.',
    );
    await client.contactGroups.delete(empty.id);
    s.groupId = grp.id;
  }, T);

  it('19. templates, template group send, cleanup', async () => {
    const t = await client.templates.create({ name: `tpl-${RUN}`, body: 'Hi {{name}}', trafficType: 'transactional' });
    expect(t.variables).toEqual(['name']);
    const u = await client.templates.update(t.id, { body: 'Hello {{name}}' });
    expect(u.body).toBe('Hello {{name}}');
    expect(u.variables).toEqual(['name']);
    const b = await client.contactGroups.send(String(s.groupId), { templateId: t.id, variables: { name: 'Ada' } });
    expect(b.status).toBe('running');
    await expect(client.templates.delete(t.id)).resolves.toBeUndefined();
    await expect(client.contactGroups.delete(String(s.groupId))).resolves.toBeUndefined();
    await expect(client.contacts.delete(String(s.contactId))).resolves.toBeUndefined();
    await expectErr(client.contacts.get(String(s.contactId)), 404, 'Record not found.');
  }, T);

  it('20. webhooks', async () => {
    const w = await client.webhooks.create({
      url: `https://example.com/opensms/${RUN}`,
      events: ['message.delivered', 'message.failed'],
    });
    expect(w.secret?.startsWith('whsec_')).toBe(true);
    expect(w.enabled).toBe(true);
    const g = await client.webhooks.get(w.id);
    expect(g.secret).toBeUndefined();
    await expectErr(
      client.webhooks.create({ url: 'http://example.com/x', events: ['message.delivered'] }),
      400,
      'url must be an HTTPS URL without credentials or fragment',
    );
    const u = await client.webhooks.update(w.id, {
      url: `https://example.com/opensms/${RUN}/v2`,
      events: ['message.delivered'],
      enabled: true,
    });
    expect(u.url).toBe(`https://example.com/opensms/${RUN}/v2`);
    expect(u.events).toEqual(['message.delivered']);
    expect(await client.webhooks.test(w.id)).toEqual({ status: 'pending' });
    const deliveries = await poll(async () => {
      const p = await client.webhooks.listDeliveries(w.id);
      return p.items.find((d) => d.event === 'webhook.test');
    });
    expect(Number.isInteger(deliveries.id)).toBe(true);
    expect(Number.isInteger(deliveries.generation)).toBe(true);
    try {
      const r = await client.webhooks.replayDelivery(w.id, deliveries.id, {
        generation: deliveries.generation!,
        reason: 'sdk conformance replay',
      });
      expect(typeof r.status).toBe('string');
    } catch (e) {
      expect(e).toBeInstanceOf(OpensmsError);
      expect({ status: (e as OpensmsError).status, detail: (e as OpensmsError).detail }).toEqual({
        status: 409,
        detail: 'Delivery state, lease or generation does not permit replay.',
      });
    }
    await expect(client.webhooks.delete(w.id)).resolves.toBeUndefined();
    await expectErr(client.webhooks.get(w.id), 404, 'webhook not found');
  }, T);

  it('21. suppressions', async () => {
    const R2 = randomPhone();
    const R3 = randomPhone();
    const sup = await client.suppressions.create({ e164: R2, reason: 'manual' });
    expect(Number.isInteger(sup.id)).toBe(true);
    expect(sup.reason).toBe('manual');
    const e = await expectErr(client.messages.send({ to: R2, text: 'x' }), 422, 'destination is suppressed');
    expect(typeof e.requestId).toBe('string');
    expect(e.requestId!.length).toBeGreaterThan(0);
    let listed = false;
    for await (const x of client.paginate(client.suppressions.list, { limit: 200 })) {
      if (x.e164 === R2) {
        listed = true;
        break;
      }
    }
    expect(listed).toBe(true);
    expect(await client.suppressions.import([{ e164: R3, reason: 'complaint' }])).toEqual({ created: 1, received: 1 });
    await expect(client.suppressions.delete(sup.id)).resolves.toBeUndefined();
    await expectErr(client.suppressions.delete(sup.id), 404, 'suppression not found');
  }, T);

  it('22. compliance', async () => {
    const ke = await client.compliance.getCountry('KE');
    expect(ke.iso2).toBe('KE');
    expect(ke.dialCode).toBe('+254');
    expect(ke.stopKeywords).toContain('STOP');
    await expectErr(client.compliance.getCountry('ZZ'), 404, 'country not found');
    const all = await client.compliance.listCountries();
    expect(all.some((c) => c.iso2 === 'KE')).toBe(true);
    const rules = await client.compliance.listContentRules();
    expect(Array.isArray(rules)).toBe(true);
    for (const r of rules) expect(Number.isInteger(r.id)).toBe(true);
  }, T);

  it('23. wallet', async () => {
    const balances = await client.wallet.balances();
    expect(balances.length).toBeGreaterThan(0);
    expect(balances[0]!.environment).toBe('sandbox');
    expect(balances[0]!.currency).toBe('KES');
    expect(balances[0]!.balance).toMatch(/^-?\d+(\.\d+)?$/);
    const ledger = await client.wallet.ledger({ limit: 1 });
    expect(ledger).toHaveLength(1);
    expect(Number.isInteger(ledger[0]!.id)).toBe(true);
    await expectErr(client.wallet.ledger({ limit: 0 }), 400, 'limit must be between 1 and 200');
    await expectErr(
      client.wallet.createTopup({ amount: '100', currency: 'KES', channel: 'card', email: 'dev@opensms.test' }),
      422,
      'sandbox wallets cannot use payment providers',
    );
  }, T);

  it('24. pricing', async () => {
    const p = await client.pricing.get({ product: 'sms', country: 'KE' });
    expect(p.currency).toBe('KES');
    expect(p.product).toBe('sms');
    for (const e of p.entries ?? []) expect(e.countryIso2).toBe('KE');
    await expectErr(client.pricing.get({ product: 'bogus' }), 400, 'product must be sms, lookup, or number_monthly');
  }, T);

  it('25. analytics', async () => {
    const o = await client.analytics.overview();
    expect(o.environment).toBe('sandbox');
    expect(o.currency).toBe('KES');
    expect(Number.isInteger(o.sent)).toBe(true);
    await client.analytics.overview({ range: '7d' });
    expect(Array.isArray(await client.analytics.byCountry())).toBe(true);
    expect(Array.isArray(await client.analytics.byCarrier())).toBe(true);
    expect(Array.isArray(await client.analytics.bySenderId())).toBe(true);
    expect(Array.isArray(await client.analytics.timeseries())).toBe(true);
  }, T);

  it('26. numbers and inbound', async () => {
    const page = await client.numbers.list();
    expect(Array.isArray(page.items)).toBe(true);
    expect(Array.isArray(await client.numbers.available({ country: 'KE', kind: 'long_code' }))).toBe(true);
    await expectErr(
      client.numbers.assign({ country: 'KE', kind: 'long_code' }),
      422,
      'This operation requires the live environment.',
    );
    const inbound = await client.inbound.list();
    expect(inbound.items).toEqual([]);
  }, T);

  it('27. sender IDs and drafts', async () => {
    let approved = false;
    for await (const x of client.paginate(client.senderIds.list, { limit: 200 })) {
      if (x.value === 'OPENSMS' && x.status === 'approved') {
        approved = true;
        break;
      }
    }
    expect(approved).toBe(true);
    expect((await client.senderIds.check({ value: 'ACME', country: 'KE' })).valid).toBe(true);
    const q = await client.senderIds.quote({ countries: ['KE'] });
    expect(q.quoteId?.startsWith('sq_')).toBe(true);
    expect(Array.isArray(await client.senderIds.listDocuments())).toBe(true);
    const d = await client.senderIds.createDraft({
      source: 'application',
      value: 'SDK' + randomUpper(4),
      kind: 'alphanumeric',
      countries: ['KE'],
      useCase: 'transactional',
      sampleMessage: 'Your order shipped',
    });
    expect(d.version).toBe(1);
    expect(d.status).toBe('active');
    const u = await client.senderIds.updateDraft(d.id, { version: 1, sampleMessage: 'Your order has shipped' });
    expect(u.version).toBe(2);
    const g = await client.senderIds.getDraft(d.id);
    expect(g.id).toBe(d.id);
    await expect(client.senderIds.deleteDraft(d.id)).resolves.toBeUndefined();
    await expectErr(client.senderIds.get(ZERO), 404, 'sender ID not found');
  }, T);

  it('28. countries', async () => {
    const all = await client.countries.list();
    const ke = all.find((c) => c.iso2 === 'KE');
    expect(ke?.dialCode).toBe('+254');
    expect((await client.countries.carriers('KE')).length).toBeGreaterThan(0);
    expect(Array.isArray(await client.countries.routes('KE'))).toBe(true);
    expect((await client.countries.compliance('KE')).iso2).toBe('KE');
  }, T);

  it.skipIf(!RO_KEY)('29. scope errors with a read-only key', async () => {
    const ro = makeClient(RO_KEY!);
    await expectErr(ro.messages.send({ to: DEST, text: `scope ${RUN}` }), 401, 'insufficient scope');
    await expectErr(ro.contacts.list(), 403, 'Insufficient API key scope.');
    const page = await ro.messages.list({ limit: 1 });
    expect(Array.isArray(page.items)).toBe(true);
  }, T);
});
