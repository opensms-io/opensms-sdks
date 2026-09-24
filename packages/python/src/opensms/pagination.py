"""Auto-pagination over cursor list methods."""

from __future__ import annotations

from typing import Any, Callable, Iterator, Optional, TypeVar

from .models import Page

T = TypeVar("T")


def paginate(list_method: Callable[..., "Page[T]"], *args: Any, **params: Any) -> Iterator[T]:
    """Yield every item of a cursor list lazily.

    Calls ``list_method(*args, **params)``, then keeps feeding the returned
    ``next_cursor`` back as ``cursor`` (with the same other params) until it
    is ``None``::

        for message in paginate(client.messages.list, limit=50):
            ...

    Positional ``args`` are forwarded, so id-scoped lists work too:
    ``paginate(client.batches.list_items, batch_id, limit=100)``.
    """
    cursor: Optional[str] = params.pop("cursor", None)
    while True:
        page = list_method(*args, cursor=cursor, **params)
        for item in page.items:
            yield item
        cursor = page.next_cursor
        if not cursor:
            return
