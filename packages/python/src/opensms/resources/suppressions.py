"""The ``suppressions`` resource."""

from __future__ import annotations

from typing import Iterable, Mapping, Optional, Union

from .._serialize import path_id
from ..models import Page, Suppression, SuppressionImportResult
from ._base import Resource


class Suppressions(Resource):
    """Numbers that must never be messaged. Accessed as ``client.suppressions``."""

    def list(self, *, limit: Optional[int] = None, cursor: Optional[str] = None) -> Page[Suppression]:
        """List suppressions."""
        return self._page(
            self._t.request("GET", "/v1/compliance/suppressions", query={"limit": limit, "cursor": cursor})
        )

    def create(self, *, e164: str, reason: str) -> Suppression:
        """Suppress a number (``reason`` ``stop_keyword``, ``manual``,
        ``complaint`` or ``invalid_number``). Never retried."""
        return self._t.request(
            "POST", "/v1/compliance/suppressions", json_body={"e164": e164, "reason": reason}
        )

    def import_(self, items: Iterable[Mapping[str, str]]) -> SuppressionImportResult:
        """Bulk import ``[{"e164", "reason"}]``. Named ``import_`` because
        ``import`` is a Python keyword; ``getattr(s, "import")`` also works.
        Never retried."""
        body = {"items": [{"e164": i["e164"], "reason": i["reason"]} for i in items]}
        return self._t.request("POST", "/v1/compliance/suppressions/import", json_body=body)

    def delete(self, id: Union[int, str]) -> None:
        """Remove a suppression."""
        self._t.request("DELETE", f"/v1/compliance/suppressions/{path_id(id)}")


# Expose the canonical SURFACE.md name too, reachable via getattr.
setattr(Suppressions, "import", Suppressions.import_)
