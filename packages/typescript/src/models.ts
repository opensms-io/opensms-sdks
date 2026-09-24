/**
 * Public request and response types for the OpenSMS API, plus the one place
 * where the SDK's camelCase names are mapped to and from the API's snake_case
 * wire names ({@link toWire} and {@link fromWire}).
 *
 * Response types mark every field optional except `id`, because the API omits
 * empty fields. Money, prices and balances are always decimal strings.
 * Enums are open: unknown server values decode as plain strings.
 * @module
 */

/** A free-form JSON object (`metadata`, `attributes`, webhook `payload`). */
export type JsonObject = Record<string, unknown>;

/** An open enum: the listed values plus any string the server adds later. */
type Open<T extends string> = T | (string & {});

/** A timestamp input: a `Date` (sent as RFC 3339 UTC) or an RFC 3339 / `YYYY-MM-DD` string. */
export type DateInput = Date | string;

/** Options for constructing an {@link Opensms} client. */
export interface OpensmsOptions {
  /** Secret API key: `sk_test_...` (sandbox) or `sk_live_...` (live). */
  apiKey: string;
  /** API base URL. Defaults to `https://opensms.io`. Trailing slashes are stripped. */
  baseUrl?: string;
  /** Per-attempt timeout in milliseconds, covering connect and read. Defaults to `30000`. */
  timeoutMs?: number;
  /** Retries after the first attempt (so `2` means up to 3 attempts). `0` disables retries. Defaults to `2`. */
  maxRetries?: number;
  /** Custom `fetch` implementation (a mock in tests, or a polyfill). Defaults to the global `fetch`. */
  fetch?: typeof fetch;
  /** Sleep used between retries, in milliseconds. Tests inject a zero-delay recorder. */
  sleep?: (ms: number) => Promise<void>;
}

/** Per-call options accepted by every method. */
export interface RequestOptions {
  /**
   * Idempotency-Key for methods that support one. When omitted the SDK
   * generates a UUIDv4 once per call and reuses it on every retry.
   */
  idempotencyKey?: string;
  /** Abort the call (all attempts). */
  signal?: AbortSignal;
}

/** One page of a cursor-paginated list. */
export interface Page<T> {
  items: T[];
  /** Pass back as `cursor` to fetch the next page. `null` on the last page. */
  nextCursor: string | null;
}

/** Common cursor paging parameters. */
export interface ListParams {
  /** Page size. Messages allow 1..100 (default 20), other lists 1..200 (default 50). */
  limit?: number;
  /** `nextCursor` from the previous page. */
  cursor?: string;
}

// ---------------------------------------------------------------- messages

export type MessageStatus = Open<
  'queued' | 'scheduled' | 'held' | 'sending' | 'sent' | 'delivered' | 'failed' | 'cancelled' | 'expired'
>;
export type TrafficType = Open<'otp' | 'transactional' | 'marketing'>;

export interface Message {
  id: string;
  createdAt?: string;
  to?: string;
  senderId?: string;
  text?: string;
  parts?: number;
  status?: MessageStatus;
  statusReason?: string;
  sentAt?: string;
  deliveredAt?: string;
  failedAt?: string;
  cancelledAt?: string | null;
  scheduledAt?: string;
  /** Decimal string, for example `"0.000000"`. */
  price?: string;
  currency?: string;
  trafficType?: TrafficType;
  metadata?: JsonObject | null;
  encoding?: Open<'gsm7' | 'ucs2'>;
  countryId?: string | null;
  countryIso2?: string | null;
  countryName?: string | null;
  carrierId?: string | null;
  carrierName?: string | null;
  destinationSource?: Open<'prefix' | 'hlr' | 'unknown'>;
  /** Present on get and list, absent on send. */
  billing?: JsonObject[];
}

export interface SendMessageParams {
  /** E.164 destination, for example `+254700000012`. */
  to: string;
  /** 1..1600 characters. */
  text: string;
  senderId?: string;
  trafficType?: TrafficType;
  scheduledAt?: DateInput;
  callbackUrl?: string;
  metadata?: JsonObject;
}

export interface ListMessagesParams extends ListParams {
  status?: MessageStatus;
  /** Digits or `+digits` fragment. */
  to?: string;
  /** Uppercase ISO2. */
  country?: string;
  dateFrom?: DateInput;
  /** A date-only value is inclusive. */
  dateTo?: DateInput;
}

