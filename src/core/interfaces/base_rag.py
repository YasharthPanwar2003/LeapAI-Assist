from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass
class Document:
    """A single ingested document. Mirrors Anuj's ScrapedPage."""

    id: str
    title: str
    content: str
    source: str  # URL or file path
    metadata: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        """Serialize to dict for saving to JSON on disk."""
        return {
            "id": self.id,
            "title": self.title,
            "content": self.content,
            "source": self.source,
            "metadata": self.metadata,
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> Document:
        """Restore a Document from a saved dict."""
        return cls(
            id=data["id"],
            title=data["title"],
            content=data["content"],
            source=data["source"],
            metadata=data.get("metadata", {}),
        )


@dataclass
class RetrievedChunk:
    """A chunk returned after RAG retrieval. Both backends return this shape."""

    text: str
    source: str
    score: float = 1.0  # overlap score or cosine similarity
    metadata: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return {
            "text": self.text,
            "source": self.source,
            "score": self.score,
            "metadata": self.metadata,
        }
