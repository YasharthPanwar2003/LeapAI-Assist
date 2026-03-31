from __future__ import annotations

import shutil
import subprocess
from dataclasses import dataclass, field

from src.logger import get_logger

logger = get_logger(__name__)


@dataclass
class SystemState:
    """Snapshot of live system state used for Zone 2 context building."""

    failed_services: list[str] = field(default_factory=list)
    enabled_repos: list[str] = field(default_factory=list)
    pending_updates: int = 0
    memory_available_gb: float = 0.0
    disk_usage_percent: float = 0.0


class SystemContext:
    """
    Probes live openSUSE system state for context injection.

    Usage::

        ctx   = SystemContext()
        state = ctx.probe()
        text  = ctx.format_zone2(state)
        # inject `text` as Zone 2 of the 5-zone prompt
    """

    def __init__(self) -> None:
        self._cache: SystemState | None = None

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def probe(self, force_refresh: bool = False) -> SystemState:
        """
        Probe the live system and return a ``SystemState`` snapshot.

        Args:
            force_refresh: Ignore cached result and re-probe.

        Architecture Section 3: Zone 2 read once per session.
        Architecture Section 11: Context probe commands.
        """
        if self._cache and not force_refresh:
            return self._cache

        state = SystemState()
        state.failed_services = self._get_failed_services()
        state.enabled_repos = self._get_enabled_repos()
        state.pending_updates = self._get_pending_updates()
        state.memory_available_gb = self._get_memory_available_gb()
        state.disk_usage_percent = self._get_disk_usage_percent()

        self._cache = state
        logger.info(
            "System context probed: failed=%d repos=%d updates=%d mem=%.1fGB disk=%.0f%%",
            len(state.failed_services),
            len(state.enabled_repos),
            state.pending_updates,
            state.memory_available_gb,
            state.disk_usage_percent,
        )
        return state

    def format_zone2(self, state: SystemState | None = None) -> str:
        """
        Format a ``SystemState`` as the Zone 2 context string (40-80 tokens).

        Args:
            state: Pre-probed state; calls ``probe()`` if ``None``.

        Returns:
            A short, token-efficient multi-line string for prompt injection.

        Architecture Section 3: Zone 2 is 40-80 tokens.
        """
        if state is None:
            state = self.probe()

        lines: list[str] = []

        if state.failed_services:
            joined = ", ".join(state.failed_services[:5])
            lines.append(f"Failed services: {joined}")

        if state.enabled_repos:
            lines.append(f"Enabled repos: {len(state.enabled_repos)}")

        if state.pending_updates > 0:
            lines.append(f"Pending updates: {state.pending_updates}")

        if state.memory_available_gb > 0:
            lines.append(f"Memory available: {state.memory_available_gb:.1f} GB")

        if state.disk_usage_percent > 0:
            lines.append(f"Root disk usage: {state.disk_usage_percent:.0f}%")

        if not lines:
            return "System state: Normal (no issues detected)"

        return "\n".join(lines)

    # ------------------------------------------------------------------
    # Internal probes
    # ------------------------------------------------------------------

    def _get_failed_services(self) -> list[str]:
        """
        Return names of failed systemd units (up to 10).

        Command: ``systemctl --failed --no-pager --plain --no-legend``
        Architecture Section 11.
        """
        services: list[str] = []
        try:
            result = subprocess.run(
                ["systemctl", "--failed", "--no-pager", "--plain", "--no-legend"],
                capture_output=True,
                text=True,
                timeout=10,
            )
            if result.returncode == 0 and result.stdout.strip():
                for line in result.stdout.splitlines():
                    parts = line.split()
                    if parts:
                        services.append(parts[0])
        except (subprocess.TimeoutExpired, FileNotFoundError) as exc:
            logger.warning("Failed-services probe error: %s", exc)

        return services[:10]

    def _get_enabled_repos(self) -> list[str]:
        """
        Return alias names of all enabled zypper repositories.

        FIX: Original code used ``zypper repos --export`` which writes to a
        FILE (not stdout) and requires a filename argument.
        Correct command: ``zypper lr --no-refresh`` → tabular stdout.

        Output columns (space-separated): # | Alias | Name | Enabled | …
        We filter rows where the Enabled column is "Yes".

        Architecture Section 11.
        """
        if not shutil.which("zypper"):
            logger.debug("zypper not found — skipping repo probe")
            return []

        repos: list[str] = []
        try:
            result = subprocess.run(
                ["zypper", "lr", "--no-refresh"],
                capture_output=True,
                text=True,
                timeout=30,
            )
            if result.returncode != 0:
                logger.debug("zypper lr exited %d", result.returncode)
                return repos

            # Table format:
            # #  | Alias        | Name          | Enabled | Refresh | Priority
            # ---+--------------+---------------+---------+---------+---------
            # 1  | repo-oss     | Main Repo     | Yes     | Yes     | 99
            for line in result.stdout.splitlines():
                # Skip header / separator lines
                stripped = line.strip()
                if not stripped or stripped.startswith("#") or stripped.startswith("-"):
                    continue
                # Real data rows start with a digit (the row number)
                parts = [p.strip() for p in stripped.split("|")]
                if len(parts) >= 4 and parts[0].isdigit():
                    alias = parts[1]  # column 2
                    enabled = parts[3]  # column 4
                    if enabled.lower() == "yes" and alias:
                        repos.append(alias)

        except (subprocess.TimeoutExpired, FileNotFoundError) as exc:
            logger.warning("Repo probe error: %s", exc)

        return repos

    def _get_pending_updates(self) -> int:
        """
        Return the number of available package updates.

        FIX: Original used ``zypper lu --best-effort`` which is not a valid
        zypper flag and exits with an error.
        Correct command: ``zypper lu`` (list-updates).

        Architecture Section 11.
        """
        if not shutil.which("zypper"):
            logger.debug("zypper not found — skipping update probe")
            return 0

        try:
            result = subprocess.run(
                ["zypper", "lu"],
                capture_output=True,
                text=True,
                timeout=60,
            )
            if result.returncode not in (0, 100):
                # 100 = "updates available" in some zypper versions
                logger.debug("zypper lu exited %d", result.returncode)
                return 0

            # Data rows contain "|" and the first non-space char is a digit
            count = sum(
                1
                for line in result.stdout.splitlines()
                if "|" in line and line.strip() and line.strip()[0].isdigit()
            )
            return count

        except (subprocess.TimeoutExpired, FileNotFoundError) as exc:
            logger.warning("Update probe error: %s", exc)
            return 0

    # ------------------------------------------------------------------
    # Bonus probes (populated but not in Zone 2 by default)
    # ------------------------------------------------------------------

    def _get_memory_available_gb(self) -> float:
        """
        Return available memory in GiB from ``/proc/meminfo``.
        Returns 0.0 if unavailable.
        """
        try:
            with open("/proc/meminfo") as f:
                for line in f:
                    if line.startswith("MemAvailable:"):
                        kb = int(line.split()[1])
                        return round(kb / 1_048_576, 1)
        except (OSError, ValueError, IndexError):
            pass
        return 0.0

    def _get_disk_usage_percent(self, path: str = "/") -> float:
        """
        Return disk usage percentage for *path*.
        Returns 0.0 if unavailable.
        """
        try:
            import shutil as _shutil

            total, used, _free = _shutil.disk_usage(path)
            return round(used / total * 100, 1) if total else 0.0
        except OSError:
            return 0.0
