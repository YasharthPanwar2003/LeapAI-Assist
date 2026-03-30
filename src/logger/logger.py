import logging
import sys
from pathlib import Path


def get_logger(name: str, log_file: Path | None = None) -> logging.Logger:
    """Get a named logger. Use get_logger(__name__) in every module."""

    logger = logging.getLogger(name)

    if logger.handlers:
        return logger

    logger.setLevel(logging.DEBUG)
    logger.propagate = False

    fmt = logging.Formatter(
        "%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
        datefmt="%H:%M:%S",
    )

    console = logging.StreamHandler(sys.stdout)
    console.setFormatter(fmt)
    logger.addHandler(console)

    if log_file:
        try:
            log_file.parent.mkdir(parents=True, exist_ok=True)
            fh = logging.FileHandler(log_file, encoding="utf-8")
            fh.setFormatter(fmt)
            logger.addHandler(fh)
        except (OSError, PermissionError):
            logger.warning("Cannot write log file: %s", log_file)

    return logger


app_logger = get_logger("LeapAI", log_file=Path("logs/app.log"))
