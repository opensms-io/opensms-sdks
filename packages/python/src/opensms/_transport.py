"""HTTP transport: the only code that touches the network.

Owns authentication headers, JSON encoding, the Idempotency-Key, timeouts,
retries with backoff, and turning non-2xx responses into
:class:`~opensms.errors.OpensmsError`. The default network layer uses only the
standard library (``urllib``); tests inject a transport callable instead.
"""

from __future__ import annotations

import email.utils
import http.client
import json
import random
import socket
import time
import urllib.error
import urllib.request
import uuid
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, Mapping, Optional

from ._serialize import build_query
from ._version import __version__
from .errors import OpensmsError

DEFAULT_BASE_URL = "https://opensms.io"
USER_AGENT = f"opensms-python/{__version__}"

#: Statuses that may be retried (when the request is safe to repeat).
RETRYABLE_STATUSES = frozenset({429, 500, 502, 503, 504})
#: A ``Retry-After`` above this many seconds is not waited for.
MAX_RETRY_AFTER = 60.0
_BACKOFF_BASE = 0.5
_BACKOFF_CAP = 8.0


@dataclass
class TransportRequest:
    """One HTTP attempt handed to a transport callable."""

    method: str
    url: str
    headers: Dict[str, str]
    body: Optional[bytes]
    timeout: float


@dataclass
class TransportResponse:
    """What a transport callable returns for any HTTP status (including
    4xx and 5xx). Header names are matched case-insensitively."""

    status: int
    headers: Mapping[str, str] = field(default_factory=dict)
    body: bytes = b""

    def header(self, name: str) -> Optional[str]:
        lower = name.lower()
        for key, value in self.headers.items():
            if key.lower() == lower:
                return value
        return None


#: A transport performs one HTTP attempt. It returns a response for every
#: status and raises (any ``OSError``, ``http.client.HTTPException`` or
#: ``TimeoutError``) only when no response was received.
Transport = Callable[[TransportRequest], TransportResponse]

_NETWORK_ERRORS = (OSError, http.client.HTTPException, TimeoutError, socket.timeout)


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args: Any, **kwargs: Any) -> None:  # type: ignore[override]
        return None


_opener = urllib.request.build_opener(_NoRedirect)


def urllib_transport(request: TransportRequest) -> TransportResponse:
    """Default transport built on ``urllib.request``."""
    req = urllib.request.Request(
        request.url, data=request.body, method=request.method, headers=request.headers
    )
    try:
        with _opener.open(req, timeout=request.timeout) as resp:
            return TransportResponse(resp.status, dict(resp.headers.items()), resp.read())
    except urllib.error.HTTPError as err:
        try:
            body = err.read()
        finally:
            err.close()
        headers = dict(err.headers.items()) if err.headers else {}
        return TransportResponse(err.code, headers, body)


def parse_retry_after(value: Optional[str], now: Optional[float] = None) -> Optional[float]:
    """Parse ``Retry-After`` as integer seconds or an HTTP date."""
    if value is None:
        return None
    value = value.strip()
    if not value:
        return None
    try:
        return max(0.0, float(int(value)))
    except ValueError:
        pass
    try:
        when = email.utils.parsedate_to_datetime(value)
    except (TypeError, ValueError, IndexError):
        return None
    if when is None:
        return None
    current = time.time() if now is None else now
    return max(0.0, when.timestamp() - current)


def error_from_response(resp: TransportResponse) -> OpensmsError:
    """Map a non-2xx response (problem+json or anything else) to an error."""
    text = resp.body.decode("utf-8", "replace") if resp.body else ""
    payload: Any = None
    if text:
        try:
            payload = json.loads(text)
        except ValueError:
            payload = None
    retry_after = parse_retry_after(resp.header("Retry-After"))
    request_id = resp.header("X-Request-ID") or None
    if isinstance(payload, dict):
        detail = payload.get("detail") if isinstance(payload.get("detail"), str) else None
        title = payload.get("title") if isinstance(payload.get("title"), str) else None
        message = detail or title or f"OpenSMS request failed with status {resp.status}"
        errors = payload.get("errors") if isinstance(payload.get("errors"), dict) else None
        return OpensmsError(
            resp.status,
            message,
            type=payload.get("type"),
            title=title,
            detail=detail,
            code=payload.get("code"),
            trace_id=payload.get("trace_id"),
            errors=errors,
            request_id=request_id,
            retry_after=retry_after,
            body=payload,
        )
    return OpensmsError(
        resp.status,
        f"OpenSMS request failed with status {resp.status}",
        request_id=request_id,
        retry_after=retry_after,
        body=payload if payload is not None else text,
    )


