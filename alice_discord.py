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

Discord interaction identity is passed to Alice as request metadata.

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

ALICE_TIMEOUT = float(
    os.getenv("ALICE_TIMEOUT", "135")
)

DISCORD_GUILD_ID = os.getenv(
    "ALICE_DISCORD_GUILD_ID"
)

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

        # Slash/application commands do not require message_content.
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
# Discord identity
# ---------------------------------------------------------------------------

def get_discord_identity(
    interaction: discord.Interaction,
) -> dict:
    """
    Build the identity metadata Alice receives for this request.

    Discord has authenticated the interaction at the platform level.
    The Lua backend receives this as identity metadata.

    This is identity propagation, not a replacement for eventual
    Cloudflare Access authentication.
    """

    user = interaction.user

    display_name = getattr(
        user,
        "display_name",
        None,
    )

    if not isinstance(display_name, str) or not display_name:
        display_name = user.name

    return {
        "provider": "discord",

        "user_id": str(
            user.id
        ),

        "name": display_name,

        # Standard Discord interactions do not expose the user's
        # email address to the bot.
        "email": None,

        "authenticated": True,

        "anonymous": False,
    }


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
    identity: Optional[dict] = None,
    gaslighting: bool = False,
    hallucination: bool = False,
    overconfidence: bool = False,
    sycophancy: bool = False,
) -> str:
    """
    Send a message through the existing Alice Web AI HTTP interface.

    The optional identity object identifies the Discord user who
    submitted the interaction.
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

    if identity is not None:
        payload["identity"] = identity

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


def build_user_turn(
    identity: dict,
    message: str,
) -> str:
    """
    Build the visible user side of the interaction.

    This does not attempt to impersonate the Discord user.

    The interaction response remains authored by the bot, while the
    user's actual Discord identity is represented by the interaction
    metadata and the visible name/message presentation.
    """

    name = str(
        identity.get(
            "name",
            "Unknown User",
        )
    )

    return (
        f"**{name}:**\n"
        f"{message}"
    )


def build_alice_turn(
    response: str,
) -> str:
    """
    Build Alice's visible side of the interaction.
    """

    return (
        f"{response}"
    )


async def send_alice_response(
    interaction: discord.Interaction,
    user_message: str,
    identity: dict,
    response: str,
) -> None:
    """
    Present the complete conversation turn.

    The user's supplied text is displayed first, followed by Alice's
    response. Both are delivered through the interaction system, so
    no additional channel-message permission is required.

    Discord still records the actual interaction as having been invoked
    by the human Discord account. The bot never attempts to impersonate
    that account.
    """

    user_turn = build_user_turn(
        identity,
        user_message,
    )

    await interaction.followup.send(
        user_turn
    )

    chunks = split_discord_message(
        build_alice_turn(response)
    )

    if not chunks:
        chunks = [
            "Alice returned an empty response."
        ]

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

    The Discord user supplies the message through the slash command.

    Alice receives:
        - the supplied message
        - the Discord provider
        - the Discord user ID
        - the Discord display name

    The completed interaction visibly presents:

        Kram:
        Hello Alice

        AliceAIAPP:
        Hello! ...

    The bot does not attempt to create a channel message authored as
    the human user.
    """

    message = message.strip()

    if not message:
        await interaction.response.send_message(
            "Message cannot be empty.",
            ephemeral=True,
        )

        return

    identity = get_discord_identity(
        interaction
    )

    log.info(
        "Discord request from %s (%s): %s",
        identity["name"],
        identity["user_id"],
        message,
    )

    await interaction.response.defer(
        thinking=True
    )

    try:
        response = await ask_alice(
            message,
            identity=identity,
        )

        await send_alice_response(
            interaction,
            message,
            identity,
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

    identity = get_discord_identity(
        interaction
    )

    log.info(
        "Discord behavior request from %s (%s): %s",
        identity["name"],
        identity["user_id"],
        message,
    )

    await interaction.response.defer(
        thinking=True
    )

    try:
        response = await ask_alice(
            message,
            identity=identity,
            gaslighting=gaslighting,
            hallucination=hallucination,
            overconfidence=overconfidence,
            sycophancy=sycophancy,
        )

        await send_alice_response(
            interaction,
            message,
            identity,
            response,
        )

    except asyncio.TimeoutError:
        await interaction.followup.send(
            "Alice timed out while waiting for the backend."
        )

    except aiohttp.ClientError as exc:
        log.exception(
            "Behavior-controlled Alice request failed"
        )

        await interaction.followup.send(
            "I could not reach Alice Web AI.\n"
            f"Backend error: {exc}"
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