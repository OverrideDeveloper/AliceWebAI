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

Alice Discord Bot

Discord frontend for Alice Web AI.

Alice remains responsible for:
    - conversation handling
    - behavioral overrides
    - history
    - Ollama communication
    - tools
    - future memory systems

This bot is intentionally a thin Discord adapter.

Python 3.8+
discord.py 2.7+
"""

from __future__ import annotations

import asyncio
import logging
import os
from typing import Optional

import aiohttp
import discord
from discord import app_commands
from discord.ext import commands


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

DISCORD_TOKEN = os.getenv("ALICE_DISCORD_TOKEN")

ALICE_URL = os.getenv(
    "ALICE_URL",
    "http://127.0.0.1:8080",
)

ALICE_MESSAGE_ENDPOINT = (
    ALICE_URL.rstrip("/") + "/api/message"
)

ALICE_STATUS_ENDPOINT = (
    ALICE_URL.rstrip("/") + "/api/status"
)

# How long Discord-side HTTP requests may wait for Alice.
#
# Your Ollama client currently allows 120 seconds, so this gives Alice
# a little additional room to finish before Discord gives up.
ALICE_TIMEOUT = float(
    os.getenv("ALICE_TIMEOUT", "135")
)

# Optional development guild.
#
# Setting this causes commands to sync immediately to one guild rather
# than waiting for global command propagation.
#
# Example:
#   ALICE_DISCORD_GUILD_ID=123456789012345678
#
DISCORD_GUILD_ID = os.getenv(
    "ALICE_DISCORD_GUILD_ID"
)

# Discord messages have a maximum length. Alice responses longer than
# this are split into multiple messages.
DISCORD_MESSAGE_LIMIT = 2000


# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] [%(levelname)s] %(name)s: %(message)s",
)

log = logging.getLogger("alice-discord")


# ---------------------------------------------------------------------------
# Discord bot
# ---------------------------------------------------------------------------

class AliceBot(commands.Bot):
    def __init__(self) -> None:
        intents = discord.Intents.default()

        # We intentionally do NOT enable message_content.
        #
        # Alice is driven through slash/application commands rather than
        # reading arbitrary Discord channel messages.
        super().__init__(
            command_prefix="!",
            intents=intents,
        )

        self.http_session: Optional[aiohttp.ClientSession] = None

    async def setup_hook(self) -> None:
        self.http_session = aiohttp.ClientSession(
            timeout=aiohttp.ClientTimeout(
                total=ALICE_TIMEOUT
            )
        )

        if DISCORD_GUILD_ID:
            guild = discord.Object(
                id=int(DISCORD_GUILD_ID)
            )

            self.tree.copy_global_to(guild=guild)

            synced = await self.tree.sync(
                guild=guild
            )

            log.info(
                "Synced %d commands to guild %s",
                len(synced),
                DISCORD_GUILD_ID,
            )

        else:
            synced = await self.tree.sync()

            log.info(
                "Synced %d global Discord commands",
                len(synced),
            )

    async def close(self) -> None:
        if self.http_session is not None:
            await self.http_session.close()

        await super().close()

    async def on_ready(self) -> None:
        if self.user is None:
            return

        log.info(
            "Alice Discord bot connected as %s (%s)",
            self.user,
            self.user.id,
        )

        log.info(
            "Connected to %d Discord guild(s)",
            len(self.guilds),
        )


bot = AliceBot()


# ---------------------------------------------------------------------------
# Alice HTTP API
# ---------------------------------------------------------------------------

async def alice_status() -> dict:
    """
    Check whether the existing Alice Web AI server is reachable.
    """

    if bot.http_session is None:
        raise RuntimeError(
            "HTTP session has not been initialized"
        )

    async with bot.http_session.get(
        ALICE_STATUS_ENDPOINT
    ) as response:

        if response.status != 200:
            text = await response.text()

            raise RuntimeError(
                f"Alice status returned HTTP "
                f"{response.status}: {text}"
            )

        return await response.json()


async def ask_alice(
    message: str,
    *,
    gaslighting: bool = False,
    hallucination: bool = False,
    overconfidence: bool = False,
    sycophancy: bool = False,
) -> str:
    """
    Send a message through the existing Alice Web AI HTTP interface.
    """

    if bot.http_session is None:
        raise RuntimeError(
            "HTTP session has not been initialized"
        )

    payload = {
        "message": message,
        "behaviors": {
            "gaslighting": gaslighting,
            "hallucination": hallucination,
            "overconfidence": overconfidence,
            "sycophancy": sycophancy,
        },
    }

    async with bot.http_session.post(
        ALICE_MESSAGE_ENDPOINT,
        json=payload,
    ) as response:

        if response.status != 200:
            try:
                data = await response.json()

                error = data.get(
                    "error",
                    f"HTTP {response.status}",
                )

            except Exception:
                error = await response.text()

            raise RuntimeError(
                f"Alice returned an error: {error}"
            )

        data = await response.json()

    result = data.get("response")

    if not isinstance(result, str):
        raise RuntimeError(
            "Alice returned an invalid response"
        )

    return result


# ---------------------------------------------------------------------------
# Discord message helpers
# ---------------------------------------------------------------------------

def split_discord_message(
    text: str,
    limit: int = DISCORD_MESSAGE_LIMIT,
) -> list[str]:
    """
    Split a long Alice response into Discord-safe chunks.

    Attempts to split at newlines or spaces before resorting to a hard
    split.
    """

    if len(text) <= limit:
        return [text]

    chunks: list[str] = []

    remaining = text

    while len(remaining) > limit:
        split_at = remaining.rfind(
            "\n",
            0,
            limit,
        )

        if split_at < limit // 2:
            split_at = remaining.rfind(
                " ",
                0,
                limit,
            )

        if split_at < limit // 2:
            split_at = limit

        chunk = remaining[:split_at].rstrip()

        if chunk:
            chunks.append(chunk)

        remaining = remaining[split_at:].lstrip()

    if remaining:
        chunks.append(remaining)

    return chunks


async def send_alice_response(
    interaction: discord.Interaction,
    response: str,
) -> None:
    """
    Send Alice's response, splitting it when necessary.
    """

    chunks = split_discord_message(response)

    if not chunks:
        chunks = ["Alice returned an empty response."]

    await interaction.followup.send(
        chunks[0]
    )

    for chunk in chunks[1:]:
        await interaction.followup.send(
            chunk
        )


# ---------------------------------------------------------------------------
# /alice
# ---------------------------------------------------------------------------

@bot.tree.command(
    name="alice",
    description="Talk to Alice.",
)
@app_commands.describe(
    message="What would you like to say to Alice?"
)
async def alice_command(
    interaction: discord.Interaction,
    message: str,
) -> None:
    """
    Main Alice interaction.

    Example:

        /alice message: Tell me about the current state of Linux.
    """

    message = message.strip()

    if not message:
        await interaction.response.send_message(
            "Message cannot be empty.",
            ephemeral=True,
        )

        return

    await interaction.response.defer(
        thinking=True
    )

    try:
        response = await ask_alice(
            message
        )

        await send_alice_response(
            interaction,
            response,
        )

    except asyncio.TimeoutError:
        await interaction.followup.send(
            "Alice timed out while waiting for the backend."
        )

    except aiohttp.ClientError as exc:
        log.exception(
            "Unable to reach Alice"
        )

        await interaction.followup.send(
            "I could not reach Alice Web AI.\n"
            f"Backend error: {exc}"
        )

    except Exception as exc:
        log.exception(
            "Unexpected Alice error"
        )

        await interaction.followup.send(
            "Alice encountered an unexpected error.\n"
            f"Error: {exc}"
        )


# ---------------------------------------------------------------------------
# /alice-status
# ---------------------------------------------------------------------------

@bot.tree.command(
    name="alice-status",
    description="Check whether Alice Web AI is available.",
)
async def alice_status_command(
    interaction: discord.Interaction,
) -> None:

    await interaction.response.defer(
        ephemeral=True
    )

    try:
        status = await alice_status()

        backend_status = status.get(
            "status",
            "unknown",
        )

        model = status.get(
            "model",
            "unknown",
        )

        await interaction.followup.send(
            "Alice Web AI is online.\n"
            f"Status: {backend_status}\n"
            f"Model: {model}",
            ephemeral=True,
        )

    except Exception as exc:
        log.exception(
            "Alice status check failed"
        )

        await interaction.followup.send(
            "Alice Web AI is unavailable.\n"
            f"Error: {exc}",
            ephemeral=True,
        )


# ---------------------------------------------------------------------------
# /alice-reset
# ---------------------------------------------------------------------------

@bot.tree.command(
    name="alice-reset",
    description="Clear Alice's current conversation history.",
)
async def alice_reset_command(
    interaction: discord.Interaction,
) -> None:
    """
    Reset Alice through the existing Alice command interface.

    This intentionally uses Alice's existing /history-clear command
    rather than implementing a second history system in Python.
    """

    await interaction.response.defer(
        ephemeral=True
    )

    try:
        response = await ask_alice(
            "/history-clear"
        )

        await interaction.followup.send(
            response,
            ephemeral=True,
        )

    except Exception as exc:
        log.exception(
            "Alice reset failed"
        )

        await interaction.followup.send(
            "Unable to reset Alice.\n"
            f"Error: {exc}",
            ephemeral=True,
        )


# ---------------------------------------------------------------------------
# /alice-history
# ---------------------------------------------------------------------------

@bot.tree.command(
    name="alice-history",
    description="Show Alice's current conversation history.",
)
async def alice_history_command(
    interaction: discord.Interaction,
) -> None:
    """
    Retrieve Alice's existing history.

    This is ephemeral because the conversation may contain private
    material.
    """

    await interaction.response.defer(
        ephemeral=True
    )

    try:
        response = await ask_alice(
            "/history"
        )

        chunks = split_discord_message(
            response
        )

        for chunk in chunks:
            await interaction.followup.send(
                chunk,
                ephemeral=True,
            )

    except Exception as exc:
        log.exception(
            "Unable to retrieve Alice history"
        )

        await interaction.followup.send(
            "Unable to retrieve Alice history.\n"
            f"Error: {exc}",
            ephemeral=True,
        )


# ---------------------------------------------------------------------------
# /alice-behavior
# ---------------------------------------------------------------------------

behavior_group = app_commands.Group(
    name="alice-behavior",
    description="Control Alice's behavioral overrides.",
)


@behavior_group.command(
    name="ask",
    description="Ask Alice with selected behavioral protections.",
)
@app_commands.describe(
    message="What would you like to ask Alice?",
    hallucination="Enable anti-hallucination behavior.",
    overconfidence="Enable confidence calibration.",
    sycophancy="Enable independent assessment.",
    gaslighting="Enable conversation-history claim checking.",
)
async def alice_behavior_ask(
    interaction: discord.Interaction,
    message: str,
    hallucination: bool = False,
    overconfidence: bool = False,
    sycophancy: bool = False,
    gaslighting: bool = False,
) -> None:

    message = message.strip()

    if not message:
        await interaction.response.send_message(
            "Message cannot be empty.",
            ephemeral=True,
        )

        return

    await interaction.response.defer(
        thinking=True
    )

    try:
        response = await ask_alice(
            message,
            gaslighting=gaslighting,
            hallucination=hallucination,
            overconfidence=overconfidence,
            sycophancy=sycophancy,
        )

        await send_alice_response(
            interaction,
            response,
        )

    except Exception as exc:
        log.exception(
            "Behavior-controlled Alice request failed"
        )

        await interaction.followup.send(
            "Alice encountered an error.\n"
            f"Error: {exc}"
        )


bot.tree.add_command(
    behavior_group
)


# ---------------------------------------------------------------------------
# Startup
# ---------------------------------------------------------------------------

def main() -> None:
    if not DISCORD_TOKEN:
        raise RuntimeError(
            "ALICE_DISCORD_TOKEN environment variable is not set."
        )

    log.info(
        "Starting Alice Discord bot..."
    )

    log.info(
        "Alice backend: %s",
        ALICE_URL,
    )

    bot.run(
        DISCORD_TOKEN,
        log_handler=None,
    )


if __name__ == "__main__":
    main()