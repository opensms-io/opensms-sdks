"""The ``numbers`` resource."""

from __future__ import annotations

from typing import List, Optional

from .._serialize import path_id, prune
from ..models import Number, NumberRule, Page
from ._base import Resource


def _rule_body(
    match: str, pattern: Optional[str], action: str, target: str, position: Optional[int]
) -> dict:
    return prune({"match": match, "pattern": pattern, "action": action, "target": target, "position": position})


class Numbers(Resource):
    """Virtual numbers and their inbound routing rules. Everything except
    :meth:`list` and :meth:`available` needs a live key. Accessed as
    ``client.numbers``."""

    def list(self, *, limit: Optional[int] = None, cursor: Optional[str] = None) -> Page[Number]:
        """List numbers assigned to the workspace."""
        return self._page(self._t.request("GET", "/v1/numbers", query={"limit": limit, "cursor": cursor}))

    def available(self, *, country: str, kind: str) -> List[Number]:
        """List numbers available to assign (``kind`` ``long_code``,
        ``short_code`` or ``toll_free``)."""
        return self._t.request("GET", "/v1/numbers/available", query={"country": country, "kind": kind})

    def assign(self, *, country: str, kind: str, idempotency_key: Optional[str] = None) -> Number:
        """Assign a number. Charges the wallet."""
        return self._t.request(
            "POST",
            "/v1/numbers",
            json_body={"country": country, "kind": kind},
            idempotent=True,
            idempotency_key=idempotency_key,
        )

    def release(self, id: str) -> None:
        """Release a number."""
        self._t.request("DELETE", f"/v1/numbers/{path_id(id)}")

    def list_rules(
        self, id: str, *, limit: Optional[int] = None, cursor: Optional[str] = None
    ) -> Page[NumberRule]:
        """List inbound rules for a number."""
        return self._page(
            self._t.request("GET", f"/v1/numbers/{path_id(id)}/rules", query={"limit": limit, "cursor": cursor})
        )

    def create_rule(
        self,
        id: str,
        *,
        match: str,
        action: str,
        target: str,
        pattern: Optional[str] = None,
        position: Optional[int] = None,
        idempotency_key: Optional[str] = None,
    ) -> NumberRule:
        """Add a rule. ``match`` is ``keyword``, ``prefix``, ``regex`` or
        ``any`` (``pattern`` required unless ``any``); ``action`` is
        ``webhook``, ``auto_reply`` or ``forward_email``."""
        return self._t.request(
            "POST",
            f"/v1/numbers/{path_id(id)}/rules",
            json_body=_rule_body(match, pattern, action, target, position),
            idempotent=True,
            idempotency_key=idempotency_key,
        )

    def update_rule(
        self,
        id: str,
        rule_id: str,
        *,
        match: str,
        action: str,
        target: str,
        pattern: Optional[str] = None,
        position: Optional[int] = None,
    ) -> NumberRule:
        """Replace a rule (PUT)."""
        return self._t.request(
            "PUT",
            f"/v1/numbers/{path_id(id)}/rules/{path_id(rule_id, 'rule_id')}",
            json_body=_rule_body(match, pattern, action, target, position),
        )

    def delete_rule(self, id: str, rule_id: str) -> None:
        """Delete a rule."""
        self._t.request("DELETE", f"/v1/numbers/{path_id(id)}/rules/{path_id(rule_id, 'rule_id')}")
