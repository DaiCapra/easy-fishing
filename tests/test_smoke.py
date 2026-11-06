"""Smoke tests: the addon loads, its entry points exist, and the basic commands and panel run."""

from __future__ import annotations

import pytest

from lupa import lua_type

from conftest import ADDON_DIR, to_py

# Functions other files and the panel rely on. Each must be a Lua function after load.
REQUIRED_NS_FUNCTIONS = [
    "SetFishing",
    "SetFishingLog",
    "FishingLogToggle",
    "FishingLogShow",
    "FishingLogHide",
    "BuildFishingPanel",
    "OpenOptions",
    "MakeCheckboxFactory",
    "Print",
    "CreateThemedButton",
    "SetFishingKey",
    "SetFishingLoud",
    "SetFishingMute",
    "SetFishingBackground",
    "SetFishingIcon",
    "FishingLoudBoostChanged",
    "FishingDescription",
    "CreateLootLog",
    "CreateToggleSwitch",
    "AddSettingsSlider",
    "IsSecretV",
    "Ticker",
]

# Shared helpers from Core.lua that every file uses.
SHARED_HELPERS = ["TAG", "DB", "CharDB", "Unsecret", "ApplyPanelBackdrop"]

DEFAULT_KEYS = [
    "fishing",
    "fishingLoud",
    "fishingLoudBoost",
    "fishingMute",
    "fishingBackground",
    "fishingIcon",
    "fishingLog",
]


def test_load_completes_without_errors(addon):
    # Fixture loading already ran every file plus ADDON_LOADED / PLAYER_LOGIN; any error would have raised.
    assert addon.errors() == []


def test_no_feature_reported_a_failure(addon):
    # Main.lua wraps each startup feature in pcall and reports failures to chat.
    failed = [line for line in addon.chat() if "failed" in line.lower()]
    assert failed == []


@pytest.mark.parametrize("name", REQUIRED_NS_FUNCTIONS)
def test_ns_entry_point_exists(ns, name):
    value = ns[name]
    assert value is not None, f"ns.{name} is missing"


def test_ns_entry_points_are_functions_or_tables(ns):
    for name in REQUIRED_NS_FUNCTIONS:
        value = ns[name]
        assert lua_type(value) in ("function", "table"), f"ns.{name} is {lua_type(value)}"


@pytest.mark.parametrize("name", SHARED_HELPERS)
def test_shared_helper_exists(ns, name):
    assert ns[name] is not None, f"ns.{name} is missing"


def test_tag_is_colored_addon_name(ns):
    assert ns["TAG"] == "|cff38BDF8EasyFishing|r"


def test_db_helpers_return_the_saved_tables(addon):
    # ns.DB() and ns.CharDB() hand back the very tables the client saved as globals.
    g = addon.lua.globals()
    assert g.rawequal(addon.ns["DB"](), g.EasyFishingDB)
    assert g.rawequal(addon.ns["CharDB"](), g.EasyFishingCharDB)


def test_unsecret_passes_normal_values(ns):
    assert ns["Unsecret"](42) == 42
    assert ns["Unsecret"]("text") == "text"
    assert ns["Unsecret"](False) is False
    assert ns["Unsecret"](None) is None


def test_unsecret_returns_nil_for_secret_value(addon, lua):
    secret_table = lua.table()
    secret_text = "hidden"
    lua.globals().WOWTEST.secretValues[secret_table] = True
    lua.globals().WOWTEST.secretValues[secret_text] = True
    assert addon.ns["IsSecretV"](secret_table) is True
    assert addon.ns["Unsecret"](secret_table) is None
    assert addon.ns["Unsecret"](secret_text) is None


def test_slash_command_registered(addon):
    slash = addon.global_("SlashCmdList")
    assert slash["EASYFISHING"] is not None
    assert addon.global_("SLASH_EASYFISHING1") == "/easyfishing"
    assert addon.global_("SLASH_EASYFISHING2") == "/ef"


@pytest.mark.parametrize("command", ["help", "show", "hide", "toggle", "on", "off"])
def test_slash_command_runs_without_error(addon, command):
    before = len(addon.chat())
    addon.global_("SlashCmdList")["EASYFISHING"](command)
    assert addon.errors() == []
    new_lines = addon.chat()[before:]
    assert not any("failed" in line.lower() for line in new_lines), new_lines


