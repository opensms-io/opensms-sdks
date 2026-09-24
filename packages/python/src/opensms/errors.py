"""Error type raised by the SDK."""

from __future__ import annotations

from typing import Any, Dict, List, Optional


class OpensmsError(Exception):
    """Raised for every non-2xx API response, for transport failures that
    survive all retries, and for webhook signature failures.

    The fields mirror the API's RFC 9457 problem+json body. Most API errors
    carry no ``code``, so branch on :attr:`status` first and use
    :attr:`detail` for display. Insufficient scope is ``401`` on messages and
    OTP but ``403`` everywhere else.
    """

    def __init__(
        self,
        status: int,
        message: str,
        *,
        type: Optional[str] = None,
        title: Optional[str] = None,
        detail: Optional[str] = None,
        code: Optional[str] = None,
        trace_id: Optional[str] = None,
        errors: Optional[Dict[str, List[str]]] = None,
        request_id: Optional[str] = None,
        retry_after: Optional[float] = None,
        body: Any = None,
    ) -> None:
        super().__init__(message)
        #: HTTP status code. ``0`` means no response (network error, timeout,
        #: or a webhook signature failure).
        self.status = status
        #: Human readable message: ``detail``, else ``title``, else a generic text.
        self.message = message
        #: Problem ``type`` URI, usually ``about:blank``.
        self.type = type
        #: Problem ``title`` such as ``Bad Request``.
        self.title = title
        #: Problem ``detail``, the specific human readable reason.
        self.detail = detail
        #: Machine readable ``code`` when the handler sets one (most do not).
        self.code = code
        #: Problem ``trace_id``, when present.
        self.trace_id = trace_id
        #: Field validation errors, ``{field: [messages]}``, when present.
        self.errors = errors
        #: ``X-Request-ID`` response header (message and OTP admission rejections).
        self.request_id = request_id
        #: ``Retry-After`` in seconds, when the server sent it.
        self.retry_after = retry_after
        #: Raw decoded body (dict) or raw text when the body was not JSON.
        self.body = body

    def __repr__(self) -> str:
        return (
            f"OpensmsError(status={self.status!r}, message={self.message!r}, "
            f"code={self.code!r})"
        )
