"""The ``messages`` resource."""

from __future__ import annotations

from datetime import date, datetime
from typing import Any, Dict, List, Optional, Union

from .._serialize import path_id, prune, to_rfc3339
from ..models import Attempt, Message, Page
from ._base import Resource

DateLike = Union[str, date, datetime]


class Messages(Resource):
    """Send and inspect SMS. Accessed as ``client.messages``."""

    def send(
        self,
        *,
        to: str,
        text: str,
        sender_id: Optional[str] = None,
        traffic_type: Optional[str] = None,
        scheduled_at: Optional[Union[str, datetime]] = None,
        callback_url: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
        idempotency_key: Optional[str] = None,
    ) -> Message:
        """Send one SMS (``POST /v1/messages``). An Idempotency-Key is always
        sent (generated when not given) and reused on retries."""
        body = prune(
            {
                "to": to,
                "text": text,
                "sender_id": sender_id,
                "traffic_type": traffic_type,
                "scheduled_at": to_rfc3339(scheduled_at),
                "callback_url": callback_url,
                "metadata": metadata,
            }
        )
        return self._t.request(
            "POST", "/v1/messages", json_body=body, idempotent=True, idempotency_key=idempotency_key
        )

    def list(
        self,
        *,
        limit: Optional[int] = None,
        cursor: Optional[str] = None,
        status: Optional[str] = None,
        to: Optional[str] = None,
        country: Optional[str] = None,
        date_from: Optional[DateLike] = None,
        date_to: Optional[DateLike] = None,
    ) -> Page[Message]:
        """List messages, newest first (``limit`` 1..100, default 20)."""
        query = {
            "limit": limit,
            "cursor": cursor,
            "status": status,
            "to": to,
            "country": country,
            "date_from": date_from,
            "date_to": date_to,
        }
        return self._page(self._t.request("GET", "/v1/messages", query=query))

    def get(self, id: str) -> Message:
        """Fetch one message."""
        return self._t.request("GET", f"/v1/messages/{path_id(id)}")

    def attempts(self, id: str) -> List[Attempt]:
        """List provider submission attempts for a message."""
        return self._t.request("GET", f"/v1/messages/{path_id(id)}/attempts")

    def cancel(self, id: str) -> Message:
        """Cancel a ``queued`` or ``scheduled`` message. Never retried."""
        return self._t.request("POST", f"/v1/messages/{path_id(id)}/cancel")
