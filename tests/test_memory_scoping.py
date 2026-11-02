from __future__ import annotations

import unittest
from unittest.mock import patch

from chroma_memory import AliceMemory


class FakeCollection:
    def __init__(self) -> None:
        self.upserts = []
        self.last_query = None

    def upsert(self, **kwargs):
        self.upserts.append(kwargs)

    def query(self, **kwargs):
        self.last_query = kwargs
        return {
            "ids": [[]],
            "documents": [[]],
            "metadatas": [[]],
            "distances": [[]],
        }


class MemoryScopingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.memory = AliceMemory.__new__(AliceMemory)
        self.memory.collection = FakeCollection()

    def test_private_ids_are_distinct_per_owner(self):
        first = AliceMemory.make_id(
            "same fact", "web", "general", "user", "discord:one"
        )
        second = AliceMemory.make_id(
            "same fact", "web", "general", "user", "discord:two"
        )
        self.assertNotEqual(first, second)

    def test_scope_changes_record_id(self):
        private = AliceMemory.make_id(
            "same fact", "web", "general", "user", "discord:one"
        )
        shared = AliceMemory.make_id(
            "same fact", "web", "general", "shared", None
        )
        self.assertNotEqual(private, shared)

    def test_store_protects_visibility_metadata(self):
        result = self.memory.store(
            content="private fact",
            source="web",
            category="general",
            scope="user",
            owner_id="discord:one",
            metadata={
                "owner_id": "discord:two",
                "scope": "shared",
                "source": "spoofed",
                "category": "spoofed",
                "stored_at": "spoofed",
                "note": "retained",
            },
        )
        metadata = self.memory.collection.upserts[0]["metadatas"][0]
        self.assertEqual(metadata["owner_id"], "discord:one")
        self.assertEqual(metadata["scope"], "user")
        self.assertEqual(metadata["source"], "web")
        self.assertEqual(metadata["category"], "general")
        self.assertNotEqual(metadata["stored_at"], "spoofed")
        self.assertEqual(metadata["note"], "retained")
        self.assertEqual(result["id"], self.memory.collection.upserts[0]["ids"][0])

    def test_user_search_includes_only_private_owner_shared_and_system(self):
        self.memory.search("fact", owner_id="discord:one")
        where = self.memory.collection.last_query["where"]
        scopes = [item.get("scope") for item in where["$or"][:2]]
        self.assertEqual(scopes, ["shared", "system"])
        private_filter = where["$or"][2]["$and"]
        self.assertEqual(private_filter, [
            {"scope": "user"},
            {"owner_id": "discord:one"},
        ])

    def test_search_without_owner_never_queries_private_scope(self):
        self.memory.search("fact")
        where = self.memory.collection.last_query["where"]
        self.assertEqual(where, {
            "$or": [{"scope": "shared"}, {"scope": "system"}]
        })

    def test_legacy_records_without_scope_are_not_in_visibility_filter(self):
        self.memory.search("old note", owner_id="discord:one")
        where = self.memory.collection.last_query["where"]
        serialized = repr(where)
        self.assertNotIn("legacy_unclassified", serialized)
        self.assertNotIn("scope': None", serialized)


if __name__ == "__main__":
    unittest.main()
