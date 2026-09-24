"""The ``analytics`` resource."""

from __future__ import annotations

from datetime import date, datetime
from typing import Any, Dict, List, Optional, Union

from ..models import AnalyticsMetrics
from ._base import Resource

DateLike = Union[str, date, datetime]


def _query(
    currency: Optional[str],
    range: Optional[str],
    from_: Optional[DateLike],
    to: Optional[DateLike],
    bucket: Optional[str],
) -> Dict[str, Any]:
    return {"currency": currency, "range": range, "from": from_, "to": to, "bucket": bucket}


class Analytics(Resource):
    """Delivery and spend metrics. Accessed as ``client.analytics``.

    Every method takes ``currency``, ``range`` (``"7d"``, 1..366 days,
    default 30d) **or** ``from_``/``to`` (datetime, date or string), and
    ``bucket`` (``day`` or ``hour``).
    """

    def overview(
        self,
        *,
        currency: Optional[str] = None,
        range: Optional[str] = None,
        from_: Optional[DateLike] = None,
        to: Optional[DateLike] = None,
        bucket: Optional[str] = None,
    ) -> AnalyticsMetrics:
        """Totals for the period."""
        q = _query(currency, range, from_, to, bucket)
        return self._t.request("GET", "/v1/analytics/overview", query=q)

    def by_country(
        self,
        *,
        currency: Optional[str] = None,
        range: Optional[str] = None,
        from_: Optional[DateLike] = None,
        to: Optional[DateLike] = None,
        bucket: Optional[str] = None,
    ) -> List[AnalyticsMetrics]:
        """Metrics per destination country."""
        q = _query(currency, range, from_, to, bucket)
        return self._t.request("GET", "/v1/analytics/by-country", query=q)

    def by_carrier(
        self,
        *,
        currency: Optional[str] = None,
        range: Optional[str] = None,
        from_: Optional[DateLike] = None,
        to: Optional[DateLike] = None,
        bucket: Optional[str] = None,
    ) -> List[AnalyticsMetrics]:
        """Metrics per carrier."""
        q = _query(currency, range, from_, to, bucket)
        return self._t.request("GET", "/v1/analytics/by-carrier", query=q)

    def by_sender_id(
        self,
        *,
        currency: Optional[str] = None,
        range: Optional[str] = None,
        from_: Optional[DateLike] = None,
        to: Optional[DateLike] = None,
        bucket: Optional[str] = None,
    ) -> List[AnalyticsMetrics]:
        """Metrics per sender ID."""
        q = _query(currency, range, from_, to, bucket)
        return self._t.request("GET", "/v1/analytics/by-sender-id", query=q)

    def timeseries(
        self,
        *,
        currency: Optional[str] = None,
        range: Optional[str] = None,
        from_: Optional[DateLike] = None,
        to: Optional[DateLike] = None,
        bucket: Optional[str] = None,
    ) -> List[AnalyticsMetrics]:
        """Metrics per time bucket."""
        q = _query(currency, range, from_, to, bucket)
        return self._t.request("GET", "/v1/analytics/timeseries", query=q)
