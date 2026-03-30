# tests/test_vectorless_rag.py
#
# Run:  pytest tests/test_vectorless_rag.py -v
# Cover: tree_builder, tree_searcher, page_fetcher, backend
#
# Pattern: AAA — Arrange / Act / Assert in every test
# LLM is always mocked — no real llama.cpp needed
# tmp_path is pytest's built-in temp dir fixture

import json
from unittest.mock import Mock

import pytest

from src.core.interfaces.base_rag import Document
from src.rag.vectorless.backend import VectorlessRAG
from src.rag.vectorless.page_fetcher import PageFetcher
from src.rag.vectorless.tree_builder import (
    DocTree,
    TreeBuilder,
    TreeNode,
    split_sections,
)
from src.rag.vectorless.tree_searcher import TreeSearcher, _tree_to_text

# ── shared fixtures ───────────────────────────────────────────────


@pytest.fixture()
def fake_llm():
    """Mock LLM — returns a fixed summary string."""
    llm = Mock()
    llm.generate.return_value = "A section about openSUSE package management."
    return llm


@pytest.fixture()
def sample_doc():
    """Minimal markdown document."""
    content = """# Introduction
Welcome to openSUSE.

## Package Management
Use zypper to install packages.
Example: sudo zypper install vim

## System Updates
Run zypper update to update the system.
"""
    return Document(
        id="opensuse-guide",
        title="openSUSE Guide",
        content=content,
        source="https://doc.opensuse.org/guide",
    )


@pytest.fixture()
def built_tree(fake_llm, sample_doc):
    """Pre-built DocTree for reuse across tests."""
    builder = TreeBuilder(fake_llm)
    return builder.build(sample_doc)


# ════════════════════════════════════════════════════════════════
# split_sections
# ════════════════════════════════════════════════════════════════


def test_split_sections_basic():
    text = "# Intro\nhello\n## Sub\nworld"
    sections = split_sections(text)
    assert len(sections) == 2
    assert sections[0]["title"] == "Intro"
    assert sections[1]["title"] == "Sub"


def test_split_sections_no_headings():
    # plain text with no headings → single section
    text = "just plain text\nno headings"
    sections = split_sections(text)
    assert len(sections) == 1
    assert sections[0]["title"] == "full"


def test_split_sections_empty_string():
    sections = split_sections("")
    assert len(sections) == 1


@pytest.mark.parametrize(
    "heading,expected_level",
    [
        ("# H1", 1),
        ("## H2", 2),
        ("### H3", 3),
    ],
)
def test_split_sections_heading_levels(heading, expected_level):
    sections = split_sections(f"{heading}\nsome content")
    assert sections[0]["level"] == expected_level


# ════════════════════════════════════════════════════════════════
# TreeNode
# ════════════════════════════════════════════════════════════════


def test_treenode_to_dict():
    node = TreeNode("0001", "Intro", "About intro", "some text", 0, 1)
    d = node.to_dict()
    assert d["node_id"] == "0001"
    assert d["title"] == "Intro"
    assert d["children"] == []


def test_treenode_roundtrip():
    node = TreeNode("0002", "Packages", "About zypper", "zypper install vim", 1, 2)
    restored = TreeNode.from_dict(node.to_dict())
    assert restored.node_id == node.node_id
    assert restored.title == node.title
    assert restored.text == node.text


def test_treenode_with_children():
    child = TreeNode("0001.0001", "Child", "summary", "text", 0, 1)
    parent = TreeNode("0001", "Parent", "summary", "text", 0, 2, children=[child])
    d = parent.to_dict()
    assert len(d["children"]) == 1
    assert d["children"][0]["node_id"] == "0001.0001"


# ════════════════════════════════════════════════════════════════
# TreeBuilder
# ════════════════════════════════════════════════════════════════


def test_builder_creates_tree(fake_llm, sample_doc):
    tree = TreeBuilder(fake_llm).build(sample_doc)
    assert tree.doc_id == "opensuse-guide"
    assert tree.root is not None


