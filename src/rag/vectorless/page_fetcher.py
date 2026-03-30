from __future__ import annotations

from src.logger.logger import get_logger
from src.rag.vectorless.tree_builder import TreeNode

logger = get_logger(__name__)


class PageFetcher:
    """
    Fetches text for a list of nodes from the in-memory tree.
    No disk I/O — text is already in TreeNode.text.
    """

    def fetch(self, nodes: list[TreeNode], doc_title: str = "") -> str:
        """Join text from all nodes with a separator."""
        if not nodes:
            return ""
        parts = [node.text for node in nodes if node.text.strip()]
        text = "\n\n---\n\n".join(parts)
        logger.debug("Fetched %d chars from %d nodes (%s)", len(text), len(parts), doc_title)
        return text

    def fetch_with_refs(self, nodes: list[TreeNode], doc_title: str) -> list[dict]:
        """
        Return list of {text, source_ref} dicts.
        Useful for citation in the final answer.
        """
        results = []
        for node in nodes:
            if not node.text.strip():
                continue
            results.append(
                {
                    "text": node.text,
                    "source_ref": f"{doc_title} › {node.title}",
                    "node_id": node.node_id,
                }
            )
        return results
