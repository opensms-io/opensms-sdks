"""The ``sandbox`` resource."""

from __future__ import annotations

from typing import Optional

from ..models import Page, SandboxMessage
from ._base import Resource


class Sandbox(Resource):
    """Sandbox inspection. Accessed as ``client.sandbox``."""

    def list_messages(
        self, *, limit: Optional[int] = None, cursor: Optional[str] = None
    ) -> Page[SandboxMessage]:
        """Rendered texts of sandbox sends, including OTP codes."""
        return self._page(
            self._t.request("GET", "/v1/sandbox/messages", query={"limit": limit, "cursor": cursor})
        )
