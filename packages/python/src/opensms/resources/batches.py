"""The ``batches`` resource."""

from __future__ import annotations

import uuid
from typing import Any, Dict, List, Mapping, Optional, Union

from .._serialize import path_id, prune
from ..models import Batch, BatchStopResult, BatchValidation, Message, Page
from ._base import Resource


class Batches(Resource):
    """Bulk sends. Accessed as ``client.batches``."""

    def create(
        self,
        *,
        items: List[Mapping[str, Any]],
        dedupe: Optional[bool] = None,
        idempotency_key: Optional[str] = None,
    ) -> Batch:
        """Create a batch in ``ready`` state (nothing is sent until
        :meth:`start`). Each item takes ``to``, ``text`` and optionally
        ``sender_id``, ``traffic_type``, ``callback_url``, ``metadata``.
        Invalid rows are counted in ``invalid``, not rejected."""
        body: Dict[str, Any] = {"items": [prune(dict(item)) for item in items]}
        if dedupe is not None:
            body["dedupe"] = dedupe
        return self._t.request(
            "POST",
            "/v1/messages/batch",
            json_body=body,
            idempotent=True,
            idempotency_key=idempotency_key,
        )

    def create_from_csv(
        self,
        csv: Union[str, bytes],
        *,
        dedupe: Optional[bool] = None,
        idempotency_key: Optional[str] = None,
    ) -> Batch:
        """Create a batch from CSV text (header row ``to,text[,sender_id,...]``),
        posted as ``text/csv``.

        The API reads ``dedupe`` only from a multipart upload, so when
        ``dedupe`` is given the CSV is sent as a ``multipart/form-data`` file
        with a ``dedupe`` field instead.
        """
        data = csv.encode("utf-8") if isinstance(csv, str) else bytes(csv)
        if dedupe is None:
            return self._t.request(
                "POST",
                "/v1/messages/batch",
                raw_body=data,
                content_type="text/csv",
                idempotent=True,
                idempotency_key=idempotency_key,
            )
        boundary = "opensms" + uuid.uuid4().hex
        body = (
            f"--{boundary}\r\n"
            'Content-Disposition: form-data; name="dedupe"\r\n\r\n'
            f"{'true' if dedupe else 'false'}\r\n"
            f"--{boundary}\r\n"
            'Content-Disposition: form-data; name="file"; filename="batch.csv"\r\n'
            "Content-Type: text/csv\r\n\r\n"
        ).encode("utf-8") + data + f"\r\n--{boundary}--\r\n".encode("utf-8")
        return self._t.request(
            "POST",
            "/v1/messages/batch",
            raw_body=body,
            content_type=f"multipart/form-data; boundary={boundary}",
            idempotent=True,
            idempotency_key=idempotency_key,
        )

    def get(self, id: str) -> Batch:
        """Fetch a batch and its counters."""
        return self._t.request("GET", f"/v1/batches/{path_id(id)}")

    def validation(self, id: str) -> BatchValidation:
        """Per-row validation report for a batch."""
        return self._t.request("GET", f"/v1/batches/{path_id(id)}/validation")

    def start(self, id: str, *, idempotency_key: Optional[str] = None) -> Batch:
        """Start sending a ``ready`` batch."""
        return self._t.request(
            "POST",
            f"/v1/batches/{path_id(id)}/start",
            idempotent=True,
            idempotency_key=idempotency_key,
        )

    def stop(self, id: str, *, idempotency_key: Optional[str] = None) -> BatchStopResult:
        """Stop a batch; unsent items are cancelled."""
        return self._t.request(
            "POST",
            f"/v1/batches/{path_id(id)}/stop",
            idempotent=True,
            idempotency_key=idempotency_key,
        )

    def list_items(
        self,
        id: str,
        *,
        status: Optional[str] = None,
        limit: Optional[int] = None,
        cursor: Optional[str] = None,
    ) -> Page[Message]:
        """List the messages a batch produced (slimmer than a full Message)."""
        query = {"status": status, "limit": limit, "cursor": cursor}
        return self._page(self._t.request("GET", f"/v1/batches/{path_id(id)}/items", query=query))
