package opensms

import (
	"encoding/json"
	"time"
)

// This file is the single place where Go names map to the API's snake_case
// wire names. Money, prices, balances and FX rates stay decimal strings.
// Enum-like fields are plain strings so a new server value never breaks
// decoding. Unknown response fields are ignored.

// Bool returns a pointer to v, for optional boolean parameters.
func Bool(v bool) *bool { return &v }

// Int returns a pointer to v, for optional integer parameters.
func Int(v int) *int { return &v }

// rfc3339UTC formats t as RFC 3339 in UTC, the form every time input is sent.
func rfc3339UTC(t time.Time) string { return t.UTC().Format(time.RFC3339Nano) }

// ListParams are the cursor parameters shared by most list methods.
type ListParams struct {
	// Limit is the page size (1..200, server default 50). 0 omits it.
	Limit int
	// Cursor is a NextCursor from a previous page.
	Cursor string
}

// WithCursor implements Cursorable.
func (p ListParams) WithCursor(cursor string) ListParams { p.Cursor = cursor; return p }

// ---------------------------------------------------------------- messages

// SendMessageParams is the body for Messages.Send.
type SendMessageParams struct {
	// To is the destination in E.164 (required).
	To string
	// Text is the message body, 1..1600 characters (required).
	Text string
	// SenderID is the sender (<=11 characters, or <=15 digits).
	SenderID string
	// TrafficType is otp, transactional (default) or marketing.
	TrafficType string
	// ScheduledAt schedules the send; zero sends now.
	ScheduledAt time.Time
	// CallbackURL receives delivery callbacks for this message.
	CallbackURL string
	// Metadata is a free-form JSON object stored with the message.
	Metadata map[string]any
}

// MarshalJSON emits only the fields that are set.
func (p SendMessageParams) MarshalJSON() ([]byte, error) {
	w := struct {
		To          string         `json:"to"`
		Text        string         `json:"text"`
		SenderID    string         `json:"sender_id,omitempty"`
		TrafficType string         `json:"traffic_type,omitempty"`
		ScheduledAt string         `json:"scheduled_at,omitempty"`
		CallbackURL string         `json:"callback_url,omitempty"`
		Metadata    map[string]any `json:"metadata,omitempty"`
	}{p.To, p.Text, p.SenderID, p.TrafficType, "", p.CallbackURL, p.Metadata}
	if !p.ScheduledAt.IsZero() {
		w.ScheduledAt = rfc3339UTC(p.ScheduledAt)
	}
	return json.Marshal(w)
}

// ListMessagesParams filters Messages.List.
type ListMessagesParams struct {
	// Limit is the page size (1..100, server default 20).
	Limit  int
	Cursor string
	// Status filters by message status.
	Status string
	// To filters by a digits or +digits fragment of the destination.
	To string
	// Country filters by uppercase ISO2.
	Country string
	// DateFrom and DateTo bound the creation time; zero omits them.
	DateFrom time.Time
	DateTo   time.Time
}

// WithCursor implements Cursorable.
func (p ListMessagesParams) WithCursor(cursor string) ListMessagesParams {
	p.Cursor = cursor
	return p
}

// Message is an outbound SMS.
type Message struct {
	ID                string           `json:"id"`
	CreatedAt         time.Time        `json:"created_at"`
	To                string           `json:"to"`
	SenderID          string           `json:"sender_id"`
	Text              string           `json:"text"`
	Parts             int              `json:"parts"`
	Status            string           `json:"status"`
	StatusReason      string           `json:"status_reason"`
	SentAt            *time.Time       `json:"sent_at"`
	DeliveredAt       *time.Time       `json:"delivered_at"`
	FailedAt          *time.Time       `json:"failed_at"`
	CancelledAt       *time.Time       `json:"cancelled_at"`
	ScheduledAt       *time.Time       `json:"scheduled_at"`
	Price             string           `json:"price"`
	Currency          string           `json:"currency"`
	TrafficType       string           `json:"traffic_type"`
	Metadata          map[string]any   `json:"metadata"`
	Encoding          string           `json:"encoding"`
	CountryID         string           `json:"country_id"`
	CountryISO2       string           `json:"country_iso2"`
	CountryName       string           `json:"country_name"`
	CarrierID         string           `json:"carrier_id"`
	CarrierName       string           `json:"carrier_name"`
	DestinationSource string           `json:"destination_source"`
	Billing           []map[string]any `json:"billing"`
}

