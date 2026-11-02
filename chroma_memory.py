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
        scope: str = "legacy_unclassified",
        owner_id: str | None = None,
    ) -> str:
        """
        Generate a deterministic ID.

        The same content/source/category combination produces
        the same ID, making upsert safe and preventing duplicates.
        """

        raw = (
            str(scope)
            + "\n"
            + str(owner_id or "")
            + "\n"
            + str(source)
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
        scope: str = "user",
        owner_id: str | None = None,
    ) -> dict[str, Any]:

        content = str(content).strip()

        if not content:
            raise ValueError("Memory content cannot be empty")

        scope = str(scope).strip()
        if scope not in {"user", "shared", "system"}:
            raise ValueError("Memory scope must be user, shared, or system")

        if scope == "user":
            owner_id = str(owner_id or "").strip()
            if not owner_id:
                raise ValueError("User-scoped memory requires an owner_id")
        else:
            owner_id = None

        memory_id = self.make_id(
            content, source, category, scope, owner_id
        )

        # Descriptive metadata is retained, but cannot override ownership,
        # scope, category, provenance, or timestamp fields.
        record_metadata: dict[str, Any] = {}
        protected = {"scope", "owner_id", "source", "category", "stored_at"}
        if metadata:
            for key, value in metadata.items():
                key = str(key)
                if key in protected or value is None:
                    continue
                if isinstance(value, (str, int, float, bool)):
                    record_metadata[key] = value
                else:
                    record_metadata[key] = str(value)

        record_metadata.update({
            "source": str(source),
            "category": str(category),
            "scope": scope,
            "stored_at": datetime.now(timezone.utc).isoformat(),
        })
        if owner_id is not None:
            record_metadata["owner_id"] = owner_id

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
        owner_id: str | None = None,
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

        visible_scopes: list[dict[str, Any]] = [
            {"scope": "shared"},
            {"scope": "system"},
        ]
        if owner_id:
            visible_scopes.append({
                "$and": [
                    {"scope": "user"},
                    {"owner_id": str(owner_id)},
                ]
            })

        visibility = {"$or": visible_scopes}
        if category:
            kwargs["where"] = {
                "$and": [
                    visibility,
                    {"category": str(category)},
                ]
            }
        else:
            kwargs["where"] = visibility

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