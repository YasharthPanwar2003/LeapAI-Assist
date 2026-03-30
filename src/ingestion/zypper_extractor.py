from __future__ import annotations

import subprocess
from pathlib import Path

from src.core.interfaces.base_ingester import FetchedDoc
from src.logger.logger import get_logger

logger = get_logger(__name__)

DEFAULT_CACHE = Path("data/cache/docs")


class ZypperExtractor:
    """
    Extracts package information from zypper and caches as Markdown.
    On-device only — only works on openSUSE/SUSE systems.
    """

    def __init__(self, cache_dir: Path | None = None) -> None:
        self.cache_dir: Path = cache_dir or DEFAULT_CACHE
        self.cache_dir.mkdir(parents=True, exist_ok=True)

    def fetch(self, packages: list[str]) -> list[FetchedDoc]:
        """Fetch package info for a list of package names."""
        docs: list[FetchedDoc] = []

        for pkg in packages:
            cached = self._load_cache(pkg)
            if cached:
                docs.append(cached)
                logger.debug("Zypper cache hit: %s", pkg)
                continue

            content = self._query_package(pkg)
            if not content:
                logger.warning("No zypper info for: %s", pkg)
                continue

            self._save_cache(pkg, content)
            docs.append(
                FetchedDoc(
                    url=f"zypper://{pkg}",
                    title=f"{pkg} package info",
                    content=content,
                    source_type="man",  # treated same as man page
                    section="zypper",
                    metadata={"package": pkg},
                )
            )
            logger.debug("Zypper info: %s (%d chars)", pkg, len(content))

        logger.info("Zypper: %d/%d packages extracted", len(docs), len(packages))
        return docs

    def detect_changes(self, fingerprints: dict[str, str]) -> list[str]:
        """Re-fetch only if cache file is missing."""
        return [pkg for pkg in fingerprints if not (self.cache_dir / f"zypper_{pkg}.md").exists()]

    def search_packages(self, query: str) -> str:
        """Run zypper search and return output as plain text."""
        try:
            result = subprocess.run(
                ["zypper", "search", "--details", query],
                capture_output=True,
                text=True,
                timeout=30,
            )
            return result.stdout if result.returncode == 0 else ""
        except (subprocess.SubprocessError, FileNotFoundError) as exc:
            logger.warning("zypper search failed: %s", exc)
            return ""

    def _query_package(self, pkg: str) -> str:
        """Run zypper info <pkg> and format as Markdown."""
        info = self._run_zypper_info(pkg)
        if not info:
            return ""

        lines = [f"# {pkg} — openSUSE Package\n"]
        lines.append("## Package Information\n")
        lines.append("```")
        lines.append(info.strip())
        lines.append("```\n")

        # also grab list of files if available
        files = self._run_zypper_files(pkg)
        if files:
            lines.append("## Installed Files\n")
            lines.append("```")
            lines.append(files.strip()[:2000])  # cap size
            lines.append("```")

        return "\n".join(lines)

    def _run_zypper_info(self, pkg: str) -> str:
        try:
            result = subprocess.run(
                ["zypper", "--quiet", "info", pkg],
                capture_output=True,
                text=True,
                timeout=30,
            )
            return result.stdout if result.returncode == 0 else ""
        except (subprocess.SubprocessError, FileNotFoundError) as exc:
            logger.warning("zypper info %s failed: %s", pkg, exc)
            return ""

    def _run_zypper_files(self, pkg: str) -> str:
        """Get file list via rpm (zypper doesn't list files directly)."""
        try:
            result = subprocess.run(
                ["rpm", "-ql", pkg],
                capture_output=True,
                text=True,
                timeout=15,
            )
            return result.stdout if result.returncode == 0 else ""
        except (subprocess.SubprocessError, FileNotFoundError):
            return ""

    def _save_cache(self, pkg: str, content: str) -> None:
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        cache_file = self.cache_dir / f"zypper_{pkg}.md"
        cache_file.write_text(content, encoding="utf-8")

    def _load_cache(self, pkg: str) -> FetchedDoc | None:
        cache_file = self.cache_dir / f"zypper_{pkg}.md"
        if not cache_file.exists():
            return None
        content = cache_file.read_text(encoding="utf-8")
        return FetchedDoc(
            url=f"zypper://{pkg}",
            title=f"{pkg} package info",
            content=content,
            source_type="man",
            section="zypper",
            metadata={"package": pkg, "from_cache": True},
        )