class HttpTransport:
    """Performs authenticated requests with retries. Shared by all resources."""

    def __init__(
        self,
        api_key: str,
        *,
        base_url: Optional[str] = None,
        timeout: float = 30.0,
        max_retries: int = 2,
        transport: Optional[Transport] = None,
        sleep: Optional[Callable[[float], None]] = None,
    ) -> None:
        if max_retries < 0:
            raise ValueError("max_retries must be >= 0")
        self._api_key = api_key
        self.base_url = (base_url or DEFAULT_BASE_URL).rstrip("/")
        self.timeout = timeout
        self.max_retries = max_retries
        self._transport: Transport = transport or urllib_transport
        self._sleep: Callable[[float], None] = sleep or time.sleep

    def request(
        self,
        method: str,
        path: str,
        *,
        query: Optional[Mapping[str, Any]] = None,
        json_body: Any = None,
        raw_body: Optional[bytes] = None,
        content_type: Optional[str] = None,
        idempotent: bool = False,
        idempotency_key: Optional[str] = None,
    ) -> Any:
        """Send one API call and return the decoded JSON (``None`` for 204).

        ``idempotent=True`` marks a method that supports Idempotency-Key: the
        caller's key (or a fresh UUIDv4) is sent on every attempt of this call.
        """
        url = f"{self.base_url}{path}{build_query(query)}"
        headers = {
            "Authorization": f"Bearer {self._api_key}",
            "Accept": "application/json",
            "User-Agent": USER_AGENT,
        }
        body: Optional[bytes] = None
        if raw_body is not None:
            body = raw_body
            headers["Content-Type"] = content_type or "application/octet-stream"
        elif json_body is not None:
            body = json.dumps(json_body, separators=(",", ":")).encode("utf-8")
            headers["Content-Type"] = "application/json"
        if idempotent or idempotency_key is not None:
            headers["Idempotency-Key"] = idempotency_key or str(uuid.uuid4())

        method = method.upper()
        can_retry = method in ("GET", "PUT", "PATCH", "DELETE", "HEAD") or (
            method == "POST" and "Idempotency-Key" in headers
        )

        attempt = 0
        while True:
            attempt += 1
            req = TransportRequest(method, url, dict(headers), body, self.timeout)
            try:
                resp = self._transport(req)
            except OpensmsError:
                raise
            except _NETWORK_ERRORS as exc:
                if can_retry and attempt <= self.max_retries:
                    self._sleep(self._backoff(attempt))
                    continue
                raise OpensmsError(0, f"OpenSMS request failed: {exc}") from exc

            if 200 <= resp.status < 300:
                return self._decode(resp)

            error = error_from_response(resp)
            if not (can_retry and resp.status in RETRYABLE_STATUSES and attempt <= self.max_retries):
                raise error
            if error.retry_after is not None:
                if error.retry_after > MAX_RETRY_AFTER:
                    raise error
                delay = error.retry_after
            else:
                delay = self._backoff(attempt)
            self._sleep(delay)

    @staticmethod
    def _backoff(retry_number: int) -> float:
        """Exponential backoff with full jitter for retry ``n`` (1-based)."""
        ceiling = min(_BACKOFF_CAP, _BACKOFF_BASE * (2 ** (retry_number - 1)))
        return random.uniform(0.0, ceiling)

    @staticmethod
    def _decode(resp: TransportResponse) -> Any:
        if resp.status == 204 or not resp.body:
            return None
        text = resp.body.decode("utf-8")
        try:
            return json.loads(text)
        except ValueError:
            return text
