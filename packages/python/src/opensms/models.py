"""Response and input shapes.

Python names are snake_case, which is also the wire format, so responses are
returned as plain ``dict`` objects typed with the ``TypedDict`` definitions
below (every key optional, because live payloads omit empty fields). Money
and prices stay decimal **strings**; datetimes stay RFC 3339 strings; enums
are plain strings so a new server value never breaks decoding. Unknown keys
the server adds are passed through untouched.

The one wrapper type is :class:`Page`, returned by every cursor list method.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, Generic, Iterator, List, Optional, TypedDict, TypeVar

T = TypeVar("T")

JSONObject = Dict[str, Any]


@dataclass
class Page(Generic[T]):
    """One page of a cursor list. Pass :attr:`next_cursor` back as ``cursor``
    to fetch the next page; it is ``None`` on the last page."""

    items: List[T] = field(default_factory=list)
    next_cursor: Optional[str] = None

    def __iter__(self) -> Iterator[T]:
        return iter(self.items)

    def __len__(self) -> int:
        return len(self.items)

    @property
    def has_more(self) -> bool:
        return self.next_cursor is not None

    @classmethod
    def from_wire(cls, data: Any) -> "Page[Any]":
        if not isinstance(data, dict):
            return cls([], None)
        return cls(list(data.get("items") or []), data.get("next_cursor") or None)


class Message(TypedDict, total=False):
    id: str
    created_at: str
    to: str
    sender_id: str
    text: str
    parts: int
    status: str
    status_reason: str
    sent_at: str
    delivered_at: str
    failed_at: str
    cancelled_at: Optional[str]
    scheduled_at: str
    price: str
    currency: str
    traffic_type: str
    metadata: Optional[JSONObject]
    encoding: str
    country_id: Optional[str]
    country_iso2: Optional[str]
    country_name: Optional[str]
    carrier_id: Optional[str]
    carrier_name: Optional[str]
    destination_source: str
    billing: List[JSONObject]


class Attempt(TypedDict, total=False):
    id: int
    sequence: int
    route_id: str
    route_name: str
    price: Optional[str]
    currency: Optional[str]
    provider: str
    provider_message_id: str
    status: str
    error_code: str
    submitted_at: str
    dlr_at: str
    submit_latency_ms: int
    dlr_latency_ms: int


class BatchItemInput(TypedDict, total=False):
    to: str
    text: str
    sender_id: str
    traffic_type: str
    callback_url: str
    metadata: JSONObject


class Batch(TypedDict, total=False):
    id: str
    status: str
    total: int
    sent: int
    delivered: int
    failed: int
    invalid: int
    duplicates: int
    suppressed: int
    estimated_cost: Optional[float]
    created_at: str
    completed_at: str


class BatchValidationRow(TypedDict, total=False):
    row: int
    item: BatchItemInput
    valid: bool
    duplicate: bool
    suppressed: bool
    error: str


class BatchValidation(TypedDict, total=False):
    rows: List[BatchValidationRow]
    total: int
    valid: int
    invalid: int
    duplicates: int
    suppressed: int


class BatchStopResult(TypedDict, total=False):
    id: str
    status: str
    cancelled: int


class OtpSendResult(TypedDict, total=False):
    otp_id: str


class OtpVerifyResult(TypedDict, total=False):
    valid: bool
    attempts_left: int


class Lookup(TypedDict, total=False):
    id: str
    state: str
    country: str
    carrier: Optional[str]
    ported: Optional[bool]
    valid: Optional[bool]
    source: Optional[str]
    price: str
    currency: str
    checked_at: Optional[str]


class Contact(TypedDict, total=False):
    id: str
    workspace_id: str
    e164: str
    name: Optional[str]
    attributes: JSONObject
    created_at: str


class ContactGroup(TypedDict, total=False):
    id: str
    workspace_id: str
    name: str
    contact_ids: List[str]
    created_at: str


class Template(TypedDict, total=False):
    id: str
    workspace_id: str
    name: str
    body: str
    traffic_type: str
    created_at: str
    updated_at: str
    variables: List[str]


class WebhookEndpoint(TypedDict, total=False):
    id: str
    url: str
    events: List[str]
    enabled: bool
    consecutive_failures: int
    disabled_at: str
    created_at: str
    secret: str


class WebhookDelivery(TypedDict, total=False):
    id: int
    generation: int
    event: str
    payload: Any
    attempts: int
    next_retry_at: str
    status: str
    last_response_code: int
    last_error: str
    created_at: str
    delivered_at: str


class StatusResult(TypedDict, total=False):
    status: str


class WebhookEvent(TypedDict, total=False):
    id: str
    type: str
    workspace_id: str
    environment: str
    created_at: str
    data: JSONObject


# ``from`` is a Python keyword, so this shape uses the functional syntax.
InboundMessage = TypedDict(
    "InboundMessage",
    {
        "id": str,
        "from": str,
        "to": str,
        "text": str,
        "received_at": str,
        "virtual_number_id": str,
    },
    total=False,
)


class Number(TypedDict, total=False):
    id: str
    country: str
    number: str
    kind: str
    monthly_fee: str
    fee_currency: str
    status: str
    inbound: bool
    outbound: bool
    assigned_at: str
    renews_at: str


class NumberRule(TypedDict, total=False):
    id: str
    match: str
    pattern: str
    action: str
    target: str
    position: int


class SenderId(TypedDict, total=False):
    id: str
    value: str
    kind: str
    countries: List[str]
    use_case: str
    sample_message: str
    status: str
    rejection_reason: str
    restricted: bool
    restriction_reason: str
    created_at: str
    registrations: List[JSONObject]


class SenderIdCheck(TypedDict, total=False):
    valid: bool
    available: bool
    reserved: bool
    reason: str


class SenderIdQuote(TypedDict, total=False):
    quote_id: str
    entries: List[JSONObject]
    totals: List[JSONObject]


class SenderIdDraft(TypedDict, total=False):
    id: str
    source: str
    value: str
    kind: str
    countries: List[str]
    use_case: str
    sample_message: str
    documents: List[str]
    version: int
    status: str
    submitted_sender_id: Optional[str]
    created_at: str
    updated_at: str


class SenderDocument(TypedDict, total=False):
    id: str
    kind: str
    filename: str
    content_type: str
    size: int
    scan_status: str
    review_status: str
    review_reason: str
    reviewed_at: str
    version: int
    supersedes_id: str
    is_current: bool
    created_at: str


class Suppression(TypedDict, total=False):
    id: int
    e164: str
    reason: str
    created_at: str


class SuppressionInput(TypedDict, total=False):
    e164: str
    reason: str


class SuppressionImportResult(TypedDict, total=False):
    created: int
    received: int


class CountryRules(TypedDict, total=False):
    iso2: str
    name: str
    status: str
    dial_code: str
    stop_keywords: List[str]
    quiet_hours: List[JSONObject]
    content_rules: List[JSONObject]


class ContentRule(TypedDict, total=False):
    id: int
    country_iso2: Optional[str]
    kind: str
    pattern: str
    action: str
    traffic_types: List[str]
    enabled: bool


class WalletBalance(TypedDict, total=False):
    id: str
    currency: str
    balance: str
    reserved: str
    environment: str


class LedgerEntry(TypedDict, total=False):
    id: int
    wallet_id: str
    type: str
    amount: str
    balance_after: str
    reserved_delta: str
    reserved_after: str
    reference: str
    payment_id: str
    message_id: str
    created_at: str


class Topup(TypedDict, total=False):
    id: str
    reference: str
    authorization_url: str
    access_code: str
    amount: str
    currency: str
    status: str


class PriceList(TypedDict, total=False):
    workspace_id: str
    currency: str
    product: str
    entries: List[JSONObject]


AnalyticsMetrics = TypedDict(
    "AnalyticsMetrics",
    {
        "sent": int,
        "delivered": int,
        "failed": int,
        "parts": int,
        "delivery_rate": float,
        "spend": str,
        "p50_ms": float,
        "p95_ms": float,
        "from": str,
        "to": str,
        "currency": str,
        "environment": str,
        "key": str,
        "name": str,
        "bucket": str,
    },
    total=False,
)


class SandboxMessage(TypedDict, total=False):
    id: str
    to: str
    sender_id: str
    text: str
    parts: int
    status: str
    traffic_type: str
    created_at: str
    sent_at: str


class Country(TypedDict, total=False):
    iso2: str
    name: str
    dial_code: str
    currency: str
    status: str
    price_per_message: Optional[JSONObject]
    sender_kinds: List[str]
    providers_available: int


class Carrier(TypedDict, total=False):
    id: str
    name: str
    mcc_mnc: List[str]
    prefixes: List[str]