def test_builder_calls_llm_per_section(fake_llm, sample_doc):
    TreeBuilder(fake_llm).build(sample_doc)
    assert fake_llm.generate.call_count >= 2


def test_builder_node_map_has_all_nodes(fake_llm, sample_doc):
    tree = TreeBuilder(fake_llm).build(sample_doc)
    assert "root" in tree.node_map
    assert len(tree.node_map) > 1


def test_builder_llm_failure_uses_fallback(sample_doc):
    bad_llm = Mock()
    bad_llm.generate.side_effect = Exception("timeout")
    tree = TreeBuilder(bad_llm).build(sample_doc)

    # tree still built with fallback summaries
    assert tree.root is not None
    for node in tree.node_map.values():
        assert node.summary


def test_builder_saves_json(fake_llm, sample_doc, tmp_path):
    tree = TreeBuilder(fake_llm).build(sample_doc)
    out = tmp_path / "opensuse-guide.json"
    tree.save(out)

    assert out.exists()
    data = json.loads(out.read_text())
    assert data["doc_id"] == "opensuse-guide"


def test_builder_build_all(fake_llm, sample_doc, tmp_path):
    trees = TreeBuilder(fake_llm).build_all([sample_doc], tmp_path)
    assert len(trees) == 1
    assert (tmp_path / "opensuse-guide.json").exists()


# ════════════════════════════════════════════════════════════════
# DocTree save / load roundtrip
# ════════════════════════════════════════════════════════════════


def test_doctree_roundtrip(built_tree, tmp_path):
    path = tmp_path / "tree.json"
    built_tree.save(path)
    loaded = DocTree.load(path)

    assert loaded.doc_id == built_tree.doc_id
    assert "root" in loaded.node_map


def test_doctree_node_map_complete_after_load(built_tree, tmp_path):
    path = tmp_path / "tree.json"
    built_tree.save(path)
    loaded = DocTree.load(path)

    for node_id in built_tree.node_map:
        assert node_id in loaded.node_map


# ════════════════════════════════════════════════════════════════
# TreeSearcher
# ════════════════════════════════════════════════════════════════


def test_searcher_returns_correct_node(built_tree):
    first_node_id = next(nid for nid in built_tree.node_map if nid != "root")
    llm = Mock()
    llm.generate.return_value = json.dumps(
        {
            "thinking": "package section is relevant",
            "node_list": [first_node_id],
        }
    )

    results = TreeSearcher(llm).search(built_tree, "How do I install packages?")

    assert len(results) >= 1
    assert results[0].node_id == first_node_id


def test_searcher_empty_list_returns_fallback(built_tree):
    llm = Mock()
    llm.generate.return_value = json.dumps(
        {
            "thinking": "nothing found",
            "node_list": [],
        }
    )
    results = TreeSearcher(llm).search(built_tree, "random query")
    assert isinstance(results, list)


def test_searcher_bad_json_does_not_crash(built_tree):
    llm = Mock()
    llm.generate.return_value = "NOT VALID JSON"
    results = TreeSearcher(llm).search(built_tree, "anything")
    assert isinstance(results, list)


def test_searcher_unknown_node_id_skipped(built_tree):
    llm = Mock()
    llm.generate.return_value = json.dumps(
        {
            "thinking": "found",
            "node_list": ["9999"],  # does not exist
        }
    )
    results = TreeSearcher(llm).search(built_tree, "anything")
    assert isinstance(results, list)


def test_tree_to_text_excludes_node_text(built_tree):
    # prompt must not contain raw section text — keeps it small
    output = _tree_to_text(built_tree.root)
    for node in built_tree.node_map.values():
        if node.text and len(node.text) > 20:
            assert node.text[:30] not in output


# ════════════════════════════════════════════════════════════════
# PageFetcher
# ════════════════════════════════════════════════════════════════


def test_fetcher_returns_node_text(built_tree):
    fetcher = PageFetcher()
    node = next(n for n in built_tree.node_map.values() if n.text.strip())
    result = fetcher.fetch([node], built_tree.doc_title)
    assert len(result) > 0


