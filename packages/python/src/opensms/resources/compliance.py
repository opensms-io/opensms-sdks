"""The ``compliance`` resource."""

from __future__ import annotations

from typing import List

from .._serialize import path_id
from ..models import ContentRule, CountryRules
from ._base import Resource


class Compliance(Resource):
    """Country rules and content rules. Accessed as ``client.compliance``."""

    def list_countries(self) -> List[CountryRules]:
        """Rules for every country."""
        return self._t.request("GET", "/v1/compliance/countries")

    def get_country(self, iso2: str) -> CountryRules:
        """Rules for one country (ISO 3166 alpha-2)."""
        return self._t.request("GET", f"/v1/compliance/countries/{path_id(iso2, 'iso2')}")

    def list_content_rules(self) -> List[ContentRule]:
        """Blocked keyword and regex rules applied to message text."""
        return self._t.request("GET", "/v1/content-rules")
