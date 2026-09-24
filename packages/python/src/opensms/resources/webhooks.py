"""The ``webhooks`` resource."""

from __future__ import annotations

from typing import List, Optional

from .._serialize import path_id, prune
from ..models import Page, StatusResult, WebhookDelivery, WebhookEndpoint, WebhookEvent
from ..signature import DEFAULT_TOLERANCE_SECONDS, Payload, construct_event, verify_signature
from ._base import Resource


class Webhooks(Resource):
    """Webhook endpoints, deliveries and signature checks. Accessed as
    ``client.webhooks``."""

    def list(self, *, limit: Optional[int] = None, cursor: Optional[str] = None) -> Page[WebhookEndpoint]:
        """List endpoints."""
        return self._page(self._t.request("GET", "/v1/webhooks", query={"limit": limit, "cursor": cursor}))

    def create(
        self,
        *,
        url: str,
        events: List[str],
        enabled: Optional[bool] = None,
        idempotency_key: Optional[str] = None,
    ) -> WebhookEndpoint:
        """Create an endpoint. ``url`` must be HTTPS. The result carries the
        signing ``secret`` (``whsec_...``); it is shown only once."""
        body = prune({"url": url, "events": list(events), "enabled": enabled})
        return self._t.request(
            "POST", "/v1/webhooks", json_body=body, idempotent=True, idempotency_key=idempotency_key
        )

    def get(self, id: str) -> WebhookEndpoint:
        """Fetch an endpoint (never includes the secret)."""
        return self._t.request("GET", f"/v1/webhooks/{path_id(id)}")

    def update(
        self,
        id: str,
        *,
        url: str,
        events: List[str],
        enabled: bool,
        idempotency_key: Optional[str] = None,
    ) -> WebhookEndpoint:
        """Replace an endpoint. ``url``, ``events`` and ``enabled`` are all
        required (full replacement)."""
        body = {"url": url, "events": list(events), "enabled": enabled}
        return self._t.request(
            "PUT",
            f"/v1/webhooks/{path_id(id)}",
            json_body=body,
            idempotent=True,
            idempotency_key=idempotency_key,
        )

    def delete(self, id: str, *, idempotency_key: Optional[str] = None) -> None:
        """Delete an endpoint."""
        self._t.request(
            "DELETE", f"/v1/webhooks/{path_id(id)}", idempotent=True, idempotency_key=idempotency_key
        )

    def test(self, id: str, *, idempotency_key: Optional[str] = None) -> StatusResult:
        """Queue a ``webhook.test`` delivery to the endpoint."""
        return self._t.request(
            "POST", f"/v1/webhooks/{path_id(id)}/test", idempotent=True, idempotency_key=idempotency_key
        )

    def list_deliveries(
        self, id: str, *, limit: Optional[int] = None, cursor: Optional[str] = None
    ) -> Page[WebhookDelivery]:
        """List delivery attempts for an endpoint."""
        return self._page(
            self._t.request(
                "GET", f"/v1/webhooks/{path_id(id)}/deliveries", query={"limit": limit, "cursor": cursor}
            )
        )

    def replay_delivery(
        self,
        id: str,
        delivery_id: int,
        *,
        generation: int,
        reason: str,
        idempotency_key: Optional[str] = None,
    ) -> StatusResult:
        """Replay a delivery. ``generation`` comes from the delivery;
        ``reason`` is 5..1000 characters."""
        return self._t.request(
            "POST",
            f"/v1/webhooks/{path_id(id)}/deliveries/{path_id(delivery_id, 'delivery_id')}/replay",
            json_body={"generation": generation, "reason": reason},
            idempotent=True,
            idempotency_key=idempotency_key,
        )

    @staticmethod
    def verify_signature(
        payload: Payload,
        header: Optional[str],
        secret: str,
        *,
        tolerance_seconds: float = DEFAULT_TOLERANCE_SECONDS,
        now: Optional[float] = None,
    ) -> bool:
        """See :func:`opensms.verify_signature`."""
        return verify_signature(payload, header, secret, tolerance_seconds=tolerance_seconds, now=now)

    @staticmethod
    def construct_event(
        payload: Payload,
        header: Optional[str],
        secret: str,
        *,
        tolerance_seconds: float = DEFAULT_TOLERANCE_SECONDS,
        now: Optional[float] = None,
    ) -> WebhookEvent:
        """See :func:`opensms.construct_event`."""
        return construct_event(payload, header, secret, tolerance_seconds=tolerance_seconds, now=now)
