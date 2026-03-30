from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass
class FetchedDoc:
    """
    Raw document from any ingestion source before normalization.
    source_type: web | man | wiki | git
    """

    url: str
    title: str
    content: str
    source_type: str = "web"
    section: str = ""
    metadata: dict[str, Any] = field(default_factory=dict)

    def size_bytes(self) -> int:
        """Content size in bytes — useful for logging."""
        return len(self.content.encode("utf-8"))

    def to_dict(self) -> dict[str, Any]:
        return {
            "url": self.url,
            "title": self.title,
            "content": self.content,
            "source_type": self.source_type,
            "section": self.section,
            "metadata": self.metadata,
        }
