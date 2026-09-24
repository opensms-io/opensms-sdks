"""Internal helpers that turn Python values into the exact wire format the API
expects: path segments, query strings and JSON bodies. Not part of the public
API."""

from __future__ import annotations

from datetime import date, datetime, timezone
from typing import Any, Dict, Mapping, Optional
from urllib.parse import quote


def path_id(value: Any, name: str = "id") -> str:
    """Validate a non-empty id and URL-escape it as one path segment."""
    if value is None or str(value).strip() == "":
        raise ValueError(f"{name} is required")
    return quote(str(value), safe="")


def to_rfc3339(value: Any) -> Any:
    """Serialize ``datetime`` as RFC 3339 UTC (``2026-09-24T10:00:00Z``).

    A naive ``datetime`` is taken to be UTC. ``date`` becomes ``YYYY-MM-DD``.
    Strings pass through unchanged.
    """
    if isinstance(value, datetime):
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        text = value.astimezone(timezone.utc).isoformat()
        return text.replace("+00:00", "Z")
    if isinstance(value, date):
        return value.isoformat()
    return value


def prune(body: Mapping[str, Any]) -> Dict[str, Any]:
    """Drop keys whose value is ``None`` so unset optionals are absent, never
    ``null`` (the API rejects unknown fields and treats null differently)."""
    return {k: v for k, v in body.items() if v is not None}


def _query_value(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (list, tuple)):
        return ",".join(_query_value(v) for v in value)
    value = to_rfc3339(value)
    return str(value)


def build_query(params: Optional[Mapping[str, Any]]) -> str:
    """Build ``?a=1&b=2`` from params, skipping ``None``. Lists are joined with
    commas. ``+`` is encoded as ``%2B``. Returns ``""`` when nothing is set."""
    if not params:
        return ""
    parts = []
    for key, value in params.items():
        if value is None:
            continue
        parts.append(f"{quote(key, safe='')}={quote(_query_value(value), safe=',')}")
    return "?" + "&".join(parts) if parts else ""
