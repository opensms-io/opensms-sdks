"""Webhook signature verification.

The API signs every delivery with ``X-OpenSMS-Signature: t=<unix>,v1=<hex>``
where ``v1 = hex(HMAC-SHA256(secret, "<t>." + raw_body))``. The secret is the
full ``whsec_...`` string returned once by ``webhooks.create``, used verbatim.
Parsing mirrors the server (``internal/webhooks/signature.go``) exactly.
These functions need no API key, so a webhook receiver can import them
directly: ``from opensms import verify_signature, construct_event``.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import re
import time
from typing import Dict, Optional, Union

from .errors import OpensmsError
from .models import WebhookEvent

#: Header that carries the signature.
SIGNATURE_HEADER = "X-OpenSMS-Signature"
DEFAULT_TOLERANCE_SECONDS = 300

Payload = Union[bytes, bytearray, str]

_HEX = set("0123456789abcdefABCDEF")
_INT = re.compile(r"\A[+-]?[0-9]+\Z")


def _as_bytes(value: Payload) -> bytes:
    if isinstance(value, str):
        return value.encode("utf-8")
    return bytes(value)


def _parse_header(header: str) -> Optional[Dict[str, str]]:
    values: Dict[str, str] = {}
    for part in header.split(","):
        key, sep, value = part.strip().partition("=")
        if not sep or not key or not value or key in values:
            return None
        values[key] = value
    if len(values) != 2 or "t" not in values or "v1" not in values:
        return None
    return values


def _check(
    payload: Payload,
    header: Optional[str],
    secret: Optional[str],
    tolerance_seconds: float,
    now: Optional[float],
) -> Optional[str]:
    """Return ``None`` when valid, else the failure code. Same order of checks
    as the server: header shape, timestamp, freshness, digest."""
    if not secret or not secret.strip() or not header or tolerance_seconds < 0:
        return "invalid_signature"
    values = _parse_header(header)
    if values is None:
        return "invalid_signature"
    raw_timestamp = values["t"]
    if not _INT.match(raw_timestamp):
        return "invalid_signature"
    timestamp = int(raw_timestamp)
    current = time.time() if now is None else now
    if abs(current - timestamp) > tolerance_seconds:
        return "expired_signature"
    digest = values["v1"]
    if len(digest) != 64 or not set(digest) <= _HEX:
        return "invalid_signature"
    # The MAC covers the timestamp text exactly as it appears in the header.
    message = raw_timestamp.encode("utf-8") + b"." + _as_bytes(payload)
    expected = hmac.new(secret.encode("utf-8"), message, hashlib.sha256).hexdigest()
    if not hmac.compare_digest(expected, digest.lower()):
        return "invalid_signature"
    return None


def verify_signature(
    payload: Payload,
    header: Optional[str],
    secret: str,
    *,
    tolerance_seconds: float = DEFAULT_TOLERANCE_SECONDS,
    now: Optional[float] = None,
) -> bool:
    """Return ``True`` when ``header`` is a valid, fresh signature of the raw
    ``payload`` bytes for ``secret``. Verify before parsing the JSON."""
    return _check(payload, header, secret, tolerance_seconds, now) is None


def construct_event(
    payload: Payload,
    header: Optional[str],
    secret: str,
    *,
    tolerance_seconds: float = DEFAULT_TOLERANCE_SECONDS,
    now: Optional[float] = None,
) -> WebhookEvent:
    """Verify the signature, then parse the payload into a webhook event.

    Raises :class:`OpensmsError` with ``status == 0`` and ``code``
    ``"invalid_signature"`` or ``"expired_signature"`` on failure.
    """
    failure = _check(payload, header, secret, tolerance_seconds, now)
    if failure == "expired_signature":
        raise OpensmsError(
            0, "Webhook signature timestamp is outside the tolerance", code=failure
        )
    if failure is not None:
        raise OpensmsError(0, "Webhook signature is invalid", code=failure)
    try:
        event = json.loads(_as_bytes(payload).decode("utf-8"))
    except ValueError as exc:
        raise OpensmsError(0, "Webhook payload is not valid JSON", code="invalid_payload") from exc
    return event
