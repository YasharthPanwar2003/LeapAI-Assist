"""
tests/test_week1.py — Test All Week 1 Files
openSUSE AI Assistant — GSoC 2026 #259

Stack:  Python 3.13.12 · pytest 9.0.2 · pytest-asyncio 1.3.0 · openSUSE Leap 16
Run:    python -m pytest tests/test_week1.py -v --tb=short
"""

from pathlib import Path

import pytest

from src.core.config_loader import Config, init_config
from src.core.interfaces.base_ingester import FetchedDoc
from src.core.interfaces.base_rag import Document, RetrievedChunk
from src.core.interfaces.base_ui import UIBase
from src.logger import get_logger


# ════════════════════════════════════════════════════════════════
# TEST CLASS 1 — LOGGER
# ════════════════════════════════════════════════════════════════
class TestLogger:
    """Tests for src/logger/logger.py via src/logger/__init__.py."""

    def test_get_logger_creates_logger(self):
        """get_logger() returns a named logger at DEBUG level (10)."""
        logger = get_logger("test_module")
        assert logger.name == "test_module"
        assert logger.level == 10  # logging.DEBUG

    def test_logger_has_console_handler(self):
        """Logger must have at least one handler attached."""
        logger = get_logger("test_console")
        assert len(logger.handlers) >= 1

    def test_logger_prevents_duplicates(self):
        """Same name → same object; no duplicate handlers across calls.

        Extra important under pytest-asyncio 1.3 / pytest 9 which runs
        tests in-process (no subprocess), so handlers accumulate faster.
        """
        logger1 = get_logger("test_dup")
        logger2 = get_logger("test_dup")
        assert logger1 is logger2


# ════════════════════════════════════════════════════════════════
# TEST CLASS 2 — CONFIG LOADER
# ════════════════════════════════════════════════════════════════
class TestConfig:
    """Tests for src/core/config_loader.py — Config dataclass."""

    def test_config_default_values(self):
        """Config() with no args must match openSUSE Leap 16 defaults."""
        config = Config()
        assert config.rag_backend == "vectorless"
        assert config.top_k == 5
        assert config.context_size == 8192
        assert config.temperature == 0.3
        assert config.max_tokens == 512
        assert config.embed_dim == 768
        assert config.llm_url == "http://localhost:8080/v1"
        assert config.llm_model == "local"
        assert config.embed_url == "http://localhost:8081/v1"
        assert config.semantic_cache_enabled is True
        assert config.semantic_cache_ttl_days == 7
        assert config.version_probe_enabled is True

    def test_config_paths_are_posixpath(self):
        """models_dir / index_dir / cache_dir / state_dir must be Path objects."""
        config = Config()
        assert isinstance(config.models_dir, Path)
        assert isinstance(config.index_dir, Path)
        assert isinstance(config.cache_dir, Path)
        assert isinstance(config.state_dir, Path)

    def test_config_validation_invalid_backend(self):
        """Unsupported rag_backend string must raise ValueError."""
        with pytest.raises(ValueError):
            Config(rag_backend="invalid_backend")

    def test_config_validation_temperature_too_high(self):
        """temperature > 2.0 must raise ValueError."""
        with pytest.raises(ValueError):
            Config(temperature=3.0)

    def test_config_validation_temperature_negative(self):
        """temperature < 0.0 must raise ValueError."""
        with pytest.raises(ValueError):
            Config(temperature=-0.1)

    def test_config_load_nonexistent_returns_defaults(self, tmp_path):
        """Loading a missing YAML file must silently return default Config."""
        config = Config.load(tmp_path / "nonexistent.yaml")
        assert config.rag_backend == "vectorless"

    def test_config_save_and_load_roundtrip(self, tmp_path):
        """Values written by .save() must survive a .load() round-trip."""
        config_path = tmp_path / "config.yaml"
        Config(rag_backend="vector", top_k=10).save(config_path)

        loaded = Config.load(config_path)
        assert loaded.rag_backend == "vector"
        assert loaded.top_k == 10

    def test_init_config_creates_file_with_defaults(self, tmp_path):
        """init_config() must create the YAML file and return default Config."""
        config_path = tmp_path / "new_config.yaml"
        config = init_config(config_path)

        assert config_path.exists(), "YAML file was not created"
        assert config.rag_backend == "vectorless"


