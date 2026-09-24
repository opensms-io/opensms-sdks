/**
 * The OpenSMS client. Composes the transport with the resource groups; this
 * is the entry point most code touches.
 * @module
 */
import type { OpensmsOptions } from './models.js';
import { paginate, type PageFetcher, type PageItem, type PageParams } from './pagination.js';
import { Transport } from './transport.js';
import { Analytics } from './resources/analytics.js';
import { Batches } from './resources/batches.js';
import { Compliance } from './resources/compliance.js';
import { ContactGroups } from './resources/contact-groups.js';
import { Contacts } from './resources/contacts.js';
import { Countries } from './resources/countries.js';
import { Inbound } from './resources/inbound.js';
import { Lookups } from './resources/lookups.js';
import { Messages } from './resources/messages.js';
import { Numbers } from './resources/numbers.js';
import { Otp } from './resources/otp.js';
import { Pricing } from './resources/pricing.js';
import { Sandbox } from './resources/sandbox.js';
import { SenderIds } from './resources/sender-ids.js';
import { Suppressions } from './resources/suppressions.js';
import { Templates } from './resources/templates.js';
import { Wallet } from './resources/wallet.js';
import { Webhooks } from './resources/webhooks.js';

/**
 * OpenSMS API client.
 *
 * @example
 * ```ts
 * import { Opensms } from '@opensms/sdk';
 *
 * const opensms = new Opensms({ apiKey: process.env.OPENSMS_API_KEY! });
 * const msg = await opensms.messages.send({ to: '+254700000012', text: 'Your order shipped' });
 * ```
 */
export class Opensms {
  /** `"sandbox"` for `sk_test_` keys, `"live"` for `sk_live_` keys. */
  readonly environment: 'sandbox' | 'live';
  /** The resolved base URL, without a trailing slash. */
  readonly baseUrl: string;

  readonly messages: Messages;
  readonly batches: Batches;
  readonly otp: Otp;
  readonly lookups: Lookups;
  readonly contacts: Contacts;
  readonly contactGroups: ContactGroups;
  readonly templates: Templates;
  readonly webhooks: Webhooks;
  readonly inbound: Inbound;
  readonly numbers: Numbers;
  readonly senderIds: SenderIds;
  readonly suppressions: Suppressions;
  readonly compliance: Compliance;
  readonly wallet: Wallet;
  readonly pricing: Pricing;
  readonly analytics: Analytics;
  readonly sandbox: Sandbox;
  readonly countries: Countries;

  /** Throws `TypeError` (no network call) when `apiKey` is not a valid secret key. */
  constructor(options: OpensmsOptions) {
    const http = new Transport(options);
    this.environment = http.environment;
    this.baseUrl = http.baseUrl;
    this.messages = new Messages(http);
    this.batches = new Batches(http);
    this.otp = new Otp(http);
    this.lookups = new Lookups(http);
    this.contacts = new Contacts(http);
    this.contactGroups = new ContactGroups(http);
    this.templates = new Templates(http);
    this.webhooks = new Webhooks(http);
    this.inbound = new Inbound(http);
    this.numbers = new Numbers(http);
    this.senderIds = new SenderIds(http);
    this.suppressions = new Suppressions(http);
    this.compliance = new Compliance(http);
    this.wallet = new Wallet(http);
    this.pricing = new Pricing(http);
    this.analytics = new Analytics(http);
    this.sandbox = new Sandbox(http);
    this.countries = new Countries(http);
  }

  /**
   * Iterate every item of a cursor list, fetching pages lazily.
   *
   * @example
   * ```ts
   * for await (const m of opensms.paginate(opensms.messages.list, { limit: 50 })) console.log(m.id);
   * ```
   */
  paginate<F extends PageFetcher>(list: F, params?: PageParams<F>): AsyncGenerator<PageItem<F>, void, undefined> {
    return paginate(list, params);
  }
}
