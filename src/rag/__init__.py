"""
RAG Module — Pluggable Retrieval Backends
Architecture v1.0 Section 5: RAG Plug-and-Play Interface Contract
"""

from src.core.interfaces.base_rag import Document, RetrievedChunk

__all__ = ["Document", "RetrievedChunk"]