def test_help_lists_commands(addon):
    addon.global_("SlashCmdList")["EASYFISHING"]("help")
    text = "\n".join(addon.chat())
    assert "/easyfishing on | off" in text
    assert "show | hide | toggle" in text


def test_chat_lines_use_the_addon_tag(addon):
    addon.global_("SlashCmdList")["EASYFISHING"]("help")
    lines = addon.chat()
    assert lines, "help printed nothing"
    assert all(line.startswith("|cff38BDF8EasyFishing|r: ") for line in lines), lines


def test_slash_toggle_twice_hides_then_shows_log(addon):
    slash = addon.global_("SlashCmdList")["EASYFISHING"]
    slash("toggle")
    log = addon.global_("EasyFishingLog")
    assert log is not None, "toggle did not create the Fishing Log"
    assert log.IsShown(log) is True
    slash("toggle")
    assert log.IsShown(log) is False
    slash("toggle")
    assert log.IsShown(log) is True
    assert addon.errors() == []


def test_fishing_log_has_no_scan_ah_button(addon):
    addon.global_("SlashCmdList")["EASYFISHING"]("show")
    assert addon.errors() == []
    texts = []
    for frame in addon.lua.globals().WOWTEST.frames.values():
        for call in addon.call_log(frame, "SetText"):
            texts.append(str(call.get(1, "")))
    assert not any("scan ah" in t.lower() for t in texts), texts


def test_slash_on_and_off_update_saved_switch(addon):
    slash = addon.global_("SlashCmdList")["EASYFISHING"]
    slash("off")
    assert to_py(addon.global_("EasyFishingDB"))["fishing"] is False
    slash("on")
    assert to_py(addon.global_("EasyFishingDB"))["fishing"] is True


def test_build_fishing_panel_returns_frame(addon, lua):
    g = lua.globals()
    panel = g.CreateFrame("Frame")
    anchor = g.CreateFrame("FontString")
    result = addon.ns.BuildFishingPanel(panel, anchor)
    assert result is not None, "BuildFishingPanel returned nothing"
    assert addon.errors() == []


def test_options_panel_builds_on_show(addon, lua):
    # Panel.lua builds the rows on the first OnShow of the options frame.
    g = lua.globals()
    panel = g.EasyFishingOptions
    assert panel is not None
    panel.Show(panel)
    addon.advance_timers(0)
    assert addon.errors() == []
    assert addon.wow["registeredCategories"] == 1


def test_open_options_runs(addon):
    addon.ns.OpenOptions()
    assert addon.errors() == []
    assert addon.wow["openedCategory"] == 1


def test_saved_variable_defaults_filled(addon):
    db = to_py(addon.global_("EasyFishingDB"))
    for key in DEFAULT_KEYS:
        assert key in db, f"EasyFishingDB.{key} missing"
    assert db["fishing"] is True
    assert db["fishingLoud"] is True
    assert db["fishingLoudBoost"] == 3
    assert db["fishingMute"] is False
    assert db["fishingBackground"] is True
    assert db["fishingIcon"] is True
    assert db["fishingLog"] is True


def test_presets_survive_defaults(make_addon):
    addon = make_addon({"db": {"fishing": False, "fishingLoudBoost": 7}})
    db = to_py(addon.global_("EasyFishingDB"))
    assert db["fishing"] is False
    assert db["fishingLoudBoost"] == 7
    assert db["fishingMute"] is False


def test_other_saved_variables_created(addon):
    assert addon.global_("EasyFishingCharDB") is not None


def test_toc_lists_exactly_the_lua_files_in_the_folder():
    # The toc's file list (non-blank, non-directive lines) must name only files that exist, and every
    # .lua file in the addon folder must be listed.
    toc_lines = (ADDON_DIR / "EasyFishing.toc").read_text(encoding="utf-8").splitlines()
    listed = [
        line.strip() for line in toc_lines
        if line.strip() and not line.strip().startswith("#")
    ]
    missing_files = [name for name in listed if not (ADDON_DIR / name).is_file()]
    assert missing_files == [], f"toc lists files that do not exist: {missing_files}"

    lua_files = sorted(p.name for p in ADDON_DIR.glob("*.lua"))
    unlisted = [name for name in lua_files if name not in listed]
    assert unlisted == [], f"Lua files not listed in the toc: {unlisted}"