// Attempt is one provider submission of a message.
type Attempt struct {
	ID                int64      `json:"id"`
	Sequence          int        `json:"sequence"`
	RouteID           string     `json:"route_id"`
	RouteName         string     `json:"route_name"`
	Price             string     `json:"price"`
	Currency          string     `json:"currency"`
	Provider          string     `json:"provider"`
	ProviderMessageID string     `json:"provider_message_id"`
	Status            string     `json:"status"`
	ErrorCode         string     `json:"error_code"`
	SubmittedAt       *time.Time `json:"submitted_at"`
	DLRAt             *time.Time `json:"dlr_at"`
	SubmitLatencyMs   *int64     `json:"submit_latency_ms"`
	DLRLatencyMs      *int64     `json:"dlr_latency_ms"`
}

// ------------------------------------------------------------------ batches

// BatchItemInput is one message in a batch.
type BatchItemInput struct {
	To          string         `json:"to"`
	Text        string         `json:"text"`
	SenderID    string         `json:"sender_id,omitempty"`
	TrafficType string         `json:"traffic_type,omitempty"`
	CallbackURL string         `json:"callback_url,omitempty"`
	Metadata    map[string]any `json:"metadata,omitempty"`
}

// CreateBatchParams is the body for Batches.Create.
type CreateBatchParams struct {
	Items []BatchItemInput `json:"items"`
	// Dedupe drops duplicate destinations (server default true).
	Dedupe *bool `json:"dedupe,omitempty"`
}

// CreateBatchFromCSVParams configures Batches.CreateFromCSV.
type CreateBatchFromCSVParams struct {
	// Dedupe drops duplicate destinations (server default true). When set,
	// the CSV is sent as a multipart upload so the flag can travel with it.
	Dedupe *bool
}

// Batch is a bulk send.
type Batch struct {
	ID         string `json:"id"`
	Status     string `json:"status"`
	Total      int    `json:"total"`
	Sent       int    `json:"sent"`
	Delivered  int    `json:"delivered"`
	Failed     int    `json:"failed"`
	Invalid    int    `json:"invalid"`
	Duplicates int    `json:"duplicates"`
	Suppressed int    `json:"suppressed"`
	// EstimatedCost is the decimal estimate, empty when null.
	EstimatedCost json.Number `json:"estimated_cost"`
	CreatedAt     time.Time   `json:"created_at"`
	CompletedAt   *time.Time  `json:"completed_at"`
}

// BatchStopResult is returned by Batches.Stop.
type BatchStopResult struct {
	ID        string `json:"id"`
	Status    string `json:"status"`
	Cancelled int    `json:"cancelled"`
}

// ValidationRow is one row of a batch validation report.
type ValidationRow struct {
	Row        int            `json:"row"`
	Item       BatchItemInput `json:"item"`
	Valid      bool           `json:"valid"`
	Duplicate  bool           `json:"duplicate"`
	Suppressed bool           `json:"suppressed"`
	Error      string         `json:"error"`
}

// ValidationReport is returned by Batches.Validation.
type ValidationReport struct {
	Rows       []ValidationRow `json:"rows"`
	Total      int             `json:"total"`
	Valid      int             `json:"valid"`
	Invalid    int             `json:"invalid"`
	Duplicates int             `json:"duplicates"`
	Suppressed int             `json:"suppressed"`
}

// BatchItem is a message created by a batch. The API returns only id,
// created_at, to, text, sender_id, parts, status, traffic_type and metadata.
type BatchItem = Message

// ListBatchItemsParams filters Batches.ListItems.
type ListBatchItemsParams struct {
	Status string
	Limit  int
	Cursor string
}

