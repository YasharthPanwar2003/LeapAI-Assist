from __future__ import annotations

from pathlib import Path
from typing import Any

from src.core.interfaces.base_rag import Document, RetrievedChunk
from src.logger.logger import get_logger
from src.rag.vectorless.page_fetcher import PageFetcher
from src.rag.vectorless.tree_builder import DocTree, TreeBuilder
from src.rag.vectorless.tree_searcher import TreeSearcher

logger = get_logger(__name__)


class VectorlessRAG:
    """
    PageIndex vectorless RAG.

    ingest()   — build JSON tree per doc (one-time ~10-20 LLM calls each)
    retrieve() — LLM picks relevant nodes → return their text
    reset()    — clear in-memory trees

    """

    def __init__(self, index_dir: Path, llm: Any) -> None:
        self.index_dir = index_dir
        self.trees: dict[str, DocTree] = {}  # doc_id → DocTree

        self.builder = TreeBuilder(llm)
        self.searcher = TreeSearcher(llm)
        self.fetcher = PageFetcher()

    def ingest(self, docs: list[Document]) -> None:
        """Build and save a JSON tree for each document."""
        self.index_dir.mkdir(parents=True, exist_ok=True)
        trees = self.builder.build_all(docs, self.index_dir)
        for tree in trees:
            self.trees[tree.doc_id] = tree
        logger.info("Ingested %d docs — %d trees in memory", len(docs), len(self.trees))

    def retrieve(self, query: str, top_k: int = 3) -> list[RetrievedChunk]:
        """
        Search all trees, return up to top_k chunks.
        Each doc contributes at most 1 chunk (best matching nodes merged).
        """
        chunks: list[RetrievedChunk] = []

        for doc_id, tree in self.trees.items():
            if len(chunks) >= top_k:
                break

            nodes = self.searcher.search(tree, query, top_k=2)
            if not nodes:
                continue

            refs = self.fetcher.fetch_with_refs(nodes, tree.doc_title)
            if not refs:
                continue

            # merge text from all matched nodes in this doc
            merged_text = "\n\n".join(r["text"] for r in refs)
            section_refs = ", ".join(r["source_ref"] for r in refs)

            chunks.append(
                RetrievedChunk(
                    text=merged_text,
                    source=tree.source,
                    score=1.0,
                    metadata={
                        "doc_id": doc_id,
                        "sections": section_refs,
                        "node_ids": [r["node_id"] for r in refs],
                    },
                )
            )

        logger.debug("Retrieved %d chunks for: %s", len(chunks), query[:40])
        return chunks

    def reset(self) -> None:
        """Clear in-memory trees."""
        self.trees.clear()
        logger.info("VectorlessRAG reset")

    def load_from_disk(self) -> int:
        """Reload saved trees from index_dir — call this on app restart."""
        count = 0
        for f in self.index_dir.glob("*.json"):
            tree = DocTree.load(f)
            self.trees[tree.doc_id] = tree
            count += 1
        logger.info("Loaded %d trees from %s", count, self.index_dir)
        return count

    @property
    def is_ready(self) -> bool:
        return len(self.trees) > 0
