"""The ``otp`` resource."""

from __future__ import annotations

from typing import Optional

from .._serialize import prune
from ..models import OtpSendResult, OtpVerifyResult
from ._base import Resource


class Otp(Resource):
    """One-time passcodes. Accessed as ``client.otp``."""

    def send(
        self,
        *,
        to: str,
        sender_id: Optional[str] = None,
        template: Optional[str] = None,
        length: Optional[int] = None,
        ttl_seconds: Optional[int] = None,
        idempotency_key: Optional[str] = None,
    ) -> OtpSendResult:
        """Generate and send a code. ``template`` must contain ``{{code}}``."""
        body = prune(
            {
                "to": to,
                "sender_id": sender_id,
                "template": template,
                "length": length,
                "ttl_seconds": ttl_seconds,
            }
        )
        return self._t.request(
            "POST", "/v1/otp/send", json_body=body, idempotent=True, idempotency_key=idempotency_key
        )

    def verify(self, *, otp_id: str, code: str) -> OtpVerifyResult:
        """Check a code. A wrong code returns ``valid: False`` and uses up an
        attempt, so this call is never retried."""
        return self._t.request("POST", "/v1/otp/verify", json_body={"otp_id": otp_id, "code": code})
