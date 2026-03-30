from __future__ import annotations

import asyncio
import json
from collections.abc import AsyncGenerator
from typing import Any

import httpx

from src.logger.logger import get_logger

logger = get_logger(__name__)


class LlamaClient:
    """
    HTTP client for llama.cpp server.
    Text generation on port 8080, embeddings on port 8081.
    """

    def __init__(
        self,
        base_url: str = "http://localhost:8080/v1",
        timeout: float = 120.0,
        max_retries: int = 3,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout
        self.max_retries = max_retries
        self._client: httpx.AsyncClient | None = None

    async def _get_client(self) -> httpx.AsyncClient:
        if self._client is None or self._client.is_closed:
            self._client = httpx.AsyncClient(
                timeout=httpx.Timeout(self.timeout),
                limits=httpx.Limits(max_keepalive_connections=5),
            )
        return self._client

    async def close(self) -> None:
        if self._client and not self._client.is_closed:
            await self._client.aclose()

    async def generate_stream(
        self,
        messages: list[dict[str, str]],
        max_tokens: int = 512,
        temperature: float = 0.3,
        stop: list[str] | None = None,
    ) -> AsyncGenerator[str]:
        client = await self._get_client()

        payload: dict[str, Any] = {
            "model": "local",
            "messages": messages,
            "max_tokens": max_tokens,
            "temperature": temperature,
            "stream": True,
        }
        if stop:
            payload["stop"] = stop

        last_error: httpx.HTTPError | None = None

        for attempt in range(self.max_retries):
            try:
                async with client.stream(
                    "POST",
                    f"{self.base_url}/chat/completions",
                    json=payload,
                ) as response:
                    response.raise_for_status()

                    async for line in response.aiter_lines():
                        if not line.startswith("data: "):
                            continue
                        data = line[6:]
                        if data.strip() == "[DONE]":
                            return
                        try:
                            chunk = json.loads(data)
                            content = chunk["choices"][0]["delta"].get("content", "")
                            if content:
                                yield content
                        except (json.JSONDecodeError, KeyError):
                            logger.warning("Invalid SSE chunk: %s", data[:80])
                return

            except httpx.HTTPError as exc:
                last_error = exc
                logger.warning("Attempt %d/%d failed: %s", attempt + 1, self.max_retries, exc)
                if attempt < self.max_retries - 1:
                    await asyncio.sleep(2**attempt)

        if last_error:
            raise last_error

    async def generate(
        self,
        messages: list[dict[str, str]],
        **kwargs: Any,
    ) -> str:
        tokens: list[str] = []
        async for token in self.generate_stream(messages, **kwargs):
            tokens.append(token)
        return "".join(tokens)

    async def check_health(self) -> bool:
        client = await self._get_client()
        try:
            response = await client.get(f"{self.base_url}/models")
            return bool(response.status_code == 200)  # cast — fixes mypy
        except httpx.HTTPError:
            return False

    async def generate_embedding(self, text: str, model: str = "local") -> list[float]:
        client = await self._get_client()
        response = await client.post(
            f"{self.base_url}/embeddings",
            json={"model": model, "input": text},
        )
        response.raise_for_status()
        data = response.json()
        return list(map(float, data["data"][0]["embedding"]))  # cast — fixes mypy
