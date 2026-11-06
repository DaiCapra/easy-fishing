"""Fishing loot: the open fishing loot window is always taken, Auto Loot on or off."""

from __future__ import annotations

import pytest

from conftest import to_py

SLOTS = [{"name": "Raw Brilliant Smallfish"}, {"name": "Oily Blackmouth"}]


@pytest.fixture
def addon_options():
    return {"db": {"fishing": True, "fishingKey": "F"}}


def open_loot(addon, auto_loot, fishing=True, slots=SLOTS):
    addon.lua.globals().WOWTEST.fishingLoot = fishing
    addon.lua.globals().WOWTEST.lootSlots = _slots(addon, slots)
    addon.fire_event("LOOT_OPENED", auto_loot, False)


def _slots(addon, slots):
    t = addon.lua.table()
    for i, s in enumerate(slots, start=1):
        row = addon.lua.table()
        for k, v in s.items():
            row[k] = v
        t[i] = row
    return t


def looted(addon):
    v = addon.lua.globals().WOWTEST.lootedSlots
    return [] if v is None else list(to_py(v))


def test_no_errors_on_load(addon):
    assert addon.errors() == []


def test_auto_loot_on_takes_every_fishing_slot(addon):
    open_loot(addon, auto_loot=True)
    assert sorted(looted(addon)) == [1, 2]
    assert addon.errors() == []


def test_auto_loot_on_leaves_non_fishing_loot_alone(addon):
    open_loot(addon, auto_loot=True, fishing=False)
    assert looted(addon) == []


def test_auto_loot_off_also_takes_every_fishing_slot(addon):
    open_loot(addon, auto_loot=False)
    assert sorted(looted(addon)) == [1, 2]
    assert addon.errors() == []


def test_auto_loot_off_non_fishing_loot_is_ignored(addon):
    open_loot(addon, auto_loot=False, fishing=False)
    assert looted(addon) == []


def test_empty_window_loots_nothing(addon):
    open_loot(addon, auto_loot=True, slots=[])
    assert looted(addon) == []
    assert addon.errors() == []
