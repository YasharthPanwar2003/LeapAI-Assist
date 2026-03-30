from __future__ import annotations

import json
from typing import Any

from src.logger.logger import get_logger
from src.rag.vectorless.tree_builder import DocTree, TreeNode

logger = get_logger(__name__)


def _tree_to_text(node: TreeNode, depth: int = 0) -> str:
    indent = "  " * depth
    lines = [f"{indent}[{node.node_id}] {node.title} — {node.summary}"]
    for child in node.children:
        lines.append(_tree_to_text(child, depth + 1))
    return "\n".join(lines)


class TreeSearcher:
    """
    Asks LLM to reason over a tree and return relevant node_ids.
    LLM response format: {"thinking": "...", "node_list": ["0002", "0005"]}
    Cost: 1 LLM call per doc per query.
    """

    def __init__(self, llm: Any) -> None:
        self.llm = llm

    def search(self, tree: DocTree, query: str, top_k: int = 3) -> list[TreeNode]:
        """
        Ask LLM which nodes answer the query.
        Returns list of TreeNode objects (with text).
        """
        tree_text = _tree_to_text(tree.root)

        prompt = (
            f"You have a documentation tree. Find all nodes relevant to the query.\n\n"
            f"Query: {query}\n\n"
            f"Document: {tree.doc_title}\n"
            f"Tree:\n{tree_text}\n\n"
            f"Reply ONLY in this JSON format:\n"
            f'{{"thinking": "<your reasoning>", "node_list": ["node_id1", "node_id2"]}}\n'
            f"Return [] in node_list if nothing is relevant."
        )

        try:
            raw = self.llm.generate(prompt, max_tokens=200).strip()
            result = json.loads(raw)
            node_ids: list[str] = result.get("node_list", [])
        except (json.JSONDecodeError, KeyError):
            logger.warning("LLM returned bad JSON for tree search in %s", tree.doc_id)
            # fallback: return first top_k children
            return list(tree.root.children[:top_k])

        nodes = []
        for nid in node_ids:
            node = tree.node_map.get(nid)
            if node:
                nodes.append(node)
            else:
                logger.warning("node_id %s not in tree %s", nid, tree.doc_id)

        # if LLM found nothing, fall back to top-level children
        if not nodes:
            nodes = list(tree.root.children[:top_k])

        return nodes[:top_k]
