/**
 * Official Java client for the OpenSMS prepaid SMS API.
 *
 * <p>The entry point is {@link io.opensms.OpensmsClient}. Failures surface as the
 * unchecked {@link io.opensms.OpensmsException}. Webhook signatures are verified
 * with {@link io.opensms.WebhookSignature}. Response models live in
 * {@code io.opensms.models}.
 *
 * <pre>{@code
 * OpensmsClient opensms = new OpensmsClient("sk_test_...");
 * Message m = opensms.messages().send(new SendMessageParams("+254700000012", "Hello"));
 * }</pre>
 */
package io.opensms;
