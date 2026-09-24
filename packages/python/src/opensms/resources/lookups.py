"""The ``lookups`` resource."""

from __future__ import annotations

from typing import Optional

from .._serialize import path_id
from ..models import Lookup
from ._base import Resource


class Lookups(Resource):
    """Number lookups (HLR). Accessed as ``client.lookups``."""

    def create(self, *, to: str, idempotency_key: Optional[str] = None) -> Lookup:
        """Look up a number. Returns the completed lookup, or a pending one
        (``state`` ``queued``) to poll with :meth:`get`."""
        return self._t.request(
            "POST", "/v1/lookup", json_body={"to": to}, idempotent=True, idempotency_key=idempotency_key
        )

    def get(self, id: str) -> Lookup:
        """Fetch a lookup."""
        return self._t.request("GET", f"/v1/lookup/{path_id(id)}")