export interface Attempt {
  id: number;
  sequence?: number;
  routeId?: string;
  routeName?: string;
  price?: string | null;
  currency?: string | null;
  provider?: string;
  providerMessageId?: string;
  status?: Open<'submitting' | 'submission_unknown' | 'submitted' | 'not_accepted' | 'delivered' | 'failed' | 'expired'>;
  errorCode?: string;
  submittedAt?: string;
  dlrAt?: string;
  submitLatencyMs?: number;
  dlrLatencyMs?: number;
}

// ---------------------------------------------------------------- batches

export interface Batch {
  id: string;
  status?: Open<'ready' | 'running' | 'stopped' | 'completed' | 'failed'>;
  total?: number;
  sent?: number;
  delivered?: number;
  failed?: number;
  invalid?: number;
  duplicates?: number;
  suppressed?: number;
  estimatedCost?: number | null;
  createdAt?: string;
  completedAt?: string;
}

export interface BatchItemInput {
  to: string;
  text: string;
  senderId?: string;
  trafficType?: TrafficType;
  callbackUrl?: string;
  metadata?: JsonObject;
}

export interface CreateBatchParams {
  /** Invalid rows do not fail the request; they are counted in `invalid`. */
  items: BatchItemInput[];
  /** Drop duplicate destinations. Defaults to `true` server side. */
  dedupe?: boolean;
}

export interface CreateBatchFromCsvParams {
  /**
   * Drop duplicate destinations (default `true`). The API only reads this
   * flag on multipart uploads, so `dedupe: false` switches the upload to
   * `multipart/form-data`.
   */
  dedupe?: boolean;
}

export interface BatchValidationRow {
  row?: number;
  item?: Partial<BatchItemInput>;
  valid?: boolean;
  duplicate?: boolean;
  suppressed?: boolean;
  error?: string;
}

export interface BatchValidationReport {
  rows?: BatchValidationRow[];
  total?: number;
  valid?: number;
  invalid?: number;
  duplicates?: number;
  suppressed?: number;
}

export interface BatchStopResult {
  id: string;
  status?: string;
  cancelled?: number;
}

/** A batch item. The API returns a slimmer shape than {@link Message}. */
export type BatchItem = Partial<Message> & { id: string };

export interface ListBatchItemsParams extends ListParams {
  status?: MessageStatus;
}

// ---------------------------------------------------------------- otp

export interface SendOtpParams {
  to: string;
  senderId?: string;
  /** Must contain `{{code}}`. */
  template?: string;
  /** 4..10 digits, default 6. */
  length?: number;
  /** 30..86400, default 600. */
  ttlSeconds?: number;
}

export interface SendOtpResult {
  otpId: string;
}

export interface VerifyOtpParams {
  otpId: string;
  code: string;
}

export interface VerifyOtpResult {
  valid: boolean;
  attemptsLeft?: number;
}

// ---------------------------------------------------------------- lookups

export interface Lookup {
  id: string;
  state?: Open<'queued' | 'submitting' | 'unknown' | 'completed' | 'failed'>;
  country?: string;
  carrier?: string | null;
  ported?: boolean | null;
  valid?: boolean | null;
  source?: string | null;
  price?: string;
  currency?: string;
  checkedAt?: string | null;
}

export interface CreateLookupParams {
  to: string;
}

// ---------------------------------------------------------------- contacts

export interface Contact {
  id: string;
  workspaceId?: string;
  e164?: string;
  name?: string | null;
  attributes?: JsonObject;
  createdAt?: string;
}

export interface CreateContactParams {
  e164: string;
  name?: string;
  attributes?: JsonObject;
}

export interface UpdateContactParams {
  e164?: string;
  name?: string;
  attributes?: JsonObject;
}

export interface ContactGroup {
  id: string;
  workspaceId?: string;
  name?: string;
  contactIds?: string[];
  createdAt?: string;
}

export interface CreateContactGroupParams {
  name: string;
  contactIds?: string[];
}

export interface UpdateContactGroupParams {
  name?: string;
  contactIds?: string[];
}

export interface ContactGroupSendParams {
  /** Provide `text` or `templateId`. */
  text?: string;
  templateId?: string;
  /** Template variables, sent verbatim. */
  variables?: Record<string, string>;
  senderId?: string;
  trafficType?: TrafficType;
  callbackUrl?: string;
}

