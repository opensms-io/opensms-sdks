"""Shared base for resource classes."""

from __future__ import annotations

from typing import Any

from .._transport import HttpTransport
from ..models import Page


class Resource:
    """Holds the transport. Resources only build path, query and body."""

    def __init__(self, transport: HttpTransport) -> None:
        self._t = transport

    @staticmethod
    def _page(data: Any) -> Page[Any]:
        return Page.from_wire(data)
