"""The OpenSMS client: validates the key and wires the transport into every
resource."""

from __future__ import annotations

from typing import Any, Callable, Iterator, Optional, TypeVar

from ._transport import DEFAULT_BASE_URL, HttpTransport, Transport
from .models import Page
from .pagination import paginate
from .resources.analytics import Analytics
from .resources.batches import Batches
from .resources.compliance import Compliance
from .resources.contact_groups import ContactGroups
from .resources.contacts import Contacts
from .resources.countries import Countries
from .resources.inbound import Inbound
from .resources.lookups import Lookups
from .resources.messages import Messages
from .resources.numbers import Numbers
from .resources.otp import Otp
from .resources.pricing import Pricing
from .resources.sandbox import Sandbox
from .resources.sender_ids import SenderIds
from .resources.suppressions import Suppressions
from .resources.templates import Templates
from .resources.wallet import Wallet
from .resources.webhooks import Webhooks

T = TypeVar("T")

_PREFIXES = {"sk_test_": "sandbox", "sk_live_": "live"}


def _environment_for(api_key: Any) -> str:
    """Mirror the server's ``auth.ValidSecret``: a known prefix and more than
    12 characters after it."""
    if not isinstance(api_key, str) or not api_key:
        raise ValueError("api_key is required")
    for prefix, environment in _PREFIXES.items():
        if api_key.startswith(prefix):
            if len(api_key) - len(prefix) > 12:
                return environment
            break
    raise ValueError("api_key must be an OpenSMS secret key (sk_test_... or sk_live_...)")


class Opensms:
    """OpenSMS API client.

    Example::

        from opensms import Opensms

        client = Opensms(api_key="sk_test_...")
        message = client.messages.send(to="+254700000012", text="Hello")
        print(message["id"], message["status"])

    Args:
        api_key: ``sk_test_...`` (sandbox) or ``sk_live_...`` (live). Checked
            locally; a malformed key raises ``ValueError`` with no request.
        base_url: API origin, default ``https://opensms.io``.
        timeout: Seconds per attempt (connect and read), default 30.
        max_retries: Retries after the first attempt, default 2. ``0``
            disables retries.
        transport: Optional callable performing one HTTP attempt (see
            :data:`opensms.Transport`); defaults to the ``urllib`` transport.
        sleep: Optional replacement for ``time.sleep`` between retries.
    """

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
        self._environment = _environment_for(api_key)
        self._http = HttpTransport(
            api_key,
            base_url=base_url or DEFAULT_BASE_URL,
            timeout=timeout,
            max_retries=max_retries,
            transport=transport,
            sleep=sleep,
        )
        self.messages = Messages(self._http)
        self.batches = Batches(self._http)
        self.otp = Otp(self._http)
        self.lookups = Lookups(self._http)
        self.contacts = Contacts(self._http)
        self.contact_groups = ContactGroups(self._http)
        self.templates = Templates(self._http)
        self.webhooks = Webhooks(self._http)
        self.inbound = Inbound(self._http)
        self.numbers = Numbers(self._http)
        self.sender_ids = SenderIds(self._http)
        self.suppressions = Suppressions(self._http)
        self.compliance = Compliance(self._http)
        self.wallet = Wallet(self._http)
        self.pricing = Pricing(self._http)
        self.analytics = Analytics(self._http)
        self.sandbox = Sandbox(self._http)
        self.countries = Countries(self._http)

    @property
    def environment(self) -> str:
        """``"sandbox"`` for ``sk_test_`` keys, ``"live"`` for ``sk_live_``."""
        return self._environment

    @property
    def base_url(self) -> str:
        return self._http.base_url

    def paginate(self, list_method: Callable[..., "Page[T]"], *args: Any, **params: Any) -> Iterator[T]:
        """Iterate every item of a cursor list lazily::

            for message in client.paginate(client.messages.list, limit=50):
                ...
        """
        return paginate(list_method, *args, **params)

    def __repr__(self) -> str:
        return f"Opensms(environment={self._environment!r}, base_url={self._http.base_url!r})"
