"""Pytest fixtures that run EasyFishing inside a fresh lupa Lua runtime per test.

Fixtures:
    addon_options  dict passed to load_addon(); override it in a test module to preset databases,
                   e.g. {"db": {"fishing": False}} or {"wow": {"toc": 120100}}.
    lua            the lupa LuaRuntime with wow_stubs.lua and harness.lua loaded, addon not loaded.
    addon          the loaded addon (see Addon below). Loading runs ADDON_LOADED and PLAYER_LOGIN.
    ns             addon.ns, the shared namespace table the addon files fill in.

Lua tables are converted with to_py() when a test wants plain Python dicts and lists. Lua functions
stay callable, e.g. ns.Print("hi") or addon.fire_event("LOOT_OPENED").
"""

from __future__ import annotations

from pathlib import Path

import lupa
import pytest
from lupa import LuaRuntime

TESTS_DIR = Path(__file__).resolve().parent
ADDON_DIR = TESTS_DIR.parent

STUBS_PATH = TESTS_DIR / "wow_stubs.lua"
HARNESS_PATH = TESTS_DIR / "harness.lua"


def new_runtime() -> LuaRuntime:
    """A fresh Lua state with the WoW stubs and the harness loaded (no addon yet)."""
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals()["EASYFISHING_ADDON_DIR"] = ADDON_DIR.as_posix()
    lua.execute(STUBS_PATH.read_text(encoding="utf-8"))
    lua.execute(HARNESS_PATH.read_text(encoding="utf-8"))
    return lua


def to_lua(lua: LuaRuntime, value):
    """Python dict/list/tuple (recursively) into a Lua table; other values pass through."""
    if isinstance(value, dict):
        t = lua.table()
        for k, v in value.items():
            t[k] = to_lua(lua, v)
        return t
    if isinstance(value, (list, tuple)):
        t = lua.table()
        for i, v in enumerate(value, start=1):
            t[i] = to_lua(lua, v)
        return t
    return value


def to_py(value):
    """Lua table into Python: a list when the keys are 1..n, otherwise a dict. Other values as-is."""
    if lupa.lua_type(value) != "table":
        return value
    items = list(value.items())
    keys = [k for k, _ in items]
    if keys and all(isinstance(k, int) and not isinstance(k, bool) for k in keys) and \
            sorted(keys) == list(range(1, len(keys) + 1)):
        return [to_py(v) for _, v in sorted(items, key=lambda kv: kv[0])]
    return {k: to_py(v) for k, v in items}


class Addon:
    """Thin wrapper over the loaded addon: its ns table plus the test helpers from wow_stubs.lua."""

    def __init__(self, lua: LuaRuntime, ns):
        self.lua = lua
        self.ns = ns
        self._g = lua.globals()

    def fire_event(self, event: str, *args):
        self._g.fire_event(event, *args)

    def advance_timers(self, seconds: float = 0):
        return self._g.advance_timers(seconds)

    @property
    def wow(self) -> dict:
        """WOWTEST as a Python dict. A snapshot: reread after changing it."""
        return to_py(self._g.WOWTEST)

    def chat(self) -> list[str]:
        return list(to_py(self._g.WOWTEST.chat))

    def errors(self) -> list[str]:
        return list(to_py(self._g.WOWTEST.errors))

    def call_log(self, frame, method: str) -> list[list]:
        """Recorded calls of `method` on a frame, each as a Python list of arguments."""
        calls = self._g.WOWTEST_CALLS_OF(frame, method)
        return [to_py(c) for c in calls.values()] if calls is not None else []

    def global_(self, name: str):
        return self._g[name]

    def set_global(self, name: str, value):
        self._g[name] = to_lua(self.lua, value)


@pytest.fixture
def addon_options() -> dict:
    return {}


@pytest.fixture
def lua(addon_options) -> LuaRuntime:
    return new_runtime()


@pytest.fixture
def addon(lua: LuaRuntime, addon_options: dict) -> Addon:
    load_addon = lua.globals()["load_addon"]
    ns = load_addon(to_lua(lua, addon_options))
    return Addon(lua, ns)


@pytest.fixture
def ns(addon: Addon):
    return addon.ns


@pytest.fixture
def make_addon():
    """Factory for a fresh, loaded addon with its own options: make_addon({"db": {...}})."""
    def factory(options: dict | None = None) -> Addon:
        lua = new_runtime()
        ns = lua.globals()["load_addon"](to_lua(lua, options or {}))
        return Addon(lua, ns)
    return factory
