/**
 * The single error type raised by the SDK.
 * @module
 */

/** Fields of an RFC 9457 problem body plus the response headers worth keeping. */
export interface OpensmsErrorInit {
  status: number;
  message?: string;
  type?: string | null;
  title?: string | null;
  detail?: string | null;
  code?: string | null;
  traceId?: string | null;
  errors?: Record<string, string[]> | null;
  requestId?: string | null;
  retryAfter?: number | null;
  body?: unknown;
  cause?: unknown;
}

/**
 * Thrown for every non-2xx response, for transport failures that survive all
 * retries (`status === 0`), and by webhook verification
 * (`status === 0`, `code` `invalid_signature` or `expired_signature`).
 *
 * Branch on {@link OpensmsError.status}: most API errors carry no `code`.
 * Insufficient scope is `401` on messages and otp but `403` everywhere else.
 */
export class OpensmsError extends Error {
  /** HTTP status. `0` means no response (network failure, timeout, or a local check). */
  readonly status: number;
  /** Problem `type`: usually `about:blank`, else `https://api.opensms.io/problems/<code>`. */
  readonly type: string | null;
  /** Problem `title`, for example `Bad Request`. */
  readonly title: string | null;
  /** Human-readable problem `detail`. */
  readonly detail: string | null;
  /** Machine code, when the API sets one (`invalid_message_id`, `not_found`, ...). */
  readonly code: string | null;
  /** Problem `trace_id`. */
  readonly traceId: string | null;
  /** Field validation errors (`field -> messages`). */
  readonly errors: Record<string, string[]> | null;
  /** `X-Request-ID` response header (message and OTP admission rejections). */
  readonly requestId: string | null;
  /** `Retry-After` in seconds (429 and some 503). */
  readonly retryAfter: number | null;
  /** The decoded body, or the raw text when it was not JSON. */
  readonly body: unknown;

  constructor(init: OpensmsErrorInit) {
    const message =
      init.message ?? init.detail ?? init.title ?? `OpenSMS request failed with status ${init.status}`;
    super(message);
    this.name = 'OpensmsError';
    this.status = init.status;
    this.type = init.type ?? null;
    this.title = init.title ?? null;
    this.detail = init.detail ?? null;
    this.code = init.code ?? null;
    this.traceId = init.traceId ?? null;
    this.errors = init.errors ?? null;
    this.requestId = init.requestId ?? null;
    this.retryAfter = init.retryAfter ?? null;
    this.body = init.body;
    if (init.cause !== undefined) (this as { cause?: unknown }).cause = init.cause;
    Object.setPrototypeOf(this, OpensmsError.prototype);
  }

  /** Build an error from a non-2xx HTTP response body and headers. */
  static fromResponse(status: number, text: string, headers: Headers, retryAfter: number | null): OpensmsError {
    let body: unknown = text === '' ? null : text;
    let problem: Record<string, unknown> = {};
    if (text !== '') {
      try {
        const parsed: unknown = JSON.parse(text);
        body = parsed;
        if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
          problem = parsed as Record<string, unknown>;
        }
      } catch {
        // Not JSON (a proxy HTML page): keep the text in `body`, fields stay null.
      }
    }
    const str = (v: unknown): string | null => (typeof v === 'string' && v !== '' ? v : null);
    const errors =
      problem.errors && typeof problem.errors === 'object' && !Array.isArray(problem.errors)
        ? (problem.errors as Record<string, string[]>)
        : null;
    return new OpensmsError({
      status,
      type: str(problem.type),
      title: str(problem.title),
      detail: str(problem.detail),
      code: str(problem.code),
      traceId: str(problem.trace_id),
      errors,
      requestId: str(headers.get('x-request-id')),
      retryAfter,
      body,
    });
  }
}
