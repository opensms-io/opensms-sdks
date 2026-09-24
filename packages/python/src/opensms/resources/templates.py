"""The ``templates`` resource."""

from __future__ import annotations

from typing import Optional

from .._serialize import path_id, prune
from ..models import Page, Template
from ._base import Resource


class Templates(Resource):
    """Reusable message templates with ``{{name}}`` placeholders. Accessed as
    ``client.templates``."""

    def list(self, *, limit: Optional[int] = None, cursor: Optional[str] = None) -> Page[Template]:
        """List templates."""
        return self._page(self._t.request("GET", "/v1/templates", query={"limit": limit, "cursor": cursor}))

    def create(
        self,
        *,
        name: str,
        body: str,
        traffic_type: Optional[str] = None,
        idempotency_key: Optional[str] = None,
    ) -> Template:
        """Create a template. ``variables`` in the result lists its placeholders."""
        payload = prune({"name": name, "body": body, "traffic_type": traffic_type})
        return self._t.request(
            "POST", "/v1/templates", json_body=payload, idempotent=True, idempotency_key=idempotency_key
        )

    def get(self, id: str) -> Template:
        """Fetch a template."""
        return self._t.request("GET", f"/v1/templates/{path_id(id)}")

    def update(
        self,
        id: str,
        *,
        name: Optional[str] = None,
        body: Optional[str] = None,
        traffic_type: Optional[str] = None,
    ) -> Template:
        """Update the given fields (PATCH)."""
        payload = prune({"name": name, "body": body, "traffic_type": traffic_type})
        return self._t.request("PATCH", f"/v1/templates/{path_id(id)}", json_body=payload)

    def delete(self, id: str) -> None:
        """Delete a template."""
        self._t.request("DELETE", f"/v1/templates/{path_id(id)}")
