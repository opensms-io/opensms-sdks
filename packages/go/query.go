package opensms

import (
	"net/url"
	"strconv"
	"time"
)

// queryBuilder collects query parameters, skipping unset values.
type queryBuilder struct{ v url.Values }

func newQuery() *queryBuilder { return &queryBuilder{v: url.Values{}} }

func (q *queryBuilder) str(key, val string) *queryBuilder {
	if val != "" {
		q.v.Set(key, val)
	}
	return q
}

func (q *queryBuilder) int(key string, val int64) *queryBuilder {
	if val != 0 {
		q.v.Set(key, strconv.FormatInt(val, 10))
	}
	return q
}

func (q *queryBuilder) time(key string, val time.Time) *queryBuilder {
	if !val.IsZero() {
		q.v.Set(key, rfc3339UTC(val))
	}
	return q
}

func (q *queryBuilder) values() url.Values { return q.v }

func listQuery(p ListParams) url.Values {
	return newQuery().int("limit", int64(p.Limit)).str("cursor", p.Cursor).values()
}
