"""The ``inbound`` resource."""

from __future__ import annotations

from typing import Optional

from .._serialize import path_id
from ..models import InboundMessage, Message, Page
from ._base import Resource


class Inbound(Resource):
    """Messages received on your numbers. Accessed as ``client.inbound``."""

    def list(self, *, limit: Optional[int] = None, cursor: Optional[str] = None) -> Page[InboundMessage]:
        """List inbound messages (always empty in sandbox)."""
        return self._page(self._t.request("GET", "/v1/inbound", query={"limit": limit, "cursor": cursor}))

    def reply(self, id: str, *, text: str, idempotency_key: Optional[str] = None) -> Message:
        """Reply to an inbound message from the number it arrived on. Live
        keys only. Returns the outbound Message."""
        return self._t.request(
            "POST",
            f"/v1/inbound/{path_id(id)}/reply",
            json_body={"text": text},
            idempotent=True,
            idempotency_key=idempotency_key,
        )
