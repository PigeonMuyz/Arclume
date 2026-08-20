#!/usr/bin/env python3
"""A loopback-only metadata adapter for Arclume development.

It requests real game data from Steam's public store endpoint and reshapes it to
the response schema expected by Arclume. It deliberately has no account,
profile, or owned-game routes and does not accept credentials.
"""

from __future__ import annotations

import json
import os
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlencode, urlparse
from urllib.request import Request, urlopen


HOST = "127.0.0.1"
PORT = 18765
STORE_LANGUAGE = os.environ.get("STEAM_STORE_LANGUAGE", "english")
STORE_ENDPOINT = "https://store.steampowered.com/api/appdetails"


def fetch_store_app(app_id: int, language: str) -> dict[str, Any] | None:
    query = urlencode({"appids": app_id, "l": language})
    request = Request(
        f"{STORE_ENDPOINT}?{query}",
        headers={"User-Agent": "Arclume-LocalSteamProxy/1.0"},
    )
    try:
        with urlopen(request, timeout=15) as response:
            payload = json.load(response)
    except (HTTPError, URLError, TimeoutError, json.JSONDecodeError) as error:
        print(f"Steam Store request for {app_id} failed: {error}")
        return None

    app_response = payload.get(str(app_id), {})
    if not app_response.get("success"):
        return None
    data = app_response.get("data")
    return data if isinstance(data, dict) else None


def string_value(value: Any, default: str = "") -> str:
    if value is None:
        return default
    return str(value)


def requirements(value: Any) -> dict[str, str] | None:
    if not isinstance(value, dict):
        return None
    return {
        "minimum": string_value(value.get("minimum")),
        "recommended": string_value(value.get("recommended")),
    }


def normalize_game(store_game: dict[str, Any], app_id: int) -> dict[str, Any]:
    """Keep optional fields optional and guarantee Arclume's required fields."""
    platforms = store_game.get("platforms")
    platforms = platforms if isinstance(platforms, dict) else {}
    release_date = store_game.get("release_date")
    release_date = release_date if isinstance(release_date, dict) else {}
    header_image = string_value(
        store_game.get("header_image"),
        f"https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/{app_id}/header.jpg",
    )

    game: dict[str, Any] = {
        "type": string_value(store_game.get("type"), "game"),
        "name": string_value(store_game.get("name"), f"Steam App {app_id}"),
        "steam_appid": int(store_game.get("steam_appid", app_id)),
        "required_age": string_value(store_game.get("required_age"), "0"),
        "is_free": bool(store_game.get("is_free", False)),
        "detailed_description": string_value(store_game.get("detailed_description")),
        "about_the_game": string_value(store_game.get("about_the_game")),
        "short_description": string_value(store_game.get("short_description")),
        "header_image": header_image,
        "capsule_image": string_value(store_game.get("capsule_image"), header_image),
        "platforms": {
            "windows": bool(platforms.get("windows", False)),
            "mac": bool(platforms.get("mac", False)),
            "linux": bool(platforms.get("linux", False)),
        },
        "release_date": {
            "coming_soon": bool(release_date.get("coming_soon", False)),
            "date": string_value(release_date.get("date"), "Unknown"),
        },
    }

    for key in (
        "controller_support",
        "dlc",
        "supported_languages",
        "capsule_imagev5",
        "website",
        "legal_notice",
        "developers",
        "publishers",
        "price_overview",
        "packages",
        "categories",
        "genres",
        "screenshots",
        "movies",
        "recommendations",
        "achievements",
        "support_info",
        "background",
        "background_raw",
        "content_descriptors",
        "ratings",
    ):
        value = store_game.get(key)
        if value is not None:
            game[key] = value

    for source_key, target_key in (
        ("pc_requirements", "pc_requirements"),
        ("mac_requirements", "mac_requirements"),
        ("linux_requirements", "linux_requirements"),
    ):
        value = requirements(store_game.get(source_key))
        if value is not None:
            game[target_key] = value

    return game


class SteamProxyHandler(BaseHTTPRequestHandler):
    server_version = "ArclumeLocalSteamProxy/1.0"

    def do_GET(self) -> None:  # noqa: N802 - required by BaseHTTPRequestHandler
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self.send_json(HTTPStatus.OK, {"ok": True, "source": "Steam Store"})
            return

        if parsed.path.rstrip("/") != "/steam":
            self.send_json(HTTPStatus.NOT_FOUND, {"error": "Unknown local proxy route"})
            return

        app_id = parse_qs(parsed.query).get("appid", [""])[0]
        if not app_id.isdecimal() or int(app_id) <= 0:
            self.send_json(HTTPStatus.BAD_REQUEST, {"error": "appid must be a positive integer"})
            return

        language = parse_qs(parsed.query).get("language", [STORE_LANGUAGE])[0]
        store_game = fetch_store_app(int(app_id), language)
        data = [] if store_game is None else [normalize_game(store_game, int(app_id))]
        self.send_json(HTTPStatus.OK, {"data": data})

    def send_json(self, status: HTTPStatus, payload: dict[str, Any]) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: Any) -> None:
        print(f"{self.address_string()} - {format % args}")


def main() -> None:
    server = ThreadingHTTPServer((HOST, PORT), SteamProxyHandler)
    print(f"Arclume local Steam Store proxy listening on http://{HOST}:{PORT}")
    print("Press Control-C to stop it.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping local Steam Store proxy.")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
