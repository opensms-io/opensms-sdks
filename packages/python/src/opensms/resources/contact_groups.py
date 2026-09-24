"""The ``contact_groups`` resource."""

from __future__ import annotations

from typing import Dict, List, Optional

from .._serialize import path_id, prune
from ..models import Batch, ContactGroup, Page
from ._base import Resource


class ContactGroups(Resource):
    """Groups of contacts. Accessed as ``client.contact_groups``."""

    def list(self, *, limit: Optional[int] = None, cursor: Optional[str] = None) -> Page[ContactGroup]:
        """List contact groups."""
        return self._page(
            self._t.request("GET", "/v1/contact-groups", query={"limit": limit, "cursor": cursor})
        )

    def create(
        self,
        *,
        name: str,
        contact_ids: Optional[List[str]] = None,
        idempotency_key: Optional[str] = None,
    ) -> ContactGroup:
        """Create a group."""
        body = prune({"name": name, "contact_ids": contact_ids})
        return self._t.request(
            "POST", "/v1/contact-groups", json_body=body, idempotent=True, idempotency_key=idempotency_key
        )

    def get(self, id: str) -> ContactGroup:
        """Fetch a group."""
        return self._t.request("GET", f"/v1/contact-groups/{path_id(id)}")

    def update(
        self,
        id: str,
        *,
        name: Optional[str] = None,
        contact_ids: Optional[List[str]] = None,
    ) -> ContactGroup:
        """Rename a group and/or replace its members."""
        body = prune({"name": name, "contact_ids": contact_ids})
        return self._t.request("PATCH", f"/v1/contact-groups/{path_id(id)}", json_body=body)

    def delete(self, id: str) -> None:
        """Delete a group (contacts are kept)."""
        self._t.request("DELETE", f"/v1/contact-groups/{path_id(id)}")

    def send(
        self,
        id: str,
        *,
        text: Optional[str] = None,
        template_id: Optional[str] = None,
        variables: Optional[Dict[str, str]] = None,
        sender_id: Optional[str] = None,
        traffic_type: Optional[str] = None,
        callback_url: Optional[str] = None,
        idempotency_key: Optional[str] = None,
    ) -> Batch:
        """Send ``text`` or a ``template_id`` to every member. Returns a
        running Batch."""
        body = prune(
            {
                "text": text,
                "template_id": template_id,
                "variables": variables,
                "sender_id": sender_id,
                "traffic_type": traffic_type,
                "callback_url": callback_url,
            }
        )
        return self._t.request(
            "POST",
            f"/v1/contact-groups/{path_id(id)}/send",
            json_body=body,
            idempotent=True,
            idempotency_key=idempotency_key,
        )
