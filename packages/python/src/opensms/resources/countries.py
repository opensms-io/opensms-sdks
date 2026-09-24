"""The ``countries`` resource."""

from __future__ import annotations

from typing import Any, List

from .._serialize import path_id
from ..models import Carrier, Country, CountryRules
from ._base import Resource


class Countries(Resource):
    """Public country catalog. Accessed as ``client.countries``."""

    def list(self) -> List[Country]:
        """Every supported country."""
        return self._t.request("GET", "/v1/countries")

    def carriers(self, iso2: str) -> List[Carrier]:
        """Carriers in a country."""
        return self._t.request("GET", f"/v1/countries/{path_id(iso2, 'iso2')}/carriers")

    def routes(self, iso2: str) -> List[Any]:
        """Routes available for a country."""
        return self._t.request("GET", f"/v1/countries/{path_id(iso2, 'iso2')}/routes")

    def compliance(self, iso2: str) -> CountryRules:
        """Compliance rules for a country."""
        return self._t.request("GET", f"/v1/countries/{path_id(iso2, 'iso2')}/compliance")
