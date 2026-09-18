"""
Alice Web AI

Copyright (C) 2026 Override Development

This file is part of Alice Web AI.

Alice Web AI is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Alice Web AI is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Alice Web AI. If not, see
<https://www.gnu.org/licenses/>.

Alice Web AI - Chroma memory backend

Local persistent semantic memory for Alice.

Copyright (C) 2026 Override Development
"""

from __future__ import annotations

import hashlib
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import chromadb


BASE_DIR = Path(__file__).resolve().parent
CHROMA_PATH = BASE_DIR / "memory" / "chroma"

COLLECTION_NAME = "alice_memory"


class AliceMemory:
    def __init__(self, path: Path | str = CHROMA_PATH) -> None:
        self.path = Path(path)
        self.path.mkdir(parents=True, exist_ok=True)

        self.client = chromadb.PersistentClient(
            path=str(self.path)
        )

        self.collection = self.client.get_or_create_collection(
            name=COLLECTION_NAME,
            metadata={
                "description": "Alice long-term semantic memory"
            }
        )

    @staticmethod
    def make_id(
        content: str,
        source: str = "unknown",
        category: str = "general",
    ) -> str:
        """
        Generate a deterministic ID.

        The same content/source/category combination produces
        the same ID, making upsert safe and preventing duplicates.
        """

        raw = (
            str(source)
            + "\n"
            + str(category)
            + "\n"
            + str(content)
        )

        return hashlib.sha256(
            raw.encode("utf-8")
        ).hexdigest()

    def store(
        self,
        content: str,
        source: str = "conversation",
        category: str = "general",
        metadata: dict[str, Any] | None = None,
        memory_id: str | None = None,
    ) -> dict[str, Any]:

        content = str(content).strip()

        if not content:
            raise ValueError("Memory content cannot be empty")

        memory_id = memory_id or self.make_id(
            content,
            source,
            category,
        )

        record_metadata: dict[str, Any] = {
            "source": str(source),
            "category": str(category),
            "stored_at": datetime.now(
                timezone.utc
            ).isoformat(),
        }

        if metadata:
            for key, value in metadata.items():
                if value is None:
                    continue

                # Chroma metadata values should remain scalar.
                if isinstance(value, (str, int, float, bool)):
                    record_metadata[str(key)] = value
                else:
                    record_metadata[str(key)] = str(value)

        self.collection.upsert(
            ids=[memory_id],
            documents=[content],
            metadatas=[record_metadata],
        )

        return {
            "id": memory_id,
            "content": content,
            "metadata": record_metadata,
        }

    def search(
        self,
        query: str,
        count: int = 5,
        category: str | None = None,
    ) -> list[dict[str, Any]]:

        query = str(query).strip()

        if not query:
            raise ValueError("Memory query cannot be empty")

        count = max(1, min(int(count), 10))

        kwargs: dict[str, Any] = {
            "query_texts": [query],
            "n_results": count,
            "include": [
                "documents",
                "metadatas",
                "distances",
            ],
        }

        if category:
            kwargs["where"] = {
                "category": str(category)
            }

        results = self.collection.query(**kwargs)

        ids = results.get("ids", [[]])[0]
        documents = results.get("documents", [[]])[0]
        metadatas = results.get("metadatas", [[]])[0]
        distances = results.get("distances", [[]])[0]

        memories: list[dict[str, Any]] = []

        for index, memory_id in enumerate(ids):
            memories.append({
                "id": memory_id,
                "content": (
                    documents[index]
                    if index < len(documents)
                    else ""
                ),
                "metadata": (
                    metadatas[index]
                    if index < len(metadatas)
                    else {}
                ),
                "distance": (
                    distances[index]
                    if index < len(distances)
                    else None
                ),
            })

        return memories

    def delete(self, memory_id: str) -> None:
        self.collection.delete(
            ids=[str(memory_id)]
        )

    def count(self) -> int:
        return self.collection.count()

    def status(self) -> dict[str, Any]:
        return {
            "path": str(self.path),
            "collection": COLLECTION_NAME,
            "count": self.count(),
        }


_memory = AliceMemory()


def get_memory() -> AliceMemory:
    return _memory