# ════════════════════════════════════════════════════════════════
# TEST CLASS 3 — DOCUMENT  (base_rag.py)
# ════════════════════════════════════════════════════════════════
class TestDocument:
    """Tests for the Document dataclass in src/core/interfaces/base_rag.py."""

    def test_document_creation(self):
        """Document fields are stored correctly on construction."""
        doc = Document(
            id="doc-1",
            title="Test Doc",
            content="Some content",
            source="/docs/test.md",
        )
        assert doc.id == "doc-1"
        assert doc.title == "Test Doc"
        assert doc.content == "Some content"
        assert doc.source == "/docs/test.md"

    def test_document_metadata_defaults_to_empty_dict(self):
        """metadata must default to {} when not supplied."""
        doc = Document(id="x", title="X", content="X", source="/x.md")
        assert doc.metadata == {}

    def test_document_to_dict(self):
        """to_dict() must serialise all fields including nested metadata."""
        doc = Document(
            id="doc-2",
            title="With Meta",
            content="Body",
            source="/docs/meta.md",
            metadata={"version": "16.0", "lang": "en"},
        )
        d = doc.to_dict()
        assert d["id"] == "doc-2"
        assert d["title"] == "With Meta"
        assert d["metadata"]["version"] == "16.0"
        assert d["metadata"]["lang"] == "en"

    def test_document_from_dict(self):
        """from_dict() must reconstruct a Document with matching fields."""
        data = {
            "id": "doc-3",
            "title": "From Dict",
            "content": "Content",
            "source": "/docs/from.md",
            "metadata": {"tag": "test"},
        }
        doc = Document.from_dict(data)
        assert doc.id == "doc-3"
        assert doc.metadata["tag"] == "test"

    def test_document_round_trip(self):
        """to_dict() → from_dict() must produce an equal Document."""
        original = Document(
            id="rt-1",
            title="Round Trip",
            content="Hello openSUSE",
            source="/rt.md",
            metadata={"week": "1"},
        )
        restored = Document.from_dict(original.to_dict())
        assert restored.id == original.id
        assert restored.title == original.title
        assert restored.content == original.content
        assert restored.metadata == original.metadata


# ════════════════════════════════════════════════════════════════
# TEST CLASS 4 — RETRIEVED CHUNK  (base_rag.py)
# ════════════════════════════════════════════════════════════════
class TestRetrievedChunk:
    """Tests for RetrievedChunk in src/core/interfaces/base_rag.py."""

    def test_chunk_creation_with_score(self):
        """RetrievedChunk stores text, source, and explicit score."""
        chunk = RetrievedChunk(
            text="Relevant passage",
            source="/docs/ref.md",
            score=0.87,
        )
        assert chunk.text == "Relevant passage"
        assert chunk.source == "/docs/ref.md"
        assert chunk.score == 0.87

    def test_chunk_default_score_is_one(self):
        """score must default to 1.0 for the vectorless backend."""
        chunk = RetrievedChunk(text="No score", source="/docs/x.md")
        assert chunk.score == 1.0


# ════════════════════════════════════════════════════════════════
# TEST CLASS 5 — FETCHED DOC  (base_ingester.py)
# ════════════════════════════════════════════════════════════════
class TestFetchedDoc:
    """Tests for FetchedDoc in src/core/interfaces/base_ingester.py."""

    def test_fetched_doc_creation(self):
        """FetchedDoc stores url, title, content and source_type."""
        doc = FetchedDoc(
            url="https://doc.opensuse.org/leap16/",
            title="Leap 16 Docs",
            content="<html>Welcome</html>",
            source_type="web",
        )
        assert doc.url == "https://doc.opensuse.org/leap16/"
        assert doc.source_type == "web"

    def test_fetched_doc_size_bytes_ascii(self):
        """size_bytes() must return correct byte count for ASCII content."""
        doc = FetchedDoc(
            url="https://example.com",
            title="Example",
            content="Hello",  # 5 bytes
        )
        assert doc.size_bytes() == 5

    def test_fetched_doc_size_bytes_unicode(self):
        """size_bytes() must count UTF-8 bytes, not character count."""
        content = "café"  # 5 bytes in UTF-8 (é = 2 bytes), 4 chars
        doc = FetchedDoc(url="https://example.com", title="UTF8", content=content)
        assert doc.size_bytes() == len(content.encode("utf-8"))

    def test_fetched_doc_to_dict(self):
        """to_dict() must include url, title, content, source_type, section."""
        doc = FetchedDoc(
            url="https://doc.opensuse.org",
            title="openSUSE",
            content="Body text",
            source_type="web",
            section="Installation",
        )
        d = doc.to_dict()
        assert d["url"] == "https://doc.opensuse.org"
        assert d["section"] == "Installation"
        assert d["source_type"] == "web"


# ════════════════════════════════════════════════════════════════
# TEST CLASS 6 — UI BASE  (base_ui.py)
# ════════════════════════════════════════════════════════════════
class TestUIBase:
    """Tests for UIBase in src/core/interfaces/base_ui.py.

    All async tests use `async def` + `await` — DO NOT use asyncio.run().
    pytest-asyncio 1.3 with asyncio_mode="auto" handles the event loop
    automatically; calling asyncio.run() inside it causes RuntimeError.
    """

    async def test_display_message_not_implemented(self):
        """UIBase.display_message() must raise NotImplementedError."""
        ui = UIBase()
        with pytest.raises(NotImplementedError):
            await ui.display_message("user", "Hello openSUSE")

    async def test_stream_response_not_implemented(self):
        """UIBase.stream_response() must raise NotImplementedError."""
        ui = UIBase()

        async def _fake_stream():
            yield "token"

        with pytest.raises(NotImplementedError):
            await ui.stream_response(_fake_stream())

    def test_update_status_not_implemented(self):
        """UIBase.update_status() is sync and must raise NotImplementedError."""
        ui = UIBase()
        with pytest.raises(NotImplementedError):
            ui.update_status("Ready")

    def test_close_does_not_raise(self):
        """UIBase.close() is a no-op base implementation — must not raise."""
        ui = UIBase()
        ui.close()


# ════════════════════════════════════════════════════════════════
# RUN WITH: python -m pytest tests/test_week1.py -v --tb=short
# ════════════════════════════════════════════════════════════════
