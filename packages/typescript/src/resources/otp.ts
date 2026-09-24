/**
 * The `otp` resource: send and verify one-time passcodes.
 * @module
 */
import { toWire } from '../models.js';
import type { RequestOptions, SendOtpParams, SendOtpResult, VerifyOtpParams, VerifyOtpResult } from '../models.js';
import { Resource } from './base.js';

/** Accessed as `client.otp`. */
export class Otp extends Resource {
  /** Generate a code and send it by SMS. */
  send(params: SendOtpParams, options?: RequestOptions): Promise<SendOtpResult> {
    return this.one({ method: 'POST', path: '/v1/otp/send', json: toWire(params), idempotent: true }, options);
  }

  /**
   * Check a code. A wrong code returns `{ valid: false }` and uses up an
   * attempt, so this call is never retried.
   */
  verify(params: VerifyOtpParams, options?: RequestOptions): Promise<VerifyOtpResult> {
    return this.one({ method: 'POST', path: '/v1/otp/verify', json: toWire(params) }, options);
  }
}
