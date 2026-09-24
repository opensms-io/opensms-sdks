"""The ``contacts`` resource."""

from __future__ import annotations

from typing import Any, Dict, Optional

from .._serialize import path_id, prune
from ..models import Contact, Page
from ._base import Resource


class Contacts(Resource):
    """Address book. Accessed as ``client.contacts``."""

    def list(self, *, limit: Optional[int] = None, cursor: Optional[str] = None) -> Page[Contact]:
        """List contacts."""
        return self._page(self._t.request("GET", "/v1/contacts", query={"limit": limit, "cursor": cursor}))

    def create(
        self,
        *,
        e164: str,
        name: Optional[str] = None,
        attributes: Optional[Dict[str, Any]] = None,
        idempotency_key: Optional[str] = None,
    ) -> Contact:
        """Create a contact. A duplicate ``e164`` returns ``409``."""
        body = prune({"e164": e164, "name": name, "attributes": attributes})
        return self._t.request(
            "POST", "/v1/contacts", json_body=body, idempotent=True, idempotency_key=idempotency_key
        )

    def get(self, id: str) -> Contact:
        """Fetch a contact."""
        return self._t.request("GET", f"/v1/contacts/{path_id(id)}")

    def update(
        self,
        id: str,
        *,
        e164: Optional[str] = None,
        name: Optional[str] = None,
        attributes: Optional[Dict[str, Any]] = None,
    ) -> Contact:
        """Update the given fields; others are kept (PATCH)."""
        body = prune({"e164": e164, "name": name, "attributes": attributes})
        return self._t.request("PATCH", f"/v1/contacts/{path_id(id)}", json_body=body)

    def delete(self, id: str) -> None:
        """Delete a contact."""
        self._t.request("DELETE", f"/v1/contacts/{path_id(id)}")