// ---------------------------------------------------------------- templates

export interface Template {
  id: string;
  workspaceId?: string;
  name?: string;
  body?: string;
  trafficType?: TrafficType;
  createdAt?: string;
  updatedAt?: string;
  /** Parsed `{{name}}` placeholders. */
  variables?: string[];
}

export interface CreateTemplateParams {
  name: string;
  body: string;
  trafficType?: TrafficType;
}

export interface UpdateTemplateParams {
  name?: string;
  body?: string;
  trafficType?: TrafficType;
}

// ---------------------------------------------------------------- webhooks

export interface WebhookEndpoint {
  id: string;
  url?: string;
  events?: string[];
  enabled?: boolean;
  consecutiveFailures?: number;
  disabledAt?: string;
  createdAt?: string;
  /** `whsec_...`, only present in the `create` response. Store it. */
  secret?: string;
}

export interface CreateWebhookParams {
  /** Must be `https://`, without credentials or fragment. */
  url: string;
  events: string[];
  enabled?: boolean;
}

/** Full replacement: every field is required. */
export interface UpdateWebhookParams {
  url: string;
  events: string[];
  enabled: boolean;
}

export interface WebhookDelivery {
  id: number;
  generation?: number;
  event?: string;
  payload?: unknown;
  attempts?: number;
  nextRetryAt?: string;
  status?: Open<'pending' | 'delivered' | 'failed'>;
  lastResponseCode?: number;
  lastError?: string;
  createdAt?: string;
  deliveredAt?: string;
}

export interface ReplayDeliveryParams {
  generation: number;
  /** 5..1000 characters. */
  reason: string;
}

export interface StatusResult {
  status: string;
}

/** A verified webhook delivery envelope. `data` is kept exactly as sent (snake_case). */
export interface WebhookEvent {
  id: string;
  type: string;
  workspaceId?: string;
  environment?: string;
  createdAt?: string;
  data: JsonObject;
}

// ---------------------------------------------------------------- inbound

export interface InboundMessage {
  id: string;
  from?: string;
  to?: string;
  text?: string;
  receivedAt?: string;
  virtualNumberId?: string;
}

export interface InboundReplyParams {
  text: string;
}

// ---------------------------------------------------------------- numbers

export type NumberKind = Open<'long_code' | 'short_code' | 'toll_free'>;

export interface PhoneNumber {
  id: string;
  country?: string;
  number?: string;
  kind?: NumberKind;
  monthlyFee?: string;
  feeCurrency?: string;
  status?: Open<'available' | 'assigned' | 'releasing'>;
  inbound?: boolean;
  outbound?: boolean;
  assignedAt?: string;
  renewsAt?: string;
}

export interface NumberSearchParams {
  country: string;
  kind: NumberKind;
}

export interface NumberRule {
  id: string;
  match?: Open<'keyword' | 'prefix' | 'regex' | 'any'>;
  pattern?: string;
  action?: Open<'webhook' | 'auto_reply' | 'forward_email'>;
  target?: string;
  position?: number;
}

export interface NumberRuleParams {
  match: Open<'keyword' | 'prefix' | 'regex' | 'any'>;
  /** Required unless `match` is `any`. */
  pattern?: string;
  action: Open<'webhook' | 'auto_reply' | 'forward_email'>;
  /** 1..2048 characters. */
  target: string;
  /** 0..10000. */
  position?: number;
}

// ---------------------------------------------------------------- sender IDs

export interface SenderId {
  id: string;
  value?: string;
  kind?: Open<'alphanumeric' | 'numeric'>;
  countries?: string[];
  useCase?: string;
  sampleMessage?: string;
  status?: Open<'pending' | 'approved' | 'rejected'>;
  rejectionReason?: string;
  restricted?: boolean;
  restrictionReason?: string;
  createdAt?: string;
  registrations?: JsonObject[];
}

export interface CreateSenderIdParams {
  value: string;
  kind: Open<'alphanumeric' | 'numeric'>;
  countries: string[];
  useCase?: string;
  sampleMessage?: string;
  /** Uploaded document ids (certificate, signatory-id, authorization). */
  documents: string[];
  draftId?: string;
  draftVersion?: number;
  quoteId?: string;
}

export interface UpdateSenderIdParams {
  useCase: string;
  countries: string[];
  documents: string[];
  sampleMessage?: string;
}

export interface SenderIdCheckParams {
  value: string;
  country?: string;
}

