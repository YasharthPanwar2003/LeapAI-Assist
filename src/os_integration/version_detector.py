from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

from src.logger import get_logger

logger = get_logger(__name__)

# Map VERSION_ID prefix → management tooling name
_TOOL_MAP: dict[str, str] = {
    "15.": "YaST",
    "16.": "Cockpit",
}


class VersionDetector:
    """
    Detects openSUSE version and available management tools.

    Usage::

        detector = VersionDetector()
        info = detector.detect()
        print(info["version_id"])        # e.g. "16.0"
        print(info["management_tool"])   # e.g. "Cockpit"
        corpus = detector.get_corpus_name()  # "agama" or "yast"
    """

    def __init__(self) -> None:
        self._cache: dict | None = None

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def detect(self, force_refresh: bool = False) -> dict:
        """
        Detect system version and management tools.

        Returns a dict with keys:
            version_id, pretty_name, management_tool,
            has_yast, has_cockpit, has_agama

        Architecture Section 6: Version-aware tool mapping.
        Architecture Section 11: Python version detection.
        """
        if self._cache and not force_refresh:
            return self._cache

        info: dict = {
            "version_id": "unknown",
            "pretty_name": "openSUSE",
            "management_tool": "unknown",
            "has_yast": False,
            "has_cockpit": False,
            "has_agama": False,
        }

        # Parse /etc/os-release
        release_path = Path("/etc/os-release")
        if release_path.exists():
            try:
                os_data = self._parse_os_release(release_path.read_text())
                info["version_id"] = os_data.get("VERSION_ID", "tumbleweed")
                info["pretty_name"] = os_data.get("PRETTY_NAME", "openSUSE")
                logger.debug(
                    "os-release: %s %s",
                    info["pretty_name"],
                    info["version_id"],
                )
            except OSError as exc:
                logger.warning("Failed to read /etc/os-release: %s", exc)

        # Select tooling based on version prefix
        vid = info["version_id"]
        if vid.startswith("15."):
            info["management_tool"] = "YaST"
            info["has_yast"] = self._check_yast()
        elif vid.startswith("16."):
            info["management_tool"] = "Cockpit"
            info["has_cockpit"] = self._check_cockpit()
            info["has_agama"] = self._check_agama()
        else:
            # Tumbleweed or unknown — assume Cockpit tooling
            info["management_tool"] = "Cockpit"
            info["has_cockpit"] = self._check_cockpit()

        self._cache = info
        logger.info(
            "Version detection complete: %s → %s",
            info["version_id"],
            info["management_tool"],
        )
        return info

    def get_corpus_name(self) -> str:
        """
        Return the documentation corpus key for RAG.

        Returns:
            ``"yast"`` for Leap 15.x, ``"agama"`` for Leap 16+ / Tumbleweed.

        Architecture Section 6: Corpus selection.
        """
        info = self.detect()
        return "yast" if info["version_id"].startswith("15.") else "agama"

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _parse_os_release(text: str) -> dict[str, str]:
        """
        Parse the contents of /etc/os-release into a plain dict.

        FIX: original regex r'(\\w+)="?([^"\\n]+)' captured the trailing
        double-quote into the value.  We now split on ``=`` and strip quotes
        explicitly.

        Args:
            text: Raw text content of /etc/os-release.
        """
        result: dict[str, str] = {}
        for line in text.splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, raw_val = line.partition("=")
            # Strip surrounding single or double quotes
            value = raw_val.strip().strip('"').strip("'")
            result[key.strip()] = value
        return result

    def _check_yast(self) -> bool:
        """
        Return True if the ``yast2`` binary is on PATH.

        Architecture Section 6: YaST for Leap 15.x.
        Architecture Section 11: ``which yast2``.
        """
        path = shutil.which("yast2")
        found = path is not None
        logger.debug("YaST binary: %s", path or "not found")
        return found

    def _check_cockpit(self) -> bool:
        """
        Return True if Cockpit is installed or running.

        Checks in order:
        1. ``cockpit.socket`` is enabled (preferred indicator).
        2. ``cockpit`` service is active (fallback).

        Architecture Section 6: Cockpit for Leap 16+.
        Architecture Section 11: ``systemctl status cockpit``.
        """
        for check_args in (
            ["systemctl", "is-enabled", "cockpit.socket"],
            ["systemctl", "is-active", "cockpit"],
        ):
            try:
                result = subprocess.run(
                    check_args,
                    capture_output=True,
                    text=True,
                    timeout=5,
                )
                if result.returncode == 0:
                    logger.debug("Cockpit detected via: %s", " ".join(check_args))
                    return True
            except (subprocess.TimeoutExpired, FileNotFoundError) as exc:
                logger.debug("Cockpit check skipped (%s): %s", check_args[1], exc)

        logger.debug("Cockpit not detected")
        return False

    def _check_agama(self) -> bool:
        """
        Return True if the Agama installer service unit exists on this system.

        FIX: original used ``systemctl status agama.service`` and checked
        returncode == 0, but ``status`` returns 0 only when the unit is
        *active*.  ``systemctl cat`` exits 0 if the unit *file exists*,
        whether or not it is running — correct for an installed-but-idle probe.

        Architecture Section 6: Agama installer only.
        Architecture Section 11: ``systemctl status agama.service``.
        """
        try:
            result = subprocess.run(
                ["systemctl", "cat", "agama.service"],
                capture_output=True,
                text=True,
                timeout=5,
            )
            if result.returncode == 0:
                logger.debug("Agama service unit present")
                return True
        except (subprocess.TimeoutExpired, FileNotFoundError) as exc:
            logger.debug("Agama check failed: %s", exc)

        logger.debug("Agama installer not present (expected post-install)")
        return False
