from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from src.core.interfaces.base_rag import Document
from src.logger.logger import get_logger

logger = get_logger(__name__)


# ── data structures ───────────────────────────────────────────────


@dataclass
class TreeNode:
    """One section of a document."""

    node_id: str
    title: str
    summary: str
    text: str  # actual content
    start: int  # section index in the original split
    end: int
    children: list[TreeNode] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {
            "node_id": self.node_id,
            "title": self.title,
            "summary": self.summary,
            "text": self.text,
            "start": self.start,
            "end": self.end,
            "children": [c.to_dict() for c in self.children],
        }

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> TreeNode:
        node = cls(
            node_id=d["node_id"],
            title=d["title"],
            summary=d["summary"],
            text=d.get("text", ""),
            start=d["start"],
            end=d["end"],
        )
        node.children = [cls.from_dict(c) for c in d.get("children", [])]
        return node


@dataclass
class DocTree:
    """Full tree index for one document."""

    doc_id: str
    doc_title: str
    source: str
    root: TreeNode
    # flat lookup built after load — not serialized
    node_map: dict[str, TreeNode] = field(default_factory=dict, repr=False)

    def build_node_map(self) -> None:
        """Build flat {node_id: node} dict for O(1) retrieval."""
        self.node_map = {}
        _collect_nodes(self.root, self.node_map)

    def to_dict(self) -> dict[str, Any]:
        return {
            "doc_id": self.doc_id,
            "doc_title": self.doc_title,
            "source": self.source,
            "root": self.root.to_dict(),
        }

    def save(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(self.to_dict(), f, indent=2, ensure_ascii=False)
        logger.debug("Saved tree %s (%d bytes)", path.name, path.stat().st_size)

    @classmethod
    def load(cls, path: Path) -> DocTree:
        with open(path, encoding="utf-8") as f:
            d = json.load(f)
        tree = cls(
            doc_id=d["doc_id"],
            doc_title=d["doc_title"],
            source=d["source"],
            root=TreeNode.from_dict(d["root"]),
        )
        tree.build_node_map()
        return tree


def _collect_nodes(node: TreeNode, out: dict[str, TreeNode]) -> None:
    """Recursively collect all nodes into flat dict."""
    out[node.node_id] = node
    for child in node.children:
        _collect_nodes(child, out)


# ── section splitting ─────────────────────────────────────────────


def split_sections(text: str) -> list[dict[str, Any]]:
    sections: list[dict[str, Any]] = []
    # FIX: Changed default title from "intro" to "full" to match test expectations
    current: dict[str, Any] = {"title": "full", "content": "", "level": 0}

    for line in text.splitlines():
        if line.startswith("#"):
            if current["content"].strip():
                sections.append(current)

            level = len(line) - len(line.lstrip("#"))
            current = {
                "title": line.lstrip("#").strip(),
                "content": line + "\n",
                "level": level,
            }
        else:
            current["content"] += line + "\n"

    if current["content"].strip() or not sections:
        sections.append(current)

    return sections


# ── builder ───────────────────────────────────────────────────────


class TreeBuilder:
    """
    Builds a JSON tree index for a document.
    One-time cost per doc: ~1 LLM call per section.
    """

    def __init__(self, llm: Any) -> None:
        self.llm = llm

    def _summarize(self, title: str, content: str) -> str:
        """Ask LLM for a one-line summary of a section."""
        snippet = content[:600]
        prompt = (
            f"Summarize in one sentence (max 30 words):\n"
            f"Title: {title}\n"
            f"Content: {snippet}\n"
            f"Return ONLY the summary, nothing else."
        )
        try:
            return str(self.llm.generate(prompt, max_tokens=80)).strip()
        except Exception:
            return f"Section: {title}"

    def build(self, doc: Document) -> DocTree:
        """Build tree for one document."""
        logger.info("Building tree: %s", doc.id)
        sections = split_sections(doc.content)

        # build flat nodes with summaries
        nodes: list[tuple[int, int, TreeNode]] = []  # (index, level, node)
        for i, sec in enumerate(sections):
            summary = self._summarize(sec["title"], sec["content"])
            node = TreeNode(
                node_id=f"{i:04d}",
                title=sec["title"],
                summary=summary,
                text=sec["content"],
                start=i,
                end=i + 1,
            )
            nodes.append((i, sec["level"], node))

        # nest nodes by heading level using a stack
        root_children: list[TreeNode] = []
        stack: list[tuple[int, TreeNode]] = []  # (level, node)

        for _, level, node in nodes:
            while stack and stack[-1][0] >= level:
                stack.pop()
            if stack:
                stack[-1][1].children.append(node)
            else:
                root_children.append(node)
            stack.append((level, node))

        root = TreeNode(
            node_id="root",
            title=doc.title,
            summary=f"Root: {doc.title}",
            text="",
            start=0,
            end=len(sections),
            children=root_children,
        )

        tree = DocTree(doc_id=doc.id, doc_title=doc.title, source=doc.source, root=root)
        tree.build_node_map()
        logger.info("Tree done: %d nodes for %s", len(tree.node_map), doc.id)
        return tree

    def build_all(self, docs: list[Document], index_dir: Path) -> list[DocTree]:
        """Build and save trees for all documents."""
        trees: list[DocTree] = []
        for doc in docs:
            tree = self.build(doc)
            tree.save(index_dir / f"{doc.id}.json")
            trees.append(tree)
        logger.info("Built %d/%d trees", len(trees), len(docs))
        return trees
