from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml

from src.logger.logger import get_logger

logger = get_logger(__name__)

_VALID_BACKENDS = ("vectorless", "vector")


@dataclass
class Config:
    """
    All app settings in one place.
    Load from YAML via Config.load(path).
    Change rag_backend: vectorless → vector in config.yaml.
    """

    # RAG
    rag_backend: str = "vectorless"
    top_k: int = 5

    # LLM
    llm_url: str = "http://localhost:8080/v1"
    llm_model: str = "local"
    context_size: int = 8192
    temperature: float = 0.3
    max_tokens: int = 512

    # Embeddings (vector backend only)
    embed_url: str = "http://localhost:8081/v1"
    embed_dim: int = 768

    # Paths
    models_dir: Path = Path("/var/lib/suse-ai/models")
    index_dir: Path = Path("/var/lib/suse-ai/index")
    cache_dir: Path = Path("/var/lib/suse-ai/cache/docs")
    state_dir: Path = Path("/var/lib/suse-ai/state")

    # Cache
    semantic_cache_enabled: bool = True
    semantic_cache_ttl_days: int = 7

    # OS integration
    version_probe_enabled: bool = True

    # Catch-all for future keys
    extra: dict[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        """Validate right after dataclass __init__ runs."""
        if self.rag_backend not in _VALID_BACKENDS:
            raise ValueError(
                f"rag_backend must be one of {_VALID_BACKENDS}, got {self.rag_backend!r}"
            )
        if not (0.0 <= self.temperature <= 2.0):
            raise ValueError(f"temperature must be 0.0–2.0, got {self.temperature}")

    @classmethod
    def load(cls, config_path: Path) -> Config:
        """Load config from YAML. Returns defaults if file doesn't exist."""
        if not config_path.exists():
            logger.warning("Config not found at %s — using defaults", config_path)
            return cls()

        try:
            with open(config_path, encoding="utf-8") as f:
                raw: dict[str, Any] = yaml.safe_load(f) or {}
        except yaml.YAMLError as e:
            logger.error("Bad YAML in %s: %s", config_path, e)
            raise ValueError(f"Invalid YAML: {e}") from e

        # Convert string → Path for path fields
        for key in ("models_dir", "index_dir", "cache_dir", "state_dir"):
            if key in raw:
                raw[key] = Path(raw[key])

        # Drop unknown keys so dataclass __init__ doesn't choke
        known_fields = {f.name for f in cls.__dataclass_fields__.values()}
        clean = {k: v for k, v in raw.items() if k in known_fields}

        logger.info("Config loaded (rag_backend=%s)", clean.get("rag_backend", "vectorless"))
        return cls(**clean)

    def save(self, config_path: Path) -> None:
        """Write current config back to YAML."""
        try:
            config_path.parent.mkdir(parents=True, exist_ok=True)
            data = {k: str(v) if isinstance(v, Path) else v for k, v in self.__dict__.items()}
            with open(config_path, "w", encoding="utf-8") as f:
                yaml.dump(data, f, default_flow_style=False, sort_keys=False)
            logger.info("Config saved to %s", config_path)
        except (OSError, PermissionError) as e:
            logger.error("Could not save config: %s", e)
            raise


# ── Singleton helpers ─────────────────────────────────────────────
_config: Config | None = None
_CONFIG_PATH = Path("/var/lib/suse-ai/state/config.yaml")


def get_config() -> Config:
    """Return the global Config, loading it on first call."""
    global _config
    if _config is None:
        _config = Config.load(_CONFIG_PATH)
    return _config


def reload_config() -> Config:
    """Force a fresh load from disk."""
    global _config
    _config = Config.load(_CONFIG_PATH)
    return _config


def init_config(config_path: Path | None = None) -> Config:
    """Load config, or create a default config.yaml if it's missing."""
    path = config_path or _CONFIG_PATH
    if not path.exists():
        logger.info("Creating default config at %s", path)
        cfg = Config()
        cfg.save(path)
        return cfg
    return Config.load(path)
