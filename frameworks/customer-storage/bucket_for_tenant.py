"""Canonical bucket_for_tenant — keep in sync with bucket-for-tenant.ts.

See README + ADR-004 in the WAVE control plane.
"""

from __future__ import annotations

import hashlib
import os

_POOL_PREFIX = "wave-customer-storage-pool-"
_DEFAULT_POOL_SIZE = 10


def _pool_size() -> int:
    raw = os.environ.get("WAVE_STORAGE_POOL_SIZE")
    if raw is None:
        return _DEFAULT_POOL_SIZE
    try:
        n = int(raw)
        return n if n > 0 else _DEFAULT_POOL_SIZE
    except ValueError:
        return _DEFAULT_POOL_SIZE


def bucket_for_tenant(tenant_id: str) -> str:
    """Return wave-customer-storage-pool-N where N = SHA-256(tenant_id) % pool_size.

    Same as TS bucketForTenant — must produce identical output.
    """
    if not tenant_id:
        raise ValueError("bucket_for_tenant: tenant_id required")
    digest = hashlib.sha256(tenant_id.encode("utf-8")).digest()
    index = int.from_bytes(digest[:4], byteorder="big") % _pool_size()
    return f"{_POOL_PREFIX}{index}"


def all_bucket_names() -> list[str]:
    n = _pool_size()
    return [f"{_POOL_PREFIX}{i}" for i in range(n)]
