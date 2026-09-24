/**
 * Send one SMS and wait for delivery.
 *
 *   OPENSMS_API_KEY=sk_test_... npx tsx examples/send.ts +254700000012
 */
import { Opensms, OpensmsError } from '@opensms/sdk';

const opensms = new Opensms({ apiKey: process.env.OPENSMS_API_KEY!, baseUrl: process.env.OPENSMS_BASE_URL });
const to = process.argv[2] ?? '+254700000012';

try {
  const sent = await opensms.messages.send({ to, text: 'Hello from the OpenSMS TypeScript SDK' });
  console.log('sent', sent.id, sent.status);
  for (let i = 0; i < 20; i++) {
    const m = await opensms.messages.get(sent.id);
    if (m.status === 'delivered' || m.status === 'failed') {
      console.log('final', m.status, m.price, m.currency);
      break;
    }
    await new Promise((r) => setTimeout(r, 1000));
  }
} catch (e) {
  if (e instanceof OpensmsError) console.error(e.status, e.detail, e.code);
  else throw e;
  process.exitCode = 1;
}
