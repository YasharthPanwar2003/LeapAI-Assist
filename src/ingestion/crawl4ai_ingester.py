from __future__ import annotations

from pathlib import Path
from typing import TYPE_CHECKING, Any

from src.core.interfaces.base_ingester import FetchedDoc
from src.logger.logger import get_logger

logger = get_logger(__name__)

CRAWL4AI_OK = False

# --- Type-checking-only imports (mypy sees these as stubs, NOT assignments) ---
if TYPE_CHECKING:
    from crawl4ai import (
        AsyncWebCrawler,
        BM25ContentFilter,
        BrowserConfig,
        CacheMode,
        CrawlerRunConfig,
        DefaultMarkdownGenerator,
    )

# --- Runtime imports (actual assignments — no clash with TYPE_CHECKING above) ---
try:
    from crawl4ai import (
        AsyncWebCrawler,
        BM25ContentFilter,
        BrowserConfig,
        CacheMode,
        CrawlerRunConfig,
        DefaultMarkdownGenerator,
    )

    CRAWL4AI_OK = True
except Exception as exc:
    raise ImportError(
        "crawl4ai is required. Install and run: pip install crawl4ai && crawl4ai-setup"
    ) from exc


class Crawl4AIExtractor:
    """
    Fetches openSUSE docs as clean Markdown.
    Local-only: headless Chromium via Playwright.
    No Docker, no API keys needed.
    """

    def __init__(
        self,
        js_enabled: bool = False,
        timeout: int = 30,
        bm25_query: str = "openSUSE documentation installation configuration",
        use_cache: bool = True,
    ) -> None:
        if not CRAWL4AI_OK:
            raise ImportError("Run: pip install crawl4ai && crawl4ai-setup")
        self.js_enabled = js_enabled
        self.timeout = timeout
        self.bm25_query = bm25_query
        self.use_cache = use_cache

    def _browser_cfg(self) -> BrowserConfig:
        return BrowserConfig(
            headless=True,
            java_script_enabled=self.js_enabled,
            text_mode=not self.js_enabled,
            verbose=False,
        )

    def _run_cfg(self) -> CrawlerRunConfig:
        content_filter = BM25ContentFilter(
            user_query=self.bm25_query,
            bm25_threshold=1.0,
        )
        md_gen = DefaultMarkdownGenerator(
            content_filter=content_filter,
            options={"ignore_links": False, "body_width": 0},
        )
        return CrawlerRunConfig(
            markdown_generator=md_gen,
            cache_mode=CacheMode.ENABLED if self.use_cache else CacheMode.BYPASS,
            exclude_external_links=True,
            remove_overlay_elements=True,
            word_count_threshold=20,
            page_timeout=self.timeout * 1000,
        )

    async def fetch(self, urls: list[str]) -> list[FetchedDoc]:
        """
        Fetch a list of URLs and return FetchedDoc objects.
        Uses arun_many() for efficient multi-URL crawling.
        """
        docs: list[FetchedDoc] = []
        run_cfg = self._run_cfg()

        async with AsyncWebCrawler(config=self._browser_cfg()) as crawler:
            async for result in await crawler.arun_many(urls, config=run_cfg):
                # ❌ REMOVED: result: Any = result  ← caused [no-redef]

                if not result.success:
                    logger.warning("Failed: %s — %s", result.url, result.error_message)
                    continue

                if result.markdown is None:
                    logger.warning("No markdown: %s", result.url)
                    continue

                content = result.markdown.fit_markdown or result.markdown.raw_markdown
                content = str(content).strip()

                if len(content) < 100:
                    logger.debug("Too short, skipping: %s", result.url)
                    continue

                resp_headers: dict[str, str] = result.response_headers or {}
                title = self._get_title(result, result.url)

                docs.append(
                    FetchedDoc(
                        url=result.url,
                        title=title,
                        content=content,
                        source_type="web",
                        metadata={
                            "etag": resp_headers.get("etag", ""),
                            "status": result.status_code,
                            "word_count": len(content.split()),
                        },
                    )
                )
                logger.debug("Fetched: %s (%d words)", result.url, len(content.split()))

        logger.info("Fetched %d/%d pages", len(docs), len(urls))
        return docs

    async def fetch_changed(
        self,
        urls: list[str],
        fingerprints: dict[str, str],
    ) -> list[FetchedDoc]:
        """
        Only fetch URLs whose ETag changed since last run.
        fingerprints = {url: etag_from_last_fetch}
        """
        to_fetch = []
        for url in urls:
            stored_etag = fingerprints.get(url, "")
            if not stored_etag:
                to_fetch.append(url)
                continue
            try:
                import httpx as _httpx

                async with _httpx.AsyncClient(timeout=10) as client:
                    resp = await client.head(url, headers={"If-None-Match": stored_etag})
                    if resp.status_code == 304:
                        logger.debug("Unchanged (304): %s", url)
                        continue
            except Exception:
                pass
            to_fetch.append(url)

        logger.info("%d/%d URLs need re-fetch", len(to_fetch), len(urls))
        return await self.fetch(to_fetch)

    def detect_changes(self, fingerprints: dict[str, str]) -> list[str]:
        """Return all URLs — actual ETag check in fetch_changed()."""
        return list(fingerprints.keys())

    def _get_title(self, result: Any, url: str) -> str:
        if hasattr(result, "metadata") and result.metadata:
            title = result.metadata.get("title", "")
            if title:
                return str(title)  # ← FIXED: wrap in str()
        return str(Path(url).stem.replace("-", " ").title())
