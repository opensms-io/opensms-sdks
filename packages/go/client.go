package opensms

import (
	"fmt"
	"net/http"
	"strings"
	"time"
)

// Client is the OpenSMS API client. Construct it with NewClient and reach the
// API through its resource fields. Client is safe for concurrent use.
type Client struct {
	// Messages sends, lists, inspects and cancels SMS messages.
	Messages *Messages
	// Batches creates and runs bulk sends.
	Batches *Batches
	// OTP sends and verifies one-time passcodes.
	OTP *OTP
	// Lookups runs number lookups.
	Lookups *Lookups
	// Contacts manages the contact book.
	Contacts *Contacts
	// ContactGroups manages contact groups and sends to them.
	ContactGroups *ContactGroups
	// Templates manages reusable message templates.
	Templates *Templates
	// Webhooks manages webhook endpoints and deliveries, and verifies
	// signatures.
	Webhooks *Webhooks
	// Inbound lists and replies to inbound messages.
	Inbound *Inbound
	// Numbers manages virtual numbers and their inbound rules.
	Numbers *Numbers
	// SenderIDs manages sender IDs, drafts and documents.
	SenderIDs *SenderIDs
	// Suppressions manages the do-not-send list.
	Suppressions *Suppressions
	// Compliance reads country rules and content rules.
	Compliance *Compliance
	// Wallet reads balances and the ledger and creates top-ups.
	Wallet *Wallet
	// Pricing reads the workspace price list.
	Pricing *Pricing
	// Analytics reads delivery and spend metrics.
	Analytics *Analytics
	// Sandbox lists rendered sandbox messages.
	Sandbox *Sandbox
	// Countries reads the public country catalog.
	Countries *Countries

	environment string
	transport   *transport
}

// Option configures a Client. Pass options to NewClient.
type Option func(*transport)

// WithBaseURL overrides the API base URL (default https://api.opensms.io).
// Trailing slashes are stripped.
func WithBaseURL(baseURL string) Option {
	return func(t *transport) {
		t.baseURL = strings.TrimRight(baseURL, "/")
	}
}

// WithMaxRetries sets the number of retries after the first attempt
// (default 2, so 3 attempts in total). 0 disables retries.
func WithMaxRetries(maxRetries int) Option {
	return func(t *transport) {
		if maxRetries >= 0 {
			t.maxRetries = maxRetries
		}
	}
}

// WithTimeout sets the per-attempt timeout covering connect and read
// (default 30s). 0 disables the SDK timeout.
func WithTimeout(timeout time.Duration) Option {
	return func(t *transport) {
		if timeout >= 0 {
			t.timeout = timeout
		}
	}
}

// WithHTTPClient injects a custom *http.Client (for proxies or tests).
func WithHTTPClient(hc *http.Client) Option {
	return func(t *transport) {
		if hc != nil {
			t.httpClient = hc
		}
	}
}

// NewClient constructs a Client. apiKey must start with sk_test_ (sandbox) or
// sk_live_ (live) and have more than 12 characters after the prefix; anything
// else returns an error wrapping ErrInvalidArgument without any network call.
func NewClient(apiKey string, opts ...Option) (*Client, error) {
	env, err := environmentFor(apiKey)
	if err != nil {
		return nil, err
	}
	t := &transport{
		apiKey:     apiKey,
		baseURL:    DefaultBaseURL,
		maxRetries: defaultMaxRetries,
		timeout:    defaultTimeout,
		httpClient: &http.Client{},
		sleep:      sleepContext,
		jitter:     fullJitter,
	}
	for _, opt := range opts {
		if opt != nil {
			opt(t)
		}
	}

	c := &Client{transport: t, environment: env}
	c.Messages = &Messages{http: t}
	c.Batches = &Batches{http: t}
	c.OTP = &OTP{http: t}
	c.Lookups = &Lookups{http: t}
	c.Contacts = &Contacts{http: t}
	c.ContactGroups = &ContactGroups{http: t}
	c.Templates = &Templates{http: t}
	c.Webhooks = &Webhooks{http: t}
	c.Inbound = &Inbound{http: t}
	c.Numbers = &Numbers{http: t}
	c.SenderIDs = &SenderIDs{http: t}
	c.Suppressions = &Suppressions{http: t}
	c.Compliance = &Compliance{http: t}
	c.Wallet = &Wallet{http: t}
	c.Pricing = &Pricing{http: t}
	c.Analytics = &Analytics{http: t}
	c.Sandbox = &Sandbox{http: t}
	c.Countries = &Countries{http: t}
	return c, nil
}

// Environment returns "sandbox" for an sk_test_ key and "live" for sk_live_.
func (c *Client) Environment() string { return c.environment }

// environmentFor mirrors the server's auth.ValidSecret check.
func environmentFor(apiKey string) (string, error) {
	for prefix, env := range map[string]string{"sk_test_": "sandbox", "sk_live_": "live"} {
		if strings.HasPrefix(apiKey, prefix) {
			if len(apiKey)-len(prefix) <= 12 {
				return "", fmt.Errorf("%w: API key is too short", ErrInvalidArgument)
			}
			return env, nil
		}
	}
	if apiKey == "" {
		return "", fmt.Errorf("%w: API key is required", ErrInvalidArgument)
	}
	return "", fmt.Errorf("%w: API key must start with sk_test_ or sk_live_", ErrInvalidArgument)
}
