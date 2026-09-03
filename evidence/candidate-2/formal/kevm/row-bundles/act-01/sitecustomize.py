"""Emit request lifecycle records before and after current-profile symbolic RPC calls.

This module is loaded only when its directory is explicitly prepended to
``PYTHONPATH``.  It does not alter proof terms or backend options.  The output
path is supplied through ``M4_RPC_LIFECYCLE_LOG`` and is diagnostic-only.
"""

from __future__ import annotations

import json
import os
from hashlib import sha256
from datetime import datetime, timezone
from pathlib import Path
from threading import Lock

try:
    from pyk.cterm.symbolic import CTermSymbolic
    from pyk.kore.rpc import Transport
except ModuleNotFoundError:
    # The runner also invokes the host Python for graph-count sampling. That
    # interpreter intentionally has no pyk installation; loading this module
    # there must be a silent no-op rather than a misleading startup warning.
    CTermSymbolic = None  # type: ignore[assignment,misc]
    Transport = None  # type: ignore[assignment,misc]


_LOG_ENV = "M4_RPC_LIFECYCLE_LOG"
_PATCH_MARKER = "_m4_request_lifecycle_patched"
_TRANSPORT_PATCH_MARKER = "_m4_transport_lifecycle_patched"
_WRITE_LOCK = Lock()


def _record(event: str, method: str, **details: object) -> None:
    target = os.environ.get(_LOG_ENV)
    if not target:
        return
    payload = {
        "event": event,
        "method": method,
        "timestampUtc": datetime.now(timezone.utc).isoformat(),
        "pid": os.getpid(),
        **details,
    }
    path = Path(target)
    path.parent.mkdir(parents=True, exist_ok=True)
    with _WRITE_LOCK, path.open("a", encoding="utf-8") as stream:
        stream.write(json.dumps(payload, sort_keys=True) + "\n")
        stream.flush()
        os.fsync(stream.fileno())


def _wrap(method: str) -> None:
    original = getattr(CTermSymbolic, method)

    def traced(self: CTermSymbolic, *args: object, **kwargs: object) -> object:
        _record("request-start", method)
        try:
            result = original(self, *args, **kwargs)
        except BaseException as error:
            _record("request-error", method, errorType=type(error).__name__)
            raise
        _record("response-end", method)
        return result

    setattr(CTermSymbolic, method, traced)


def _wrap_transport() -> None:
    original = Transport.request

    def traced(
        self: Transport,
        request: str,
        request_id: str,
        method_name: str,
    ) -> str:
        request_bytes = request.encode()
        request_sha256 = sha256(request_bytes).hexdigest()
        _record(
            "client-pre-send",
            method_name,
            requestId=request_id,
            requestSha256=request_sha256,
            requestBytes=len(request_bytes),
        )
        try:
            response = original(self, request, request_id, method_name)
        except BaseException as error:
            _record(
                "client-transport-error",
                method_name,
                requestId=request_id,
                requestSha256=request_sha256,
                errorType=type(error).__name__,
            )
            raise
        response_bytes = response.encode()
        _record(
            "client-response",
            method_name,
            requestId=request_id,
            requestSha256=request_sha256,
            responseSha256=sha256(response_bytes).hexdigest(),
            responseBytes=len(response_bytes),
        )
        return response

    Transport.request = traced


if CTermSymbolic is not None and Transport is not None:
    if not getattr(CTermSymbolic, _PATCH_MARKER, False):
        for _method in ("simplify", "implies", "execute"):
            _wrap(_method)
        setattr(CTermSymbolic, _PATCH_MARKER, True)

    if not getattr(Transport, _TRANSPORT_PATCH_MARKER, False):
        _wrap_transport()
        setattr(Transport, _TRANSPORT_PATCH_MARKER, True)

    _record("instrumentation-ready", "sitecustomize")
