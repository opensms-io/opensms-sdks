// Package opensms is the official Go client for the OpenSMS prepaid SMS API.
//
// Construct a client with an API key (sk_test_ for the sandbox, sk_live_ for
// live traffic) and reach the API through resource fields:
//
//	client, err := opensms.NewClient("sk_test_...")
//	if err != nil {
//		log.Fatal(err)
//	}
//	msg, err := client.Messages.Send(ctx, opensms.SendMessageParams{
//		To:   "+254700000012",
//		Text: "Your order has shipped",
//	})
//
// One transport (transport.go) owns bearer authentication, JSON encoding,
// Idempotency-Key generation (one UUID per call, reused on every retry),
// retries on 429 and 5xx with backoff that honours Retry-After, and mapping
// of problem+json errors to *Error. Resources are thin wrappers over it.
// Every method takes a context.Context as its first argument.
//
// Cursor lists return a *Page[T]; Paginate walks every page lazily.
// VerifySignature and ConstructEvent check webhook signatures without a
// client or API key.
package opensms