export interface SenderIdCheckResult {
  valid?: boolean;
  available?: boolean;
  reserved?: boolean;
  reason?: string;
}

export interface SenderIdQuoteParams {
  /** ISO2 codes, sent comma separated. */
  countries: string[];
}

export interface SenderIdQuote {
  quoteId?: string;
  entries?: { country?: string; provider?: string; feeAmount?: string; feeCurrency?: string }[];
  totals?: { currency?: string; amount?: string }[];
}

export interface SenderDocument {
  id: string;
  kind?: Open<'certificate' | 'signatory-id' | 'authorization'>;
  filename?: string;
  contentType?: string;
  size?: number;
  scanStatus?: string;
  reviewStatus?: string;
  reviewReason?: string;
  reviewedAt?: string;
  version?: number;
  supersedesId?: string;
  isCurrent?: boolean;
  createdAt?: string;
}

export interface SenderIdDraft {
  id: string;
  source?: Open<'onboarding' | 'application'>;
  value?: string;
  kind?: string;
  countries?: string[];
  useCase?: string;
  sampleMessage?: string;
  documents?: string[];
  version?: number;
  status?: Open<'active' | 'submitted'>;
  submittedSenderId?: string | null;
  createdAt?: string;
  updatedAt?: string;
}

export interface CreateSenderIdDraftParams {
  source?: Open<'onboarding' | 'application'>;
  value?: string;
  kind?: Open<'alphanumeric' | 'numeric'>;
  countries?: string[];
  useCase?: string;
  sampleMessage?: string;
  documents?: string[];
}

export interface UpdateSenderIdDraftParams extends CreateSenderIdDraftParams {
  /** Current version (optimistic lock, `409` on mismatch). */
  version: number;
}

// ---------------------------------------------------------------- suppressions

export type SuppressionReason = Open<'stop_keyword' | 'manual' | 'complaint' | 'invalid_number'>;

export interface Suppression {
  id: number;
  e164?: string;
  reason?: SuppressionReason;
  createdAt?: string;
}

export interface CreateSuppressionParams {
  e164: string;
  reason: SuppressionReason;
}

export interface SuppressionImportResult {
  created?: number;
  received?: number;
}

// ---------------------------------------------------------------- compliance

export interface CountryRules {
  iso2?: string;
  name?: string;
  status?: string;
  dialCode?: string;
  stopKeywords?: string[];
  quietHours?: { trafficType?: string; startLocal?: string; endLocal?: string; enforce?: boolean }[];
  contentRules?: { kind?: string; pattern?: string; action?: string; trafficTypes?: string[]; enabled?: boolean }[];
}

export interface ContentRule {
  id: number;
  countryIso2?: string | null;
  kind?: Open<'blocked_keyword' | 'regex'>;
  pattern?: string;
  action?: Open<'reject' | 'hold_for_review'>;
  trafficTypes?: string[];
  enabled?: boolean;
}

// ---------------------------------------------------------------- wallet

export interface WalletBalance {
  id: string;
  currency?: string;
  balance?: string;
  reserved?: string;
  environment?: Open<'sandbox' | 'live'>;
}

export interface LedgerEntry {
  id: number;
  walletId?: string;
  type?: string;
  amount?: string;
  balanceAfter?: string;
  reservedDelta?: string;
  reservedAfter?: string;
  reference?: string;
  paymentId?: string;
  messageId?: string;
  createdAt?: string;
}

export interface LedgerParams {
  /** 1..200. */
  limit?: number;
  /** Smallest entry `id` already seen. Stop when fewer than `limit` rows come back. */
  before?: number;
}

export interface CreateTopupParams {
  /** Decimal string. */
  amount: string;
  currency: string;
  channel: Open<'card' | 'mobile_money' | 'bank_transfer'>;
  email: string;
}

export interface Topup {
  id: string;
  reference?: string;
  authorizationUrl?: string;
  accessCode?: string;
  amount?: string;
  currency?: string;
  status?: string;
}

// ---------------------------------------------------------------- pricing

export interface PricingParams {
  product?: Open<'sms' | 'lookup' | 'number_monthly'>;
  country?: string;
}