// WithCursor implements Cursorable.
func (p ListBatchItemsParams) WithCursor(cursor string) ListBatchItemsParams {
	p.Cursor = cursor
	return p
}

// ---------------------------------------------------------------------- otp

// SendOTPParams is the body for OTP.Send.
type SendOTPParams struct {
	To       string `json:"to"`
	SenderID string `json:"sender_id,omitempty"`
	// Template must contain {{code}}.
	Template string `json:"template,omitempty"`
	// Length is the code length, 4..10 (default 6).
	Length int `json:"length,omitempty"`
	// TTLSeconds is 30..86400 (default 600).
	TTLSeconds int `json:"ttl_seconds,omitempty"`
}

// OTPSendResult is returned by OTP.Send.
type OTPSendResult struct {
	OTPID string `json:"otp_id"`
}

// VerifyOTPParams is the body for OTP.Verify.
type VerifyOTPParams struct {
	OTPID string `json:"otp_id"`
	Code  string `json:"code"`
}

// OTPVerifyResult is returned by OTP.Verify.
type OTPVerifyResult struct {
	Valid        bool `json:"valid"`
	AttemptsLeft int  `json:"attempts_left"`
}

// ------------------------------------------------------------------ lookups

// CreateLookupParams is the body for Lookups.Create.
type CreateLookupParams struct {
	To string `json:"to"`
}

// Lookup is a number lookup.
type Lookup struct {
	ID        string     `json:"id"`
	State     string     `json:"state"`
	Country   string     `json:"country"`
	Carrier   *string    `json:"carrier"`
	Ported    *bool      `json:"ported"`
	Valid     *bool      `json:"valid"`
	Source    string     `json:"source"`
	Price     string     `json:"price"`
	Currency  string     `json:"currency"`
	CheckedAt *time.Time `json:"checked_at"`
}

// ----------------------------------------------------------------- contacts

// Contact is an address-book entry.
type Contact struct {
	ID          string         `json:"id"`
	WorkspaceID string         `json:"workspace_id"`
	E164        string         `json:"e164"`
	Name        string         `json:"name"`
	Attributes  map[string]any `json:"attributes"`
	CreatedAt   time.Time      `json:"created_at"`
}

// CreateContactParams is the body for Contacts.Create.
type CreateContactParams struct {
	E164       string         `json:"e164"`
	Name       string         `json:"name,omitempty"`
	Attributes map[string]any `json:"attributes,omitempty"`
}

// UpdateContactParams is the body for Contacts.Update. Unset fields are kept.
type UpdateContactParams struct {
	E164       string         `json:"e164,omitempty"`
	Name       string         `json:"name,omitempty"`
	Attributes map[string]any `json:"attributes,omitempty"`
}

// ContactGroup is a named set of contacts.
type ContactGroup struct {
	ID          string    `json:"id"`
	WorkspaceID string    `json:"workspace_id"`
	Name        string    `json:"name"`
	ContactIDs  []string  `json:"contact_ids"`
	CreatedAt   time.Time `json:"created_at"`
}

// CreateContactGroupParams is the body for ContactGroups.Create.
type CreateContactGroupParams struct {
	Name       string   `json:"name"`
	ContactIDs []string `json:"contact_ids,omitempty"`
}

// UpdateContactGroupParams is the body for ContactGroups.Update. A nil
// ContactIDs keeps the members; a non-nil empty slice clears them.
type UpdateContactGroupParams struct {
	Name       string
	ContactIDs []string
}

// MarshalJSON sends contact_ids whenever ContactIDs is non-nil.
func (p UpdateContactGroupParams) MarshalJSON() ([]byte, error) {
	m := map[string]any{}
	if p.Name != "" {
		m["name"] = p.Name
	}
	if p.ContactIDs != nil {
		m["contact_ids"] = p.ContactIDs
	}
	return json.Marshal(m)
}

