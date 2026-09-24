package opensms

// Live conformance scenario from spec/CONFORMANCE.md. Runs only when
// OPENSMS_BASE_URL and OPENSMS_API_KEY are set; skipped otherwise.
//
//	source ../../spec/fixtures/credentials.sh && go test -run TestLive -v ./...

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"math/big"
	"net/http"
	"os"
	"regexp"
	"strings"
	"testing"
	"time"
)

const (
	zeroUUID = "00000000-0000-0000-0000-000000000000"
)

var uuidRE = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)

func liveEnv(t *testing.T) (string, string) {
	t.Helper()
	base, key := os.Getenv("OPENSMS_BASE_URL"), os.Getenv("OPENSMS_API_KEY")
	if base == "" || key == "" {
		t.Skip("OPENSMS_BASE_URL and OPENSMS_API_KEY not set; skipping live conformance")
	}
	return base, key
}

func liveClient(t *testing.T, base, key string) *Client {
	t.Helper()
	c, err := NewClient(key, WithBaseURL(base), WithTimeout(90*time.Second))
	if err != nil {
		t.Fatalf("NewClient: %v", err)
	}
	return c
}

func randHex(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func randPhone() string {
	n, _ := rand.Int(rand.Reader, big.NewInt(100000000))
	return fmt.Sprintf("+2547%08d", n.Int64())
}

// randSendPhone returns a random Safaricom-range KE number. The scenario in
// CONFORMANCE.md sends to +254700000012, but the API enforces a
// per-destination admission quota (default 5 per hour, 3 OTPs per 10 minutes)
// that every SDK's run shares, so each run sends to its own numbers.
func randSendPhone() string {
	n, _ := rand.Int(rand.Reader, big.NewInt(10000000))
	return fmt.Sprintf("+25470%07d", n.Int64())
}

func randUpper(n int) string {
	const letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	out := make([]byte, n)
	for i := range out {
		k, _ := rand.Int(rand.Reader, big.NewInt(26))
		out[i] = letters[k.Int64()]
	}
	return string(out)
}

// wantErr asserts err is an *Error with the given status and exact detail.
func wantErr(t *testing.T, err error, status int, detail string) *Error {
	t.Helper()
	var e *Error
	if !errors.As(err, &e) {
		t.Fatalf("want *Error(%d, %q), got %v", status, detail, err)
	}
	if e.Status != status || e.Detail != detail {
		t.Fatalf("want (%d, %q), got (%d, %q) code=%q", status, detail, e.Status, e.Detail, e.Code)
	}
	return e
}

// poll calls fn until it returns true or the deadline passes.
func poll(t *testing.T, deadline time.Duration, fn func() (bool, error)) {
	t.Helper()
	end := time.Now().Add(deadline)
	for {
		done, err := fn()
		if err != nil {
			t.Fatalf("poll: %v", err)
		}
		if done {
			return
		}
		if time.Now().After(end) {
			t.Fatalf("poll: deadline %v exceeded", deadline)
		}
		time.Sleep(500 * time.Millisecond)
	}
}

func transportOrDefault(rt http.RoundTripper) http.RoundTripper {
	if rt == nil {
		return http.DefaultTransport
	}
	return rt
}

func TestLiveConformance(t *testing.T) {
	base, key := liveEnv(t)
	c := liveClient(t, base, key)
	ctx := context.Background()
	run := randHex(4)
	liveTo := randSendPhone()
	var (
		msgID     string
		contactID string
		groupID   string
	)

	t.Run("01 constructor", func(t *testing.T) {
		for _, k := range []string{"not_a_key", "sk_test_short"} {
			if _, err := NewClient(k); !errors.Is(err, ErrInvalidArgument) {
				t.Fatalf("NewClient(%q) = %v", k, err)
			}
		}
	})

	t.Run("02 auth error", func(t *testing.T) {
		bad := liveClient(t, base, "sk_test_"+strings.Repeat("A", 32))
		attempts := 0
		inner := bad.transport.httpClient.Transport
		bad.transport.httpClient.Transport = roundTripFunc(func(r *http.Request) (*http.Response, error) {
			attempts++
			return transportOrDefault(inner).RoundTrip(r)
		})
		_, err := bad.Messages.List(ctx, ListMessagesParams{Limit: 1})
		e := wantErr(t, err, 401, "missing or invalid API key")
		if e.Type != "about:blank" || e.Title != "Unauthorized" || e.Code != "" {
			t.Fatalf("problem = %+v", e)
		}
		if attempts != 1 {
			t.Fatalf("attempts = %d, want 1", attempts)
		}
	})

	t.Run("03 send", func(t *testing.T) {
		m, err := c.Messages.Send(ctx, SendMessageParams{
			To: liveTo, Text: "conformance go " + run,
			Metadata: map[string]any{"sdk": "go", "run": run},
		})
		if err != nil {
			t.Fatal(err)
		}
		if !uuidRE.MatchString(m.ID) || m.To != liveTo || m.SenderID != "OPENSMS" || m.TrafficType != "transactional" ||
			m.Parts != 1 || m.Encoding != "gsm7" || m.CountryISO2 != "KE" || m.Currency != "KES" || m.Price != "0.000000" ||
			m.Metadata["run"] != run {
			t.Fatalf("message = %+v", m)
		}
		switch m.Status {
		case "queued", "sending", "sent", "delivered":
		default:
			t.Fatalf("status = %q", m.Status)
		}
		msgID = m.ID
	})

	t.Run("04 idempotent replay", func(t *testing.T) {
		k := newUUID()
		p := SendMessageParams{To: liveTo, Text: "idem go " + run}
		a, err := c.Messages.Send(ctx, p, WithIdempotencyKey(k))
		if err != nil {
			t.Fatal(err)
		}
		b, err := c.Messages.Send(ctx, p, WithIdempotencyKey(k))
		if err != nil {
			t.Fatal(err)
		}
		if a.ID != b.ID {
			t.Fatalf("replay ids differ: %s vs %s", a.ID, b.ID)
		}
		p.Text += " changed"
		_, err = c.Messages.Send(ctx, p, WithIdempotencyKey(k))
		wantErr(t, err, 409, "Idempotency-Key was already used with a different request")
	})

	t.Run("05 get and wait", func(t *testing.T) {
		var m *Message
		poll(t, 20*time.Second, func() (bool, error) {
			var err error
			m, err = c.Messages.Get(ctx, msgID)
			return err == nil && m.Status == "delivered", err
		})
		if m.DeliveredAt == nil || m.SentAt == nil || m.Text != "conformance go "+run {
			t.Fatalf("delivered message = %+v", m)
		}
	})

	t.Run("06 list and cursor", func(t *testing.T) {
		p1, err := c.Messages.List(ctx, ListMessagesParams{Limit: 1})
		if err != nil {
			t.Fatal(err)
		}
		if len(p1.Items) != 1 || p1.NextCursor == "" {
			t.Fatalf("page1 = %+v", p1)
		}
		p2, err := c.Messages.List(ctx, ListMessagesParams{Limit: 1, Cursor: p1.NextCursor})
		if err != nil {
			t.Fatal(err)
		}
		if len(p2.Items) != 1 || p2.Items[0].ID == p1.Items[0].ID {
			t.Fatalf("page2 = %+v", p2)
		}
		_, err = c.Messages.List(ctx, ListMessagesParams{Limit: 1, Cursor: "garbage"})
		wantErr(t, err, 400, "invalid cursor")
		_, err = c.Messages.List(ctx, ListMessagesParams{Status: "bogus"})
		wantErr(t, err, 400, "invalid status")
		it := Paginate(ctx, c.Messages.List, ListMessagesParams{Limit: 2})
		n := 0
		for n < 3 && it.Next() {
			n++
		}
		if it.Err() != nil || n != 3 {
			t.Fatalf("paginate yielded %d, err %v", n, it.Err())
		}
	})

	t.Run("07 attempts", func(t *testing.T) {
		as, err := c.Messages.Attempts(ctx, msgID)
		if err != nil {
			t.Fatal(err)
		}
		if len(as) == 0 {
			t.Fatal("no attempts")
		}
		a := as[0]
		if a.Sequence != 1 || !strings.HasPrefix(a.RouteName, "Mock provider (sandbox)") || a.Status != "delivered" || a.Price != "0.000000" {
			t.Fatalf("attempt = %+v", a)
		}
	})

	t.Run("08 validation error", func(t *testing.T) {
		_, err := c.Messages.Send(ctx, SendMessageParams{To: "12345", Text: "x"})
		e := wantErr(t, err, 400, "to must be an E.164 phone number")
		if e.Title != "Bad Request" || e.Type != "about:blank" {
			t.Fatalf("problem = %+v", e)
		}
	})

	t.Run("09 coded error", func(t *testing.T) {
		_, err := c.Messages.Get(ctx, "not-a-uuid")
		e := wantErr(t, err, 400, "Message ID must be a valid UUID.")
		if e.Code != "invalid_message_id" || e.Type != "https://api.opensms.io/problems/invalid_message_id" {
			t.Fatalf("problem = %+v", e)
		}
	})

	t.Run("10 not found", func(t *testing.T) {
		_, err := c.Messages.Get(ctx, zeroUUID)
		wantErr(t, err, 404, "message not found")
	})

	t.Run("11 schedule and cancel", func(t *testing.T) {
		m, err := c.Messages.Send(ctx, SendMessageParams{To: randSendPhone(), Text: "scheduled " + run, ScheduledAt: time.Now().Add(2 * time.Hour)})
		if err != nil {
			t.Fatal(err)
		}
		if m.Status != "scheduled" {
			t.Fatalf("status = %q", m.Status)
		}
		cm, err := c.Messages.Cancel(ctx, m.ID)
		if err != nil {
			t.Fatal(err)
		}
		if cm.Status != "cancelled" || cm.CancelledAt == nil {
			t.Fatalf("cancelled = %+v", cm)
		}
		_, err = c.Messages.Cancel(ctx, m.ID)
		wantErr(t, err, 409, "message cannot be cancelled in its current state")
		_, err = c.Messages.Cancel(ctx, msgID)
		wantErr(t, err, 409, "message cannot be cancelled in its current state")
	})

	t.Run("12 batch", func(t *testing.T) {
		b, err := c.Batches.Create(ctx, CreateBatchParams{Items: []BatchItemInput{
			{To: randSendPhone(), Text: "b1 " + run},
			{To: randSendPhone(), Text: "b2 " + run},
			{To: "bad", Text: "x"},
		}})
		if err != nil {
			t.Fatal(err)
		}
		if b.Status != "ready" || b.Total != 3 || b.Invalid != 1 || b.Sent != 0 {
			t.Fatalf("batch = %+v", b)
		}
		rep, err := c.Batches.Validation(ctx, b.ID)
		if err != nil {
			t.Fatal(err)
		}
		if len(rep.Rows) != 3 || rep.Valid != 2 || rep.Rows[2].Valid || rep.Rows[2].Error != "to must be an E.164 phone number" {
			t.Fatalf("report = %+v", rep)
		}
		g, err := c.Batches.Get(ctx, b.ID)
		if err != nil {
			t.Fatal(err)
		}
		if g.Total != 3 || g.Invalid != 1 || g.Sent != 0 {
			t.Fatalf("get = %+v", g)
		}
		s, err := c.Batches.Start(ctx, b.ID)
		if err != nil {
			t.Fatal(err)
		}
		if s.Status != "running" {
			t.Fatalf("start status = %q", s.Status)
		}
		poll(t, 20*time.Second, func() (bool, error) {
			p, err := c.Batches.ListItems(ctx, b.ID, ListBatchItemsParams{})
			if err != nil {
				return false, err
			}
			if len(p.Items) != 2 {
				return false, nil
			}
			for _, it := range p.Items {
				if it.To == "" || it.Status == "" {
					return false, fmt.Errorf("item missing to/status: %+v", it)
				}
			}
			return true, nil
		})
	})

	t.Run("13 batch stop", func(t *testing.T) {
		b, err := c.Batches.Create(ctx, CreateBatchParams{Items: []BatchItemInput{{To: randSendPhone(), Text: "stop " + run}}})
		if err != nil {
			t.Fatal(err)
		}
		st, err := c.Batches.Stop(ctx, b.ID)
		if err != nil {
			t.Fatal(err)
		}
		if st.ID != b.ID || st.Status != "stopped" || st.Cancelled != 0 {
			t.Fatalf("stop = %+v", st)
		}
		_, err = c.Batches.Start(ctx, b.ID)
		wantErr(t, err, 409, "batch is not ready to start")
		_, err = c.Batches.Get(ctx, zeroUUID)
		wantErr(t, err, 404, "batch not found")
	})

	t.Run("14 csv batch", func(t *testing.T) {
		b, err := c.Batches.CreateFromCSV(ctx, []byte("to,text\n+254700000014,csv "+run+"\n"), CreateBatchFromCSVParams{})
		if err != nil {
			t.Fatal(err)
		}
		if b.Status != "ready" || b.Total != 1 || b.Invalid != 0 {
			t.Fatalf("csv batch = %+v", b)
		}
	})

	t.Run("15 otp", func(t *testing.T) {
		sentAt := time.Now().Add(-5 * time.Second)
		res, err := c.OTP.Send(ctx, SendOTPParams{To: liveTo, Length: 6, TTLSeconds: 300})
		if err != nil {
			t.Fatal(err)
		}
		if !uuidRE.MatchString(res.OTPID) {
			t.Fatalf("otp_id = %q", res.OTPID)
		}
		codeRE := regexp.MustCompile(`Your OpenSMS verification code is (\d{6})`)
		var code string
		poll(t, 20*time.Second, func() (bool, error) {
			p, err := c.Sandbox.ListMessages(ctx, ListParams{Limit: 10})
			if err != nil {
				return false, err
			}
			for _, m := range p.Items {
				if m.TrafficType != "otp" || m.CreatedAt.Before(sentAt) {
					continue
				}
				if mm := codeRE.FindStringSubmatch(m.Text); mm != nil {
					code = mm[1]
					return true, nil
				}
			}
			return false, nil
		})
		wrong := "000000"
		if wrong == code {
			wrong = "111111"
		}
		v, err := c.OTP.Verify(ctx, VerifyOTPParams{OTPID: res.OTPID, Code: wrong})
		if err != nil {
			t.Fatal(err)
		}
		if v.Valid || v.AttemptsLeft != 4 {
			t.Fatalf("wrong verify = %+v", v)
		}
		v, err = c.OTP.Verify(ctx, VerifyOTPParams{OTPID: res.OTPID, Code: code})
		if err != nil {
			t.Fatal(err)
		}
		if !v.Valid || v.AttemptsLeft != 3 {
			t.Fatalf("right verify = %+v", v)
		}
		_, err = c.OTP.Send(ctx, SendOTPParams{To: randSendPhone(), Template: "no placeholder"})
		wantErr(t, err, 400, "template must contain {{code}}")
		_, err = c.OTP.Verify(ctx, VerifyOTPParams{OTPID: zeroUUID, Code: "123456"})
		wantErr(t, err, 404, "OTP not found")
	})

	t.Run("16 lookup", func(t *testing.T) {
		l, err := c.Lookups.Create(ctx, CreateLookupParams{To: liveTo})
		if err != nil {
			t.Fatal(err)
		}
		if l.State != "completed" || l.Country != "KE" || l.Source != "mock" || l.Price != "0.000000" {
			t.Fatalf("lookup = %+v", l)
		}
		g, err := c.Lookups.Get(ctx, l.ID)
		if err != nil {
			t.Fatal(err)
		}
		if g.ID != l.ID || g.State != l.State {
			t.Fatalf("get = %+v", g)
		}
		_, err = c.Lookups.Get(ctx, zeroUUID)
		if e := wantErr(t, err, 404, "Lookup not found."); e.Code != "not_found" {
			t.Fatalf("code = %q", e.Code)
		}
	})

	t.Run("17 contacts", func(t *testing.T) {
		r1 := randPhone()
		ct, err := c.Contacts.Create(ctx, CreateContactParams{E164: r1, Name: "Ada " + run, Attributes: map[string]any{"tier": "gold"}})
		if err != nil {
			t.Fatal(err)
		}
		if ct.E164 != r1 {
			t.Fatalf("contact = %+v", ct)
		}
		contactID = ct.ID
		g, err := c.Contacts.Get(ctx, ct.ID)
		if err != nil {
			t.Fatal(err)
		}
		if g.ID != ct.ID || g.E164 != r1 || g.Name != ct.Name {
			t.Fatalf("get = %+v", g)
		}
		u, err := c.Contacts.Update(ctx, ct.ID, UpdateContactParams{Name: "Ada L " + run})
		if err != nil {
			t.Fatal(err)
		}
		if u.Name != "Ada L "+run || u.Attributes["tier"] != "gold" {
			t.Fatalf("update = %+v", u)
		}
		it := Paginate(ctx, c.Contacts.List, ListParams{Limit: 200})
		found := false
		for it.Next() {
			if it.Item().ID == ct.ID {
				found = true
				break
			}
		}
		if it.Err() != nil || !found {
			t.Fatalf("contact not listed (err %v)", it.Err())
		}
		_, err = c.Contacts.Create(ctx, CreateContactParams{E164: r1})
		wantErr(t, err, 409, "A record with this phone number or name already exists.")
	})

	t.Run("18 contact groups", func(t *testing.T) {
		if contactID == "" {
			t.Skip("no contact from step 17")
		}
		g, err := c.ContactGroups.Create(ctx, CreateContactGroupParams{Name: "grp " + run, ContactIDs: []string{contactID}})
		if err != nil {
			t.Fatal(err)
		}
		if len(g.ContactIDs) != 1 || g.ContactIDs[0] != contactID {
			t.Fatalf("group = %+v", g)
		}
		groupID = g.ID
		u, err := c.ContactGroups.Update(ctx, g.ID, UpdateContactGroupParams{Name: "grp2 " + run})
		if err != nil {
			t.Fatal(err)
		}
		if u.Name != "grp2 "+run {
			t.Fatalf("update = %+v", u)
		}
		if gg, err := c.ContactGroups.Get(ctx, g.ID); err != nil || gg.Name != "grp2 "+run {
			t.Fatalf("get = %+v %v", gg, err)
		}
		b, err := c.ContactGroups.Send(ctx, g.ID, GroupSendParams{Text: "Hi " + run})
		if err != nil {
			t.Fatal(err)
		}
		if b.Status != "running" || b.Total != 1 {
			t.Fatalf("group send = %+v", b)
		}
		empty, err := c.ContactGroups.Create(ctx, CreateContactGroupParams{Name: "empty " + run})
		if err != nil {
			t.Fatal(err)
		}
		_, err = c.ContactGroups.Send(ctx, empty.ID, GroupSendParams{Text: "x"})
		wantErr(t, err, 422, "Group must contain between 1 and 1000 contacts.")
		if err := c.ContactGroups.Delete(ctx, empty.ID); err != nil {
			t.Fatal(err)
		}
		if p, err := c.ContactGroups.List(ctx, ListParams{Limit: 1}); err != nil || len(p.Items) == 0 {
			t.Fatalf("list = %+v %v", p, err)
		}
	})

	t.Run("19 templates", func(t *testing.T) {
		tp, err := c.Templates.Create(ctx, CreateTemplateParams{Name: "tpl-" + run, Body: "Hi {{name}}", TrafficType: "transactional"})
		if err != nil {
			t.Fatal(err)
		}
		if len(tp.Variables) != 1 || tp.Variables[0] != "name" {
			t.Fatalf("template = %+v", tp)
		}
		u, err := c.Templates.Update(ctx, tp.ID, UpdateTemplateParams{Body: "Hello {{name}}"})
		if err != nil {
			t.Fatal(err)
		}
		if u.Body != "Hello {{name}}" || len(u.Variables) != 1 || u.Variables[0] != "name" {
			t.Fatalf("update = %+v", u)
		}
		if g, err := c.Templates.Get(ctx, tp.ID); err != nil || g.ID != tp.ID {
			t.Fatalf("get = %+v %v", g, err)
		}
		if p, err := c.Templates.List(ctx, ListParams{Limit: 1}); err != nil || len(p.Items) == 0 {
			t.Fatalf("list = %+v %v", p, err)
		}
		if groupID != "" {
			b, err := c.ContactGroups.Send(ctx, groupID, GroupSendParams{TemplateID: tp.ID, Variables: map[string]string{"name": "Ada"}})
			if err != nil {
				t.Fatal(err)
			}
			if b.Status != "running" {
				t.Fatalf("template send = %+v", b)
			}
		}
		if err := c.Templates.Delete(ctx, tp.ID); err != nil {
			t.Fatal(err)
		}
		if groupID != "" {
			if err := c.ContactGroups.Delete(ctx, groupID); err != nil {
				t.Fatal(err)
			}
		}
		if contactID != "" {
			if err := c.Contacts.Delete(ctx, contactID); err != nil {
				t.Fatal(err)
			}
			_, err = c.Contacts.Get(ctx, contactID)
			wantErr(t, err, 404, "Record not found.")
		}
	})

	t.Run("20 webhooks", func(t *testing.T) {
		w, err := c.Webhooks.Create(ctx, CreateWebhookParams{URL: "https://example.com/opensms/" + run, Events: []string{"message.delivered", "message.failed"}})
		if err != nil {
			t.Fatal(err)
		}
		if !strings.HasPrefix(w.Secret, "whsec_") || !w.Enabled {
			t.Fatalf("webhook = %+v", w)
		}
		g, err := c.Webhooks.Get(ctx, w.ID)
		if err != nil {
			t.Fatal(err)
		}
		if g.Secret != "" {
			t.Fatal("get returned the secret")
		}
		_, err = c.Webhooks.Create(ctx, CreateWebhookParams{URL: "http://example.com/x", Events: []string{"message.delivered"}})
		wantErr(t, err, 400, "url must be an HTTPS URL without credentials or fragment")
		// Server drift (not in SURFACE.md): PUT refuses a URL change while the
		// endpoint has queued deliveries. With outbound delivery disabled and
		// other runs sending in the same workspace, message.delivered events
		// can queue on the new endpoint before this call, so accept that 409.
		u, err := c.Webhooks.Update(ctx, w.ID, UpdateWebhookParams{URL: "https://example.com/opensms/" + run + "/v2", Events: []string{"message.delivered"}, Enabled: true})
		if err != nil {
			wantErr(t, err, 409, "Queued deliveries retain their original destination; URL changes require an empty queue.")
			t.Logf("webhook update returned the queued-deliveries 409; checking update on a quiet endpoint")
		} else if u.URL != "https://example.com/opensms/"+run+"/v2" || len(u.Events) != 1 {
			t.Fatalf("update = %+v", u)
		}
		// The same full replacement on an endpoint whose event never fires here.
		quiet, err := c.Webhooks.Create(ctx, CreateWebhookParams{URL: "https://example.com/opensms/quiet/" + run, Events: []string{"number.renewed"}})
		if err != nil {
			t.Fatal(err)
		}
		qu, err := c.Webhooks.Update(ctx, quiet.ID, UpdateWebhookParams{URL: "https://example.com/opensms/quiet/" + run + "/v2", Events: []string{"message.delivered"}, Enabled: true})
		if err != nil {
			t.Fatal(err)
		}
		if qu.URL != "https://example.com/opensms/quiet/"+run+"/v2" || len(qu.Events) != 1 || qu.Events[0] != "message.delivered" || !qu.Enabled {
			t.Fatalf("quiet update = %+v", qu)
		}
		if err := c.Webhooks.Delete(ctx, quiet.ID); err != nil {
			t.Fatal(err)
		}
		if p, err := c.Webhooks.List(ctx, ListParams{Limit: 1}); err != nil || len(p.Items) == 0 {
			t.Fatalf("list = %+v %v", p, err)
		}
		st, err := c.Webhooks.Test(ctx, w.ID)
		if err != nil {
			t.Fatal(err)
		}
		if st.Status != "pending" {
			t.Fatalf("test = %+v", st)
		}
		var d WebhookDelivery
		poll(t, 20*time.Second, func() (bool, error) {
			p, err := c.Webhooks.ListDeliveries(ctx, w.ID, ListParams{})
			if err != nil {
				return false, err
			}
			for _, it := range p.Items {
				if it.Event == "webhook.test" {
					d = it
					return true, nil
				}
			}
			return false, nil
		})
		if d.ID == 0 {
			t.Fatalf("delivery = %+v", d)
		}
		_, err = c.Webhooks.ReplayDelivery(ctx, w.ID, d.ID, ReplayDeliveryParams{Generation: d.Generation, Reason: "sdk conformance replay"})
		if err != nil {
			wantErr(t, err, 409, "Delivery state, lease or generation does not permit replay.")
		}
		if err := c.Webhooks.Delete(ctx, w.ID); err != nil {
			t.Fatal(err)
		}
		_, err = c.Webhooks.Get(ctx, w.ID)
		wantErr(t, err, 404, "webhook not found")
	})

	t.Run("21 suppressions", func(t *testing.T) {
		r2, r3 := randPhone(), randPhone()
		s, err := c.Suppressions.Create(ctx, CreateSuppressionParams{E164: r2, Reason: "manual"})
		if err != nil {
			t.Fatal(err)
		}
		if s.ID == 0 || s.Reason != "manual" {
			t.Fatalf("suppression = %+v", s)
		}
		_, err = c.Messages.Send(ctx, SendMessageParams{To: r2, Text: "x"})
		if e := wantErr(t, err, 422, "destination is suppressed"); e.RequestID == "" {
			t.Fatal("no X-Request-ID on admission rejection")
		}
		it := Paginate(ctx, c.Suppressions.List, ListParams{Limit: 200})
		found := false
		for it.Next() {
			if it.Item().E164 == r2 {
				found = true
				break
			}
		}
		if it.Err() != nil || !found {
			t.Fatalf("suppression not listed (err %v)", it.Err())
		}
		imp, err := c.Suppressions.Import(ctx, []SuppressionInput{{E164: r3, Reason: "complaint"}})
		if err != nil {
			t.Fatal(err)
		}
		if imp.Created != 1 || imp.Received != 1 {
			t.Fatalf("import = %+v", imp)
		}
		if err := c.Suppressions.Delete(ctx, s.ID); err != nil {
			t.Fatal(err)
		}
		err = c.Suppressions.Delete(ctx, s.ID)
		wantErr(t, err, 404, "suppression not found")
	})

	t.Run("22 compliance", func(t *testing.T) {
		ke, err := c.Compliance.GetCountry(ctx, "KE")
		if err != nil {
			t.Fatal(err)
		}
		hasStop := false
		for _, k := range ke.StopKeywords {
			hasStop = hasStop || k == "STOP"
		}
		if ke.ISO2 != "KE" || ke.DialCode != "+254" || !hasStop {
			t.Fatalf("KE = %+v", ke)
		}
		_, err = c.Compliance.GetCountry(ctx, "ZZ")
		wantErr(t, err, 404, "country not found")
		all, err := c.Compliance.ListCountries(ctx)
		if err != nil {
			t.Fatal(err)
		}
		found := false
		for _, cr := range all {
			found = found || cr.ISO2 == "KE"
		}
		if !found {
			t.Fatal("KE missing from compliance countries")
		}
		rules, err := c.Compliance.ListContentRules(ctx)
		if err != nil {
			t.Fatal(err)
		}
		for _, r := range rules {
			if r.ID == 0 {
				t.Fatalf("rule without id: %+v", r)
			}
		}
	})

	t.Run("23 wallet", func(t *testing.T) {
		bals, err := c.Wallet.Balances(ctx)
		if err != nil {
			t.Fatal(err)
		}
		if len(bals) == 0 || bals[0].Environment != "sandbox" || bals[0].Currency != "KES" || !regexp.MustCompile(`^-?\d+\.\d+$`).MatchString(bals[0].Balance) {
			t.Fatalf("balances = %+v", bals)
		}
		led, err := c.Wallet.Ledger(ctx, LedgerParams{Limit: Int(1)})
		if err != nil {
			t.Fatal(err)
		}
		if len(led) != 1 || led[0].ID == 0 {
			t.Fatalf("ledger = %+v", led)
		}
		_, err = c.Wallet.Ledger(ctx, LedgerParams{Limit: Int(0)})
		wantErr(t, err, 400, "limit must be between 1 and 200")
		_, err = c.Wallet.CreateTopup(ctx, CreateTopupParams{Amount: "100", Currency: "KES", Channel: "card", Email: "dev@opensms.test"})
		wantErr(t, err, 422, "sandbox wallets cannot use payment providers")
	})

	t.Run("24 pricing", func(t *testing.T) {
		pl, err := c.Pricing.Get(ctx, PricingParams{Product: "sms", Country: "KE"})
		if err != nil {
			t.Fatal(err)
		}
		if pl.Currency != "KES" || pl.Product != "sms" {
			t.Fatalf("pricing = %+v", pl)
		}
		for _, e := range pl.Entries {
			if e.CountryISO2 != "KE" {
				t.Fatalf("entry = %+v", e)
			}
		}
		_, err = c.Pricing.Get(ctx, PricingParams{Product: "bogus"})
		wantErr(t, err, 400, "product must be sms, lookup, or number_monthly")
	})

	t.Run("25 analytics", func(t *testing.T) {
		ov, err := c.Analytics.Overview(ctx, AnalyticsParams{})
		if err != nil {
			t.Fatal(err)
		}
		if ov.Environment != "sandbox" || ov.Currency != "KES" {
			t.Fatalf("overview = %+v", ov)
		}
		if _, err := c.Analytics.Overview(ctx, AnalyticsParams{Range: "7d"}); err != nil {
			t.Fatal(err)
		}
		if _, err := c.Analytics.ByCountry(ctx, AnalyticsParams{}); err != nil {
			t.Fatal(err)
		}
		if _, err := c.Analytics.ByCarrier(ctx, AnalyticsParams{}); err != nil {
			t.Fatal(err)
		}
		if _, err := c.Analytics.BySenderID(ctx, AnalyticsParams{}); err != nil {
			t.Fatal(err)
		}
		if _, err := c.Analytics.Timeseries(ctx, AnalyticsParams{}); err != nil {
			t.Fatal(err)
		}
	})

	t.Run("26 numbers and inbound", func(t *testing.T) {
		if _, err := c.Numbers.List(ctx, ListParams{}); err != nil {
			t.Fatal(err)
		}
		if _, err := c.Numbers.Available(ctx, AvailableNumbersParams{Country: "KE", Kind: "long_code"}); err != nil {
			t.Fatal(err)
		}
		_, err := c.Numbers.Assign(ctx, AssignNumberParams{Country: "KE", Kind: "long_code"})
		wantErr(t, err, 422, "This operation requires the live environment.")
		p, err := c.Inbound.List(ctx, ListParams{})
		if err != nil {
			t.Fatal(err)
		}
		if len(p.Items) != 0 {
			t.Fatalf("inbound items = %d", len(p.Items))
		}
	})

	t.Run("27 sender ids", func(t *testing.T) {
		it := Paginate(ctx, c.SenderIDs.List, ListParams{Limit: 200})
		found := false
		for it.Next() {
			s := it.Item()
			if s.Value == "OPENSMS" && s.Status == "approved" {
				found = true
				break
			}
		}
		if it.Err() != nil || !found {
			t.Fatalf("OPENSMS approved sender not listed (err %v)", it.Err())
		}
		chk, err := c.SenderIDs.Check(ctx, CheckSenderIDParams{Value: "ACME", Country: "KE"})
		if err != nil {
			t.Fatal(err)
		}
		if !chk.Valid {
			t.Fatalf("check = %+v", chk)
		}
		q, err := c.SenderIDs.Quote(ctx, QuoteSenderIDParams{Countries: []string{"KE"}})
		if err != nil {
			t.Fatal(err)
		}
		if !strings.HasPrefix(q.QuoteID, "sq_") {
			t.Fatalf("quote = %+v", q)
		}
		if _, err := c.SenderIDs.ListDocuments(ctx); err != nil {
			t.Fatal(err)
		}
		d, err := c.SenderIDs.CreateDraft(ctx, SenderIDDraftParams{
			Source: "application", Value: "SDK" + randUpper(4), Kind: "alphanumeric",
			Countries: []string{"KE"}, UseCase: "transactional", SampleMessage: "Your order shipped",
		})
		if err != nil {
			t.Fatal(err)
		}
		if d.Version != 1 || d.Status != "active" {
			t.Fatalf("draft = %+v", d)
		}
		u, err := c.SenderIDs.UpdateDraft(ctx, d.ID, UpdateSenderIDDraftParams{Version: 1, SampleMessage: "Your order has shipped"})
		if err != nil {
			t.Fatal(err)
		}
		if u.Version != 2 {
			t.Fatalf("updated draft = %+v", u)
		}
		if g, err := c.SenderIDs.GetDraft(ctx, d.ID); err != nil || g.ID != d.ID {
			t.Fatalf("get draft = %+v %v", g, err)
		}
		if _, err := c.SenderIDs.ListDrafts(ctx, ListParams{}); err != nil {
			t.Fatal(err)
		}
		if err := c.SenderIDs.DeleteDraft(ctx, d.ID); err != nil {
			t.Fatal(err)
		}
		_, err = c.SenderIDs.Get(ctx, zeroUUID)
		wantErr(t, err, 404, "sender ID not found")
	})

	t.Run("28 countries", func(t *testing.T) {
		cs, err := c.Countries.List(ctx)
		if err != nil {
			t.Fatal(err)
		}
		found := false
		for _, co := range cs {
			found = found || (co.ISO2 == "KE" && co.DialCode == "+254")
		}
		if !found {
			t.Fatal("KE +254 not in countries")
		}
		cars, err := c.Countries.Carriers(ctx, "KE")
		if err != nil || len(cars) == 0 {
			t.Fatalf("carriers = %d %v", len(cars), err)
		}
		if _, err := c.Countries.Routes(ctx, "KE"); err != nil {
			t.Fatal(err)
		}
		cr, err := c.Countries.Compliance(ctx, "KE")
		if err != nil || cr.ISO2 != "KE" {
			t.Fatalf("compliance = %+v %v", cr, err)
		}
	})

	t.Run("29 scope errors", func(t *testing.T) {
		ro := os.Getenv("OPENSMS_READONLY_API_KEY")
		if ro == "" {
			t.Skip("OPENSMS_READONLY_API_KEY not set")
		}
		rc := liveClient(t, base, ro)
		_, err := rc.Messages.Send(ctx, SendMessageParams{To: liveTo, Text: "scope " + run})
		wantErr(t, err, 401, "insufficient scope")
		_, err = rc.Contacts.List(ctx, ListParams{})
		wantErr(t, err, 403, "Insufficient API key scope.")
		if _, err := rc.Messages.List(ctx, ListMessagesParams{Limit: 1}); err != nil {
			t.Fatal(err)
		}
	})
}
