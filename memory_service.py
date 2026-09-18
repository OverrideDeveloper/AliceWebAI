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

Alice Web AI - Local Chroma memory service

HTTP bridge between Alice's Lua/Luvit runtime and ChromaDB.

Copyright (C) 2026 Override Development
"""

from __future__ import annotations

import json
from http.server import (
    BaseHTTPRequestHandler,
    ThreadingHTTPServer,
)
from typing import Any

from chroma_memory import get_memory


HOST = "127.0.0.1"
PORT = 8090


def json_response(
    handler: BaseHTTPRequestHandler,
    status: int,
    payload: dict[str, Any],
) -> None:

    body = json.dumps(
        payload,
        ensure_ascii=True,
    ).encode("utf-8")

    handler.send_response(status)

    handler.send_header(
        "Content-Type",
        "application/json; charset=utf-8",
    )

    handler.send_header(
        "Content-Length",
        str(len(body)),
    )

    handler.send_header(
        "Cache-Control",
        "no-cache",
    )

    handler.end_headers()
    handler.wfile.write(body)


class MemoryHandler(BaseHTTPRequestHandler):

    def log_message(self, format: str, *args: Any) -> None:
        print(
            "[MEMORY] "
            + format % args
        )

    def read_json(self) -> dict[str, Any]:
        length = int(
            self.headers.get(
                "Content-Length",
                "0",
            )
        )

        if length <= 0:
            return {}

        raw = self.rfile.read(length)

        return json.loads(
            raw.decode("utf-8")
        )

    def do_GET(self) -> None:

        if self.path == "/memory/status":
            try:
                memory = get_memory()

                json_response(
                    self,
                    200,
                    {
                        "status": "ok",
                        **memory.status(),
                    },
                )

            except Exception as exc:
                json_response(
                    self,
                    500,
                    {
                        "error": str(exc)
                    },
                )

            return

        json_response(
            self,
            404,
            {
                "error": "Not found"
            },
        )

    def do_POST(self) -> None:

        try:
            data = self.read_json()

        except Exception as exc:
            json_response(
                self,
                400,
                {
                    "error": (
                        "Invalid JSON: "
                        + str(exc)
                    )
                },
            )
            return

        try:

            if self.path == "/memory/search":

                query = data.get("query", "")
                count = data.get("count", 5)
                category = data.get("category")

                results = get_memory().search(
                    query=query,
                    count=count,
                    category=category,
                )

                json_response(
                    self,
                    200,
                    {
                        "results": results
                    },
                )

                return

            if self.path == "/memory/store":

                content = data.get(
                    "content",
                    "",
                )

                source = data.get(
                    "source",
                    "conversation",
                )

                category = data.get(
                    "category",
                    "general",
                )

                metadata = data.get(
                    "metadata",
                    {},
                )

                memory_id = data.get(
                    "id"
                )

                result = get_memory().store(
                    content=content,
                    source=source,
                    category=category,
                    metadata=metadata,
                    memory_id=memory_id,
                )

                json_response(
                    self,
                    200,
                    {
                        "stored": result
                    },
                )

                return

            if self.path == "/memory/delete":

                memory_id = data.get("id")

                if not memory_id:
                    json_response(
                        self,
                        400,
                        {
                            "error":
                                "Memory id is required"
                        },
                    )
                    return

                get_memory().delete(
                    memory_id
                )

                json_response(
                    self,
                    200,
                    {
                        "deleted": memory_id
                    },
                )

                return

            json_response(
                self,
                404,
                {
                    "error": "Not found"
                },
            )

        except Exception as exc:

            print(
                "[MEMORY ERROR] "
                + str(exc)
            )

            json_response(
                self,
                500,
                {
                    "error": str(exc)
                },
            )


def main() -> None:

    server = ThreadingHTTPServer(
        (HOST, PORT),
        MemoryHandler,
    )

    print(
        "[INFO] Alice Chroma memory service "
        f"running on http://{HOST}:{PORT}"
    )

    print(
        "[INFO] Persistent memory: "
        f"{get_memory().path}"
    )

    try:
        server.serve_forever()

    except KeyboardInterrupt:
        print(
            "\n[INFO] Memory service shutting down..."
        )

    finally:
        server.server_close()


if __name__ == "__main__":
    main()