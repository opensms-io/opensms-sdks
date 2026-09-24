"""The ``sender_ids`` resource (sender IDs, drafts and the document list)."""

from __future__ import annotations

from typing import Any, List, Optional

from .._serialize import path_id, prune
from ..models import Page, SenderDocument, SenderId, SenderIdCheck, SenderIdDraft, SenderIdQuote
from ._base import Resource


class SenderIds(Resource):
    """Alphanumeric and numeric sender IDs. Accessed as ``client.sender_ids``."""

    def list(self, *, limit: Optional[int] = None, cursor: Optional[str] = None) -> Page[SenderId]:
        """List sender IDs."""
        return self._page(self._t.request("GET", "/v1/sender-ids", query={"limit": limit, "cursor": cursor}))

    def get(self, id: str) -> SenderId:
        """Fetch a sender ID with its registrations."""
        return self._t.request("GET", f"/v1/sender-ids/{path_id(id)}")

    def create(
        self,
        *,
        value: str,
        kind: str,
        countries: List[str],
        documents: List[Any],
        use_case: Optional[str] = None,
        sample_message: Optional[str] = None,
        draft_id: Optional[str] = None,
        draft_version: Optional[int] = None,
        quote_id: Optional[str] = None,
    ) -> SenderId:
        """Register a sender ID. May charge registration fees (see
        :meth:`quote`), so it is never retried automatically."""
        body = prune(
            {
                "value": value,
                "kind": kind,
                "countries": list(countries),
                "documents": list(documents),
                "use_case": use_case,
                "sample_message": sample_message,
                "draft_id": draft_id,
                "draft_version": draft_version,
                "quote_id": quote_id,
            }
        )
        return self._t.request("POST", "/v1/sender-ids", json_body=body)

    def update(
        self,
        id: str,
        *,
        use_case: str,
        countries: List[str],
        documents: List[Any],
        sample_message: Optional[str] = None,
    ) -> SenderId:
        """Amend a sender ID application."""
        body = prune(
            {
                "use_case": use_case,
                "countries": list(countries),
                "documents": list(documents),
                "sample_message": sample_message,
            }
        )
        return self._t.request("PATCH", f"/v1/sender-ids/{path_id(id)}", json_body=body)

    def delete(self, id: str) -> None:
        """Delete a sender ID."""
        self._t.request("DELETE", f"/v1/sender-ids/{path_id(id)}")

    def check(self, *, value: str, country: Optional[str] = None) -> SenderIdCheck:
        """Check whether a value is valid, available and not reserved."""
        return self._t.request("GET", "/v1/sender-ids/check", query={"value": value, "country": country})

    def quote(self, *, countries: List[str]) -> SenderIdQuote:
        """Quote registration fees for the given countries."""
        return self._t.request("GET", "/v1/sender-ids/quote", query={"countries": list(countries)})

    def list_documents(self) -> List[SenderDocument]:
        """List uploaded sender documents (upload itself is console only).
        Returns the ``items`` list; there is no cursor."""
        data = self._t.request("GET", "/v1/sender-documents")
        if isinstance(data, dict):
            return list(data.get("items") or [])
        return data or []

    def list_drafts(self, *, limit: Optional[int] = None, cursor: Optional[str] = None) -> Page[SenderIdDraft]:
        """List application drafts."""
        return self._page(
            self._t.request("GET", "/v1/sender-id-drafts", query={"limit": limit, "cursor": cursor})
        )

    def create_draft(
        self,
        *,
        source: Optional[str] = None,
        value: Optional[str] = None,
        kind: Optional[str] = None,
        countries: Optional[List[str]] = None,
        use_case: Optional[str] = None,
        sample_message: Optional[str] = None,
        documents: Optional[List[str]] = None,
    ) -> SenderIdDraft:
        """Start an application draft (``source`` ``application`` or
        ``onboarding``)."""
        body = prune(
            {
                "source": source,
                "value": value,
                "kind": kind,
                "countries": countries,
                "use_case": use_case,
                "sample_message": sample_message,
                "documents": documents,
            }
        )
        return self._t.request("POST", "/v1/sender-id-drafts", json_body=body)

    def get_draft(self, id: str) -> SenderIdDraft:
        """Fetch a draft."""
        return self._t.request("GET", f"/v1/sender-id-drafts/{path_id(id)}")

    def update_draft(
        self,
        id: str,
        *,
        version: int,
        source: Optional[str] = None,
        value: Optional[str] = None,
        kind: Optional[str] = None,
        countries: Optional[List[str]] = None,
        use_case: Optional[str] = None,
        sample_message: Optional[str] = None,
        documents: Optional[List[str]] = None,
    ) -> SenderIdDraft:
        """Update a draft. ``version`` must be the current version
        (optimistic lock, ``409`` on mismatch)."""
        body = prune(
            {
                "version": version,
                "source": source,
                "value": value,
                "kind": kind,
                "countries": countries,
                "use_case": use_case,
                "sample_message": sample_message,
                "documents": documents,
            }
        )
        return self._t.request("PATCH", f"/v1/sender-id-drafts/{path_id(id)}", json_body=body)

    def delete_draft(self, id: str) -> None:
        """Delete a draft."""
        self._t.request("DELETE", f"/v1/sender-id-drafts/{path_id(id)}")
