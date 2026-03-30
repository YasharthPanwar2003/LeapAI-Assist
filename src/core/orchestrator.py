from __future__ import annotations

import hashlib
import re
import subprocess
from collections import deque
from collections.abc import AsyncGenerator
from dataclasses import dataclass, field
from pathlib import Path

from src.core.config_loader import Config, get_config
from src.core.interfaces.base_rag import RetrievedChunk
from src.inference.llama_client import LlamaClient
from src.logger.logger import get_logger
from src.rag.vectorless.backend import VectorlessRAG

logger = get_logger(__name__)


@dataclass
class SessionState:
    """Rolling conversation + token budget tracker."""

    history: deque = field(default_factory=lambda: deque(maxlen=10))
    token_count: int = 0
    os_context: str = ""


class Orchestrator:
    """
    Query router + 5-zone prompt builder + semantic cache.

    Zone 1 — system prompt (static openSUSE persona)
    Zone 2 — OS state (distro, version, failed services)
    Zone 3 — RAG context (retrieved doc chunks)
    Zone 4 — rolling conversation history
    Zone 5 — current user query  ← always last
    """

    def __init__(
        self,
        config: Config | None = None,
        index_dir: Path | None = None,
    ) -> None:
        self.config = config or get_config()
        self.index_dir = index_dir or self.config.index_dir

        self.llm = LlamaClient(base_url=self.config.llm_url)
        self.rag = VectorlessRAG(self.index_dir, self.llm)
        self.session = SessionState()
        self._cache: dict[str, str] = {}

        self.rag.load_from_disk()
        logger.info("Orchestrator ready (rag_backend=%s)", self.config.rag_backend)

    async def process_query(
        self,
        query: str,
        stream: bool = True,
    ) -> str | AsyncGenerator[str]:
        """Main entry point. Returns streamed tokens or full string."""
        logger.info("Query: %s...", query[:50])

        cached = self._cache_get(query)
        if cached:
            logger.debug("Cache hit")
            if stream:
                return self._replay(cached)
            return cached

        if not self.session.os_context:
            self.session.os_context = self._probe_os()

        chunks = self.rag.retrieve(query, top_k=self.config.top_k)
        messages = self._build_messages(query, chunks)

        if stream:
            return self._stream(messages)

        return await self.llm.generate(
            messages,
            max_tokens=self.config.max_tokens,
            temperature=self.config.temperature,
        )

    def _build_messages(
        self,
        query: str,
        chunks: list[RetrievedChunk],
    ) -> list[dict[str, str]]:
        """Assemble 5-zone prompt."""

        # Zone 1+2: system prompt with OS context
        system = self._system_prompt()
        if self.session.os_context:
            system += f"\n\nCurrent System:\n{self.session.os_context}"

        # Zone 3: RAG docs
        user = ""
        if chunks:
            rag_text = "\n\n".join(
                f"[Source {i + 1}] {c.metadata.get('sections', c.source)}\n{c.text[:1500]}"
                for i, c in enumerate(chunks)
            )
            user += f"Documentation:\n{rag_text}\n\n"

        # Zone 4: conversation history (last 4 messages)
        if self.session.history:
            user += "Previous conversation:\n"
            for msg in list(self.session.history)[-4:]:
                user += f"{msg['role']}: {msg['content']}\n"
            user += "\n"

        # Zone 5: current query — always last
        user += f"Question: {query}"

        return [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ]

    def _system_prompt(self) -> str:
        version = self._detect_version()
        if version.startswith("15."):
            tooling = "YaST (yast2 commands)"
            corpus = "Leap 15.x"
        else:
            tooling = "Cockpit (localhost:9090) + Myrlyn + zypper"
            corpus = "Leap 16+"

        return (
            f"You are an AI assistant for openSUSE Linux, running locally on this machine.\n"
            f"Help with package management, system config, troubleshooting, and {corpus} docs.\n"
            f"- Use zypper for package management\n"
            f"- Use systemctl for services\n"
            f"- On {corpus}: use {tooling}\n"
            f"Always cite sources. Be concise. No external API calls."
        )

    def _probe_os(self) -> str:
        """Read /etc/os-release and systemctl for system context."""
        try:
            with open("/etc/os-release") as fh:
                os_data = dict(re.findall(r'(\w+)="?([^"\n]+)', fh.read()))
            failed = self._failed_services()
            return (
                f"Distribution: {os_data.get('PRETTY_NAME', 'openSUSE')}\n"
                f"Version: {os_data.get('VERSION_ID', 'unknown')}\n"
                f"Failed services: {failed or 'none'}"
            )
        except Exception as exc:
            logger.warning("OS probe failed: %s", exc)
            return "System context: unavailable"

    def _detect_version(self) -> str:
        try:
            with open("/etc/os-release") as fh:
                data = dict(re.findall(r'(\w+)="?([^"\n]+)', fh.read()))
            return str(data.get("VERSION_ID", "unknown"))
        except Exception:
            return "unknown"

    def _failed_services(self) -> str:
        try:
            result = subprocess.run(
                ["systemctl", "--failed", "--no-pager", "--plain"],
                capture_output=True,
                text=True,
                timeout=10,
            )
            if result.returncode == 0 and result.stdout.strip():
                services = [
                    line.split()[0] for line in result.stdout.strip().splitlines() if line.split()
                ]
                return ", ".join(services[:5])
        except Exception as exc:
            logger.warning("systemctl check failed: %s", exc)
        return ""

    async def _stream(
        self,
        messages: list[dict[str, str]],
    ) -> AsyncGenerator[str]:
        full = ""
        async for token in self.llm.generate_stream(
            messages,
            max_tokens=self.config.max_tokens,
            temperature=self.config.temperature,
        ):
            full += token
            yield token

        self._update_session(messages[-1]["content"], full)
        self._cache_set(messages[-1]["content"], full)

    async def _replay(self, text: str) -> AsyncGenerator[str]:
        """Word-by-word replay of a cached response."""
        for word in text.split():
            yield word + " "

    def _update_session(self, query: str, response: str) -> None:
        self.session.history.append({"role": "user", "content": query})
        self.session.history.append({"role": "assistant", "content": response})
        self.session.token_count += len(query.split()) + len(response.split())

        # evict oldest turns when over token budget
        budget = self.config.context_size // 4
        while self.session.token_count > budget and len(self.session.history) > 2:
            old = self.session.history.popleft()
            self.session.token_count -= len(old["content"].split())

    def _cache_get(self, query: str) -> str | None:
        if not self.config.semantic_cache_enabled:
            return None
        return self._cache.get(hashlib.sha256(query.encode()).hexdigest())

    def _cache_set(self, query: str, response: str) -> None:
        if not self.config.semantic_cache_enabled:
            return
        key = hashlib.sha256(query.encode()).hexdigest()
        self._cache[key] = response
        logger.debug("Cache write: %s...", key[:12])

    async def close(self) -> None:
        await self.llm.close()
        logger.info("Orchestrator closed")
