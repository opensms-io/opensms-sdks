"""The ``wallet`` resource."""

from __future__ import annotations

from typing import Any, List, Optional

from ..models import LedgerEntry, Topup, WalletBalance
from ._base import Resource


def _data(value: Any) -> List[Any]:
    if isinstance(value, dict):
        return list(value.get("data") or [])
    return value or []


class Wallet(Resource):
    """Balances, ledger and top-ups. Accessed as ``client.wallet``."""

    def balances(self) -> List[WalletBalance]:
        """Wallet balances (decimal strings) for the key's environment."""
        return _data(self._t.request("GET", "/v1/wallet"))

    def ledger(self, *, limit: Optional[int] = None, before: Optional[int] = None) -> List[LedgerEntry]:
        """Ledger entries, newest first. Not cursor based: pass the smallest
        ``id`` seen as ``before`` to page, and stop when fewer than ``limit``
        rows come back."""
        return _data(self._t.request("GET", "/v1/wallet/ledger", query={"limit": limit, "before": before}))

    def create_topup(
        self,
        *,
        amount: str,
        currency: str,
        channel: str,
        email: str,
        idempotency_key: Optional[str] = None,
    ) -> Topup:
        """Start a top-up (``channel`` ``card``, ``mobile_money`` or
        ``bank_transfer``). Live keys only. ``amount`` is a decimal string."""
        body = {"amount": str(amount), "currency": currency, "channel": channel, "email": email}
        return self._t.request(
            "POST", "/v1/wallet/topups", json_body=body, idempotent=True, idempotency_key=idempotency_key
        )
