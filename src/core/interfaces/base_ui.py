from __future__ import annotations

from collections.abc import AsyncGenerator


class UIBase:
    """
    Base class for all UI backends — Textual TUI, Cockpit, future Qt.
    Subclass this and override the methods you need.
    """

    async def display_message(self, role: str, content: str) -> None:
        """Show a complete message. role = user | assistant | system"""
        raise NotImplementedError

    async def stream_response(self, tokens: AsyncGenerator[str]) -> None:
        """Render LLM tokens as they stream in."""
        raise NotImplementedError

    def update_status(self, status: str) -> None:
        """Update status bar e.g. 'Thinking...', 'Ready'"""
        raise NotImplementedError

    def close(self) -> None:
        """Clean up resources on exit."""
        pass  # default: do nothing