export interface PriceEntry {
  countryIso2?: string;
  countryName?: string;
  carrierId?: string | null;
  carrierName?: string | null;
  product?: string;
  minMonthlyVolume?: number;
  markupType?: string;
  markupValue?: string;
  sellCurrency?: string;
  sellAmount?: string | null;
  convertedAmount?: string | null;
  convertedCurrency?: string;
  workspaceOverride?: boolean;
  effectiveFrom?: string;
  fxRate?: string;
}

export interface PriceList {
  workspaceId?: string;
  currency?: string;
  product?: string;
  entries?: PriceEntry[];
}

// ---------------------------------------------------------------- analytics

export interface AnalyticsQuery {
  /** Three-letter currency, defaults to the workspace currency. */
  currency?: string;
  /** `Nd` with N in 1..366 (default `30d`). Do not combine with `from`/`to`. */
  range?: string;
  from?: DateInput;
  to?: DateInput;
  bucket?: Open<'day' | 'hour'>;
}

export interface AnalyticsMetrics {
  sent?: number;
  delivered?: number;
  failed?: number;
  parts?: number;
  deliveryRate?: number;
  /** Decimal string. */
  spend?: string;
  p50Ms?: number;
  p95Ms?: number;
}

export interface AnalyticsOverview extends AnalyticsMetrics {
  from?: string;
  to?: string;
  currency?: string;
  environment?: string;
}

export interface AnalyticsBreakdownRow extends AnalyticsMetrics {
  key?: string;
  name?: string;
}

export interface AnalyticsTimeseriesRow extends AnalyticsMetrics {
  bucket?: string;
}

// ---------------------------------------------------------------- sandbox

export interface SandboxMessage {
  id: string;
  to?: string;
  senderId?: string;
  text?: string;
  parts?: number;
  status?: string;
  trafficType?: TrafficType;
  createdAt?: string;
  sentAt?: string;
}

// ---------------------------------------------------------------- countries

export interface Country {
  iso2?: string;
  name?: string;
  dialCode?: string;
  currency?: string;
  status?: string;
  pricePerMessage?: { amount?: string; currency?: string } | null;
  senderKinds?: string[];
  providersAvailable?: number;
}

export interface Carrier {
  id: string;
  name?: string;
  mccMnc?: string[];
  prefixes?: string[];
}

/** A route serving a country. Fields beyond these are kept as returned. */
export interface Route {
  id?: string;
  name?: string;
  [key: string]: unknown;
}

// ---------------------------------------------------------------- wire mapping

/**
 * Keys whose values are caller-defined JSON and must pass through untouched in
 * both directions (their inner keys are the caller's, not the API's).
 */
const FREE_FORM_KEYS = new Set(['metadata', 'attributes', 'payload', 'variables', 'errors']);

const toSnake = (k: string): string => k.replace(/[A-Z]/g, (c) => `_${c.toLowerCase()}`);
const toCamel = (k: string): string => k.replace(/_([a-z0-9])/g, (_, c: string) => c.toUpperCase());

function isPlainObject(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v) && !(v instanceof Date);
}

/**
 * Convert SDK params (camelCase) into an API body or query (snake_case).
 * Drops `undefined` so unset optionals are omitted rather than sent as `null`,
 * and turns `Date` into an RFC 3339 UTC string.
 */
export function toWire(value: unknown): unknown {
  if (value instanceof Date) return value.toISOString();
  if (Array.isArray(value)) return value.map(toWire);
  if (!isPlainObject(value)) return value;
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(value)) {
    if (v === undefined) continue;
    const key = toSnake(k);
    out[key] = FREE_FORM_KEYS.has(key) ? v : toWire(v);
  }
  return out;
}

/** Convert an API response (snake_case) into SDK models (camelCase). */
export function fromWire<T>(value: unknown): T {
  return convertIn(value) as T;
}

function convertIn(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(convertIn);
  if (!isPlainObject(value)) return value;
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(value)) {
    out[toCamel(k)] = FREE_FORM_KEYS.has(k) ? v : convertIn(v);
  }
  return out;
}

/** Decode a `{ items, next_cursor }` envelope into a {@link Page}. */
export function pageFromWire<T>(value: unknown): Page<T> {
  const raw = (isPlainObject(value) ? value : {}) as { items?: unknown; next_cursor?: unknown };
  const items = Array.isArray(raw.items) ? (raw.items.map(convertIn) as T[]) : [];
  const next = typeof raw.next_cursor === 'string' && raw.next_cursor !== '' ? raw.next_cursor : null;
  return { items, nextCursor: next };
}
