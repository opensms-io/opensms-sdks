"""Official Python client for OpenSMS, the prepaid SMS API.

    from opensms import Opensms

    client = Opensms(api_key="sk_test_...")
    client.messages.send(to="+254700000012", text="Your order has shipped")
"""

from ._transport import Transport, TransportRequest, TransportResponse, urllib_transport
from ._version import __version__
from .client import Opensms
from .errors import OpensmsError
from .models import Page
from .pagination import paginate
from .signature import SIGNATURE_HEADER, construct_event, verify_signature

__all__ = [
    "Opensms",
    "OpensmsError",
    "Page",
    "paginate",
    "verify_signature",
    "construct_event",
    "SIGNATURE_HEADER",
    "Transport",
    "TransportRequest",
    "TransportResponse",
    "urllib_transport",
    "__version__",
]