// GroupSendParams is the body for ContactGroups.Send. Set Text or TemplateID.
type GroupSendParams struct {
	Text        string            `json:"text,omitempty"`
	TemplateID  string            `json:"template_id,omitempty"`
	Variables   map[string]string `json:"variables,omitempty"`
	SenderID    string            `json:"sender_id,omitempty"`
	TrafficType string            `json:"traffic_type,omitempty"`
	CallbackURL string            `json:"callback_url,omitempty"`
}

// ---------------------------------------------------------------- templates

// Template is a reusable message body with {{name}} placeholders.
type Template struct {
	ID          string    `json:"id"`
	WorkspaceID string    `json:"workspace_id"`
	Name        string    `json:"name"`
	Body        string    `json:"body"`
	TrafficType string    `json:"traffic_type"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
	Variables   []string  `json:"variables"`
}

// CreateTemplateParams is the body for Templates.Create.
type CreateTemplateParams struct {
	Name        string `json:"name"`
	Body        string `json:"body"`
	TrafficType string `json:"traffic_type,omitempty"`
}

// UpdateTemplateParams is the body for Templates.Update. Unset fields are kept.
type UpdateTemplateParams struct {
	Name        string `json:"name,omitempty"`
	Body        string `json:"body,omitempty"`
	TrafficType string `json:"traffic_type,omitempty"`
}

// ----------------------------------------------------------------- webhooks

// WebhookEndpoint is a webhook subscription.
type WebhookEndpoint struct {
	ID                  string     `json:"id"`
	URL                 string     `json:"url"`
	Events              []string   `json:"events"`
	Enabled             bool       `json:"enabled"`
	ConsecutiveFailures int        `json:"consecutive_failures"`
	DisabledAt          *time.Time `json:"disabled_at"`
	CreatedAt           time.Time  `json:"created_at"`
	// Secret (whsec_...) is returned only by Webhooks.Create. Store it.
	Secret string `json:"secret"`
}

// CreateWebhookParams is the body for Webhooks.Create.
type CreateWebhookParams struct {
	// URL must be https without credentials or fragment.
	URL    string   `json:"url"`
	Events []string `json:"events"`
	// Enabled defaults to true.
	Enabled *bool `json:"enabled,omitempty"`
}

// UpdateWebhookParams is the body for Webhooks.Update, a full replacement:
// every field is sent.
type UpdateWebhookParams struct {
	URL     string   `json:"url"`
	Events  []string `json:"events"`
	Enabled bool     `json:"enabled"`
}

// WebhookDelivery is one delivery of an event to an endpoint.
type WebhookDelivery struct {
	ID               int64      `json:"id"`
	Generation       int        `json:"generation"`
	Event            string     `json:"event"`
	Payload          any        `json:"payload"`
	Attempts         int        `json:"attempts"`
	NextRetryAt      *time.Time `json:"next_retry_at"`
	Status           string     `json:"status"`
	LastResponseCode *int       `json:"last_response_code"`
	LastError        string     `json:"last_error"`
	CreatedAt        time.Time  `json:"created_at"`
	DeliveredAt      *time.Time `json:"delivered_at"`
}

// ReplayDeliveryParams is the body for Webhooks.ReplayDelivery.
type ReplayDeliveryParams struct {
	// Generation comes from the delivery.
	Generation int `json:"generation"`
	// Reason is 5..1000 characters.
	Reason string `json:"reason"`
}

// StatusResult is a {status} acknowledgement (webhook test and replay).
type StatusResult struct {
	Status string `json:"status"`
}

// WebhookEvent is the envelope of a signed webhook delivery.
type WebhookEvent struct {
	ID          string         `json:"id"`
	Type        string         `json:"type"`
	WorkspaceID string         `json:"workspace_id"`
	Environment string         `json:"environment"`
	CreatedAt   time.Time      `json:"created_at"`
	Data        map[string]any `json:"data"`
}

// ------------------------------------------------------------------ inbound

// InboundMessage is an SMS received on a virtual number.
type InboundMessage struct {
	ID              string    `json:"id"`
	From            string    `json:"from"`
	To              string    `json:"to"`
	Text            string    `json:"text"`
	ReceivedAt      time.Time `json:"received_at"`
	VirtualNumberID string    `json:"virtual_number_id"`
}

// InboundReplyParams is the body for Inbound.Reply.
type InboundReplyParams struct {
	Text string `json:"text"`
}

// ------------------------------------------------------------------ numbers

// Number is a virtual number.
type Number struct {
	ID          string     `json:"id"`
	Country     string     `json:"country"`
	Number      string     `json:"number"`
	Kind        string     `json:"kind"`
	MonthlyFee  string     `json:"monthly_fee"`
	FeeCurrency string     `json:"fee_currency"`
	Status      string     `json:"status"`
	Inbound     bool       `json:"inbound"`
	Outbound    bool       `json:"outbound"`
	AssignedAt  *time.Time `json:"assigned_at"`
	RenewsAt    *time.Time `json:"renews_at"`
}

// AvailableNumbersParams filters Numbers.Available.
type AvailableNumbersParams struct {
	Country string
	// Kind is long_code, short_code or toll_free.
	Kind string
}

// AssignNumberParams is the body for Numbers.Assign.
type AssignNumberParams struct {
	Country string `json:"country"`
	Kind    string `json:"kind"`
}

// NumberRule routes inbound messages on a number.
type NumberRule struct {
	ID       string `json:"id"`
	Match    string `json:"match"`
	Pattern  string `json:"pattern"`
	Action   string `json:"action"`
	Target   string `json:"target"`
	Position int    `json:"position"`
}

// NumberRuleParams is the body for Numbers.CreateRule and Numbers.UpdateRule.
type NumberRuleParams struct {
	// Match is keyword, prefix, regex or any.
	Match string `json:"match"`
	// Pattern is required unless Match is any.
	Pattern string `json:"pattern,omitempty"`
	// Action is webhook, auto_reply or forward_email.
	Action   string `json:"action"`
	Target   string `json:"target"`
	Position int    `json:"position"`
}

// ---------------------------------------------------------------- senderIDs

// SenderID is a registered sender.
type SenderID struct {
	ID                string           `json:"id"`
	Value             string           `json:"value"`
	Kind              string           `json:"kind"`
	Countries         []string         `json:"countries"`
	UseCase           string           `json:"use_case"`
	SampleMessage     string           `json:"sample_message"`
	Status            string           `json:"status"`
	RejectionReason   string           `json:"rejection_reason"`
	Restricted        bool             `json:"restricted"`
	RestrictionReason string           `json:"restriction_reason"`
	CreatedAt         time.Time        `json:"created_at"`
	Registrations     []map[string]any `json:"registrations"`
}

// CreateSenderIDParams is the body for SenderIDs.Create.
type CreateSenderIDParams struct {
	Value     string   `json:"value"`
	Kind      string   `json:"kind"`
	Countries []string `json:"countries"`
	UseCase   string   `json:"use_case,omitempty"`
	// SampleMessage is an example of what will be sent.
	SampleMessage string `json:"sample_message,omitempty"`
	// Documents are sender document ids (always sent, may be empty).
	Documents    []string `json:"documents"`
	DraftID      string   `json:"draft_id,omitempty"`
	DraftVersion *int     `json:"draft_version,omitempty"`
	QuoteID      string   `json:"quote_id,omitempty"`
}

// UpdateSenderIDParams is the body for SenderIDs.Update.
type UpdateSenderIDParams struct {
	UseCase       string   `json:"use_case"`
	Countries     []string `json:"countries"`
	Documents     []string `json:"documents"`
	SampleMessage string   `json:"sample_message,omitempty"`
}

// CheckSenderIDParams is the query for SenderIDs.Check.
type CheckSenderIDParams struct {
	Value   string
	Country string
}

// SenderIDCheck is returned by SenderIDs.Check.
type SenderIDCheck struct {
	Valid     bool   `json:"valid"`
	Available bool   `json:"available"`
	Reserved  bool   `json:"reserved"`
	Reason    string `json:"reason"`
}

// QuoteSenderIDParams is the query for SenderIDs.Quote.
type QuoteSenderIDParams struct {
	Countries []string
}

// SenderIDQuoteEntry is one country fee in a quote.
type SenderIDQuoteEntry struct {
	Country     string `json:"country"`
	Provider    string `json:"provider"`
	FeeAmount   string `json:"fee_amount"`
	FeeCurrency string `json:"fee_currency"`
}

// Money is an amount with its currency.
type Money struct {
	Amount   string `json:"amount"`
	Currency string `json:"currency"`
}

// SenderIDQuote is returned by SenderIDs.Quote.
type SenderIDQuote struct {
	QuoteID string               `json:"quote_id"`
	Entries []SenderIDQuoteEntry `json:"entries"`
	Totals  []Money              `json:"totals"`
}

// SenderDocument is an uploaded sender registration document.
type SenderDocument struct {
	ID           string     `json:"id"`
	Kind         string     `json:"kind"`
	Filename     string     `json:"filename"`
	ContentType  string     `json:"content_type"`
	Size         int64      `json:"size"`
	ScanStatus   string     `json:"scan_status"`
	ReviewStatus string     `json:"review_status"`
	ReviewReason string     `json:"review_reason"`
	ReviewedAt   *time.Time `json:"reviewed_at"`
	Version      int        `json:"version"`
	SupersedesID string     `json:"supersedes_id"`
	IsCurrent    bool       `json:"is_current"`
	CreatedAt    time.Time  `json:"created_at"`
}

// SenderIDDraft is a saved, unsubmitted sender ID application.
type SenderIDDraft struct {
	ID                string    `json:"id"`
	Source            string    `json:"source"`
	Value             string    `json:"value"`
	Kind              string    `json:"kind"`
	Countries         []string  `json:"countries"`
	UseCase           string    `json:"use_case"`
	SampleMessage     string    `json:"sample_message"`
	Documents         []string  `json:"documents"`
	Version           int       `json:"version"`
	Status            string    `json:"status"`
	SubmittedSenderID *string   `json:"submitted_sender_id"`
	CreatedAt         time.Time `json:"created_at"`
	UpdatedAt         time.Time `json:"updated_at"`
}

// SenderIDDraftParams is the body for SenderIDs.CreateDraft.
type SenderIDDraftParams struct {
	// Source is onboarding or application.
	Source        string   `json:"source,omitempty"`
	Value         string   `json:"value,omitempty"`
	Kind          string   `json:"kind,omitempty"`
	Countries     []string `json:"countries,omitempty"`
	UseCase       string   `json:"use_case,omitempty"`
	SampleMessage string   `json:"sample_message,omitempty"`
	Documents     []string `json:"documents,omitempty"`
}

// UpdateSenderIDDraftParams is the body for SenderIDs.UpdateDraft. Version is
// the draft's current version (optimistic lock, 409 on mismatch).
type UpdateSenderIDDraftParams struct {
	Version       int      `json:"version"`
	Value         string   `json:"value,omitempty"`
	Kind          string   `json:"kind,omitempty"`
	Countries     []string `json:"countries,omitempty"`
	UseCase       string   `json:"use_case,omitempty"`
	SampleMessage string   `json:"sample_message,omitempty"`
	Documents     []string `json:"documents,omitempty"`
}

// ------------------------------------------------------------- suppressions

// Suppression is a do-not-send entry.
type Suppression struct {
	ID        int64     `json:"id"`
	E164      string    `json:"e164"`
	Reason    string    `json:"reason"`
	CreatedAt time.Time `json:"created_at"`
}

// SuppressionInput is the body for Suppressions.Create and one import item.
type SuppressionInput struct {
	E164 string `json:"e164"`
	// Reason is stop_keyword, manual, complaint or invalid_number.
	Reason string `json:"reason"`
}

// CreateSuppressionParams is the body for Suppressions.Create.
type CreateSuppressionParams = SuppressionInput

// SuppressionImportResult is returned by Suppressions.Import.
type SuppressionImportResult struct {
	Created  int `json:"created"`
	Received int `json:"received"`
}

// --------------------------------------------------------------- compliance

// QuietHours is a country quiet-hours window.
type QuietHours struct {
	TrafficType string `json:"traffic_type"`
	StartLocal  string `json:"start_local"`
	EndLocal    string `json:"end_local"`
	Enforce     string `json:"enforce"`
}

// CountryContentRule is a content rule embedded in CountryRules.
type CountryContentRule struct {
	Kind         string   `json:"kind"`
	Pattern      string   `json:"pattern"`
	Action       string   `json:"action"`
	TrafficTypes []string `json:"traffic_types"`
	Enabled      bool     `json:"enabled"`
}

// CountryRules are the compliance rules for one country.
type CountryRules struct {
	ISO2         string               `json:"iso2"`
	Name         string               `json:"name"`
	Status       string               `json:"status"`
	DialCode     string               `json:"dial_code"`
	StopKeywords []string             `json:"stop_keywords"`
	QuietHours   []QuietHours         `json:"quiet_hours"`
	ContentRules []CountryContentRule `json:"content_rules"`
}

// ContentRule is a platform content rule.
type ContentRule struct {
	ID           int64    `json:"id"`
	CountryISO2  string   `json:"country_iso2"`
	Kind         string   `json:"kind"`
	Pattern      string   `json:"pattern"`
	Action       string   `json:"action"`
	TrafficTypes []string `json:"traffic_types"`
	Enabled      bool     `json:"enabled"`
}

// ------------------------------------------------------------------- wallet

// WalletBalance is one currency wallet.
type WalletBalance struct {
	ID          string `json:"id"`
	Currency    string `json:"currency"`
	Balance     string `json:"balance"`
	Reserved    string `json:"reserved"`
	Environment string `json:"environment"`
}

// LedgerEntry is one wallet ledger movement.
type LedgerEntry struct {
	ID            int64     `json:"id"`
	WalletID      string    `json:"wallet_id"`
	Type          string    `json:"type"`
	Amount        string    `json:"amount"`
	BalanceAfter  string    `json:"balance_after"`
	ReservedDelta string    `json:"reserved_delta"`
	ReservedAfter string    `json:"reserved_after"`
	Reference     string    `json:"reference"`
	PaymentID     string    `json:"payment_id"`
	MessageID     string    `json:"message_id"`
	CreatedAt     time.Time `json:"created_at"`
}

// LedgerParams pages Wallet.Ledger. It does not use cursors: pass the
// smallest ID already seen as Before, and stop when fewer than Limit entries
// come back.
type LedgerParams struct {
	// Limit is 1..200; nil omits it. Use Int(n) to set it.
	Limit *int
	// Before returns entries with an id lower than this. 0 omits it.
	Before int64
}

// CreateTopupParams is the body for Wallet.CreateTopup.
type CreateTopupParams struct {
	// Amount is a decimal string.
	Amount   string `json:"amount"`
	Currency string `json:"currency"`
	// Channel is card, mobile_money or bank_transfer.
	Channel string `json:"channel"`
	Email   string `json:"email"`
}

// Topup is a pending payment-provider top-up.
type Topup struct {
	ID               string `json:"id"`
	Reference        string `json:"reference"`
	AuthorizationURL string `json:"authorization_url"`
	AccessCode       string `json:"access_code"`
	Amount           string `json:"amount"`
	Currency         string `json:"currency"`
	Status           string `json:"status"`
}

// ------------------------------------------------------------------ pricing

// PricingParams filters Pricing.Get.
type PricingParams struct {
	// Product is sms (default), lookup or number_monthly.
	Product string
	// Country is an ISO2 code.
	Country string
}

// PriceEntry is one row of a price list.
type PriceEntry struct {
	CountryISO2       string    `json:"country_iso2"`
	CountryName       string    `json:"country_name"`
	CarrierID         string    `json:"carrier_id"`
	CarrierName       string    `json:"carrier_name"`
	Product           string    `json:"product"`
	MinMonthlyVolume  int64     `json:"min_monthly_volume"`
	MarkupType        string    `json:"markup_type"`
	MarkupValue       string    `json:"markup_value"`
	SellCurrency      string    `json:"sell_currency"`
	SellAmount        *string   `json:"sell_amount"`
	ConvertedAmount   *string   `json:"converted_amount"`
	ConvertedCurrency string    `json:"converted_currency"`
	WorkspaceOverride bool      `json:"workspace_override"`
	EffectiveFrom     time.Time `json:"effective_from"`
	FXRate            string    `json:"fx_rate"`
}

// PriceList is returned by Pricing.Get.
type PriceList struct {
	WorkspaceID string       `json:"workspace_id"`
	Currency    string       `json:"currency"`
	Product     string       `json:"product"`
	Entries     []PriceEntry `json:"entries"`
}

// ---------------------------------------------------------------- analytics

// AnalyticsParams is the common analytics query. Use Range or From/To, not
// both.
type AnalyticsParams struct {
	// Currency is a 3-letter code (default: the workspace currency).
	Currency string
	// Range is Nd with N in 1..366 (default 30d).
	Range string
	From  time.Time
	To    time.Time
	// Bucket is day or hour.
	Bucket string
}

// Metrics are delivery and spend counters.
type Metrics struct {
	Sent         int64   `json:"sent"`
	Delivered    int64   `json:"delivered"`
	Failed       int64   `json:"failed"`
	Parts        int64   `json:"parts"`
	DeliveryRate float64 `json:"delivery_rate"`
	Spend        string  `json:"spend"`
	P50Ms        *int64  `json:"p50_ms"`
	P95Ms        *int64  `json:"p95_ms"`
}

// AnalyticsOverview is returned by Analytics.Overview.
type AnalyticsOverview struct {
	Metrics
	From        time.Time `json:"from"`
	To          time.Time `json:"to"`
	Currency    string    `json:"currency"`
	Environment string    `json:"environment"`
}

// AnalyticsBreakdown is one row of a by-country, by-carrier or by-sender-id
// breakdown.
type AnalyticsBreakdown struct {
	Metrics
	Key  string `json:"key"`
	Name string `json:"name"`
}

// AnalyticsPoint is one timeseries bucket.
type AnalyticsPoint struct {
	Metrics
	Bucket time.Time `json:"bucket"`
}

// ------------------------------------------------------------------ sandbox

// SandboxMessage is a rendered sandbox send (including OTP codes).
type SandboxMessage struct {
	ID          string     `json:"id"`
	To          string     `json:"to"`
	SenderID    string     `json:"sender_id"`
	Text        string     `json:"text"`
	Parts       int        `json:"parts"`
	Status      string     `json:"status"`
	TrafficType string     `json:"traffic_type"`
	CreatedAt   time.Time  `json:"created_at"`
	SentAt      *time.Time `json:"sent_at"`
}

// ---------------------------------------------------------------- countries

// Country is a public catalog country.
type Country struct {
	ISO2               string   `json:"iso2"`
	Name               string   `json:"name"`
	DialCode           string   `json:"dial_code"`
	Currency           string   `json:"currency"`
	Status             string   `json:"status"`
	PricePerMessage    *Money   `json:"price_per_message"`
	SenderKinds        []string `json:"sender_kinds"`
	ProvidersAvailable int      `json:"providers_available"`
}

// Carrier is a mobile network in a country.
type Carrier struct {
	ID       string   `json:"id"`
	Name     string   `json:"name"`
	MCCMNC   []string `json:"mcc_mnc"`
	Prefixes []string `json:"prefixes"`
}

// Route is a routable provider path for a country.
type Route struct {
	Provider  string `json:"provider"`
	Carrier   string `json:"carrier"`
	Health    string `json:"health"`
	Cost      string `json:"cost"`
	Currency  string `json:"currency"`
	Priority  int    `json:"priority"`
	SellPrice *Money `json:"sell_price"`
	P50Ms     *int64 `json:"p50_ms"`
}