def test_fetcher_empty_list_returns_empty():
    assert PageFetcher().fetch([], "doc") == ""


def test_fetcher_with_refs_structure(built_tree):
    fetcher = PageFetcher()
    nodes = [n for n in built_tree.node_map.values() if n.text.strip()][:2]
    refs = fetcher.fetch_with_refs(nodes, built_tree.doc_title)

    assert len(refs) == len(nodes)
    for ref in refs:
        assert "text" in ref
        assert "source_ref" in ref
        assert "node_id" in ref


def test_fetcher_skips_empty_text_nodes():
    empty = TreeNode("x", "Empty", "summary", "", 0, 1)
    refs = PageFetcher().fetch_with_refs([empty], "doc")
    assert refs == []


# ════════════════════════════════════════════════════════════════
# VectorlessRAG — full pipeline
# ════════════════════════════════════════════════════════════════


def test_backend_not_ready_before_ingest(fake_llm, tmp_path):
    assert VectorlessRAG(tmp_path, fake_llm).is_ready is False


def test_backend_ready_after_ingest(fake_llm, sample_doc, tmp_path):
    backend = VectorlessRAG(tmp_path, fake_llm)
    backend.ingest([sample_doc])
    assert backend.is_ready


def test_backend_reset_clears_trees(fake_llm, sample_doc, tmp_path):
    backend = VectorlessRAG(tmp_path, fake_llm)
    backend.ingest([sample_doc])
    backend.reset()
    assert backend.is_ready is False


def test_backend_retrieve_returns_chunks(fake_llm, sample_doc, tmp_path):
    def side_effect(prompt, max_tokens):
        if "Summarize" in prompt:
            return "summary"
        return json.dumps({"thinking": "ok", "node_list": ["0000"]})

    fake_llm.generate.side_effect = side_effect
    backend = VectorlessRAG(tmp_path, fake_llm)
    backend.ingest([sample_doc])
    chunks = backend.retrieve("How to install packages?")

    assert len(chunks) >= 1
    assert chunks[0].text


def test_backend_chunk_has_correct_source(fake_llm, sample_doc, tmp_path):
    fake_llm.generate.return_value = json.dumps({"thinking": "ok", "node_list": ["0000"]})
    backend = VectorlessRAG(tmp_path, fake_llm)
    backend.ingest([sample_doc])
    chunks = backend.retrieve("zypper")

    assert chunks[0].source == sample_doc.source


def test_backend_chunk_metadata_has_doc_id(fake_llm, sample_doc, tmp_path):
    fake_llm.generate.return_value = json.dumps({"thinking": "ok", "node_list": ["0000"]})
    backend = VectorlessRAG(tmp_path, fake_llm)
    backend.ingest([sample_doc])
    chunks = backend.retrieve("packages")

    assert chunks[0].metadata["doc_id"] == "opensuse-guide"


def test_backend_load_from_disk_restores_trees(fake_llm, sample_doc, tmp_path):
    fake_llm.generate.return_value = "summary"
    backend = VectorlessRAG(tmp_path, fake_llm)
    backend.ingest([sample_doc])
    backend.reset()

    count = backend.load_from_disk()
    assert count == 1
    assert backend.is_ready


def test_backend_multiple_docs_covered(fake_llm, tmp_path):
    fake_llm.generate.return_value = json.dumps({"thinking": "ok", "node_list": ["0000"]})
    docs = [
        Document("doc-1", "Doc One", "# A\ncontent A", "src://a"),
        Document("doc-2", "Doc Two", "# B\ncontent B", "src://b"),
    ]
    backend = VectorlessRAG(tmp_path, fake_llm)
    backend.ingest(docs)
    chunks = backend.retrieve("anything", top_k=5)

    doc_ids = {c.metadata["doc_id"] for c in chunks}
    assert "doc-1" in doc_ids
    assert "doc-2" in doc_ids
