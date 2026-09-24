package opensms

import "context"

// Page is one page of a cursor-paginated list. NextCursor is empty on the
// last page; pass it back as Cursor to fetch the next one.
type Page[T any] struct {
	Items      []T    `json:"items"`
	NextCursor string `json:"next_cursor"`
}

// HasMore reports whether another page exists.
func (p *Page[T]) HasMore() bool { return p != nil && p.NextCursor != "" }

// Cursorable is implemented by list parameter types. WithCursor returns a copy
// of the parameters with Cursor set.
type Cursorable[P any] interface {
	WithCursor(cursor string) P
}

// ListFunc is the shape of every cursor list method.
type ListFunc[T any, P any] func(ctx context.Context, params P) (*Page[T], error)

// Iterator walks every item of a cursor-paginated list, fetching pages
// lazily. Use it as:
//
//	it := opensms.Paginate(ctx, client.Messages.List, opensms.ListMessagesParams{Limit: 50})
//	for it.Next() {
//		m := it.Item()
//	}
//	if err := it.Err(); err != nil { ... }
type Iterator[T any, P Cursorable[P]] struct {
	ctx    context.Context
	list   ListFunc[T, P]
	params P

	items   []T
	idx     int
	cur     T
	cursor  string
	started bool
	done    bool
	err     error
}

// Paginate returns an Iterator over list, starting from params and feeding
// each page's NextCursor back as the cursor until it is empty. For list
// methods that take an id (Batches.ListItems, Webhooks.ListDeliveries,
// Numbers.ListRules), wrap the call in a closure that captures the id.
func Paginate[T any, P Cursorable[P]](ctx context.Context, list func(context.Context, P) (*Page[T], error), params P) *Iterator[T, P] {
	return &Iterator[T, P]{ctx: ctx, list: list, params: params}
}

// Next advances to the next item, fetching a page when needed. It returns
// false at the end of the list or on error.
func (it *Iterator[T, P]) Next() bool {
	for {
		if it.err != nil {
			return false
		}
		if it.idx < len(it.items) {
			it.cur = it.items[it.idx]
			it.idx++
			return true
		}
		if it.done {
			return false
		}
		params := it.params
		if it.started {
			params = it.params.WithCursor(it.cursor)
		}
		it.started = true
		page, err := it.list(it.ctx, params)
		if err != nil {
			it.err = err
			return false
		}
		it.items = page.Items
		it.idx = 0
		it.cursor = page.NextCursor
		if it.cursor == "" {
			it.done = true
		}
	}
}

// Item returns the current item.
func (it *Iterator[T, P]) Item() T { return it.cur }

// Err returns the first error encountered, if any.
func (it *Iterator[T, P]) Err() error { return it.err }
