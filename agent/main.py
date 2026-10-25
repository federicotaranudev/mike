"""Entry point: API + scheduler."""
from __future__ import annotations
import uvicorn

from .api import app  # noqa: F401
from .config import settings
from .scheduler import start


def main() -> None:
    start()
    uvicorn.run("agent.api:app", host=settings.host, port=settings.port)


if __name__ == "__main__":
    main()
