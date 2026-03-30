from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

from src.core.interfaces.base_ingester import FetchedDoc
from src.logger.logger import get_logger

logger = get_logger(__name__)

DEFAULT_CACHE = Path("data/cache/docs")


class ManPageExtractor:
    """
    Extracts man pages for openSUSE commands and caches them as Markdown.
    On-device only — reads from local man database.
    """

    def __init__(self, cache_dir: Path | None = None) -> None:
        self.cache_dir: Path = cache_dir or DEFAULT_CACHE
        self.cache_dir.mkdir(parents=True, exist_ok=True)

    def fetch(self, commands: list[str]) -> list[FetchedDoc]:
        """Extract man pages for a list of commands."""
        docs: list[FetchedDoc] = []

        for cmd in commands:
            cached = self._load_cache(cmd)
            if cached:
                docs.append(cached)
                logger.debug("Man cache hit: %s", cmd)
                continue

            content = self._run_man(cmd)
            if not content:
                logger.warning("No man page found: %s", cmd)
                continue

            self._save_cache(cmd, content)
            docs.append(
                FetchedDoc(
                    url=f"man://{cmd}",
                    title=f"{cmd} man page",
                    content=content,
                    source_type="man",
                    metadata={"command": cmd},
                )
            )
            logger.debug("Extracted man page: %s (%d chars)", cmd, len(content))

        logger.info("Man pages: %d/%d extracted", len(docs), len(commands))
        return docs

    def detect_changes(self, fingerprints: dict[str, str]) -> list[str]:
        """Re-fetch only if cache file is missing."""
        return [cmd for cmd in fingerprints if not (self.cache_dir / f"{cmd}.md").exists()]

    def _run_man(self, command: str) -> str:
        try:
            # Ensure stable UTF-8 output; MANWIDTH avoids line wrapping tied to terminal width.
            env = {**os.environ, "LANG": "C.UTF-8", "MANWIDTH": "120"}
            result = subprocess.run(
                ["man", command],
                capture_output=True,
                text=True,
                timeout=15,
                env=env,
            )
            if result.returncode == 0:
                return self._clean(result.stdout)
        except (subprocess.SubprocessError, FileNotFoundError) as exc:
            logger.warning("man %s failed: %s", command, exc)
        return ""

    def _clean(self, raw: str) -> str:
        """Strip terminal control sequences and collapse blank lines."""
        # Remove ANSI/VT100 escapes
        ansi_re = re.compile(r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")
        text = ansi_re.sub("", raw)

        # Remove backspace-overprint patterns: e.g. "X\b_" -> "X", "X\bX" -> "X"
        # Common in man pages rendered by nroff.
        text = re.sub(r".\x08", "", text)

        # Collapse runs of blank lines into at most one blank line
        lines = text.splitlines()
        cleaned: list[str] = []
        blank_run = 0
        for line in lines:
            if not line.strip():
                blank_run += 1
                if blank_run <= 1:
                    cleaned.append(line)
            else:
                blank_run = 0
                cleaned.append(line)

        return "\n".join(cleaned)

    def _save_cache(self, command: str, content: str) -> None:
        """Persist man page as Markdown file."""
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        cache_file = self.cache_dir / f"{command}.md"
        cache_file.write_text(
            f"# {command} man page\n\n{content}",
            encoding="utf-8",
        )

    def _load_cache(self, command: str) -> FetchedDoc | None:
        cache_file = self.cache_dir / f"{command}.md"
        if not cache_file.exists():
            return None
        content = cache_file.read_text(encoding="utf-8")
        return FetchedDoc(
            url=f"man://{command}",
            title=f"{command} man page",
            content=content,
            source_type="man",
            metadata={"command": command, "from_cache": True},
        )


__all__ = ["ManPageExtractor"]
