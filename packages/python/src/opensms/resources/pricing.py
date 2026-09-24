"""The ``pricing`` resource."""

from __future__ import annotations

from typing import Optional

from ..models import PriceList
from ._base import Resource


class Pricing(Resource):
    """Workspace price list. Accessed as ``client.pricing``."""

    def get(self, *, product: Optional[str] = None, country: Optional[str] = None) -> PriceList:
        """Prices for ``product`` (``sms``, ``lookup`` or ``number_monthly``),
        optionally for one ``country``."""
        return self._t.request("GET", "/v1/pricing", query={"product": product, "country": country})
