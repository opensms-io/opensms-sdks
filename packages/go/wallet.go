package opensms

import (
	"context"
	"net/http"
	"strconv"
)

// Wallet reads balances and the ledger, reached as client.Wallet.
type Wallet struct {
	http *transport
}

type dataEnvelope[T any] struct {
	Data []T `json:"data"`
}

// Balances returns every currency wallet (GET /v1/wallet).
func (r *Wallet) Balances(ctx context.Context) ([]WalletBalance, error) {
	out, err := call[dataEnvelope[WalletBalance]](ctx, r.http, request{method: http.MethodGet, path: "/v1/wallet"})
	if err != nil {
		return nil, err
	}
	return out.Data, nil
}

// Ledger returns ledger entries, newest first (GET /v1/wallet/ledger). It
// pages with Before (the smallest id seen), not cursors.
func (r *Wallet) Ledger(ctx context.Context, params LedgerParams) ([]LedgerEntry, error) {
	q := newQuery().int("before", params.Before).values()
	if params.Limit != nil {
		q.Set("limit", strconv.Itoa(*params.Limit))
	}
	out, err := call[dataEnvelope[LedgerEntry]](ctx, r.http, request{method: http.MethodGet, path: "/v1/wallet/ledger", query: q})
	if err != nil {
		return nil, err
	}
	return out.Data, nil
}

// CreateTopup starts a payment-provider top-up (POST /v1/wallet/topups).
// Live keys only.
func (r *Wallet) CreateTopup(ctx context.Context, params CreateTopupParams, opts ...CallOption) (*Topup, error) {
	return call[Topup](ctx, r.http, request{method: http.MethodPost, path: "/v1/wallet/topups", body: params, idempotent: true, opts: applyCallOptions(opts)})
}
