"""Interface contracts — swap any backend without touching other code."""

from .base_ingester import FetchedDoc
from .base_rag import Document, RetrievedChunk
from .base_ui import UIBase

__all__ = ["Document", "RetrievedChunk", "FetchedDoc", "UIBase"]


#
