"""Mute Other Sounds: muted while a fishing pole is equipped (and between casts), restored when it comes off."""

from __future__ import annotations

import pytest

from conftest import to_lua

MAIN_HAND = 16
POLE_ID = 19970
FISHING_SPELL = 7620  # a fishing channel: CHANNEL_IDS in Fishing.lua

# The volumes and switches the mute touches, with what each is before the addon changes it.
ORIGINAL = {
    "Sound_MusicVolume": "0.6",
    "Sound_AmbienceVolume": "0.4",
    "Sound_DialogVolume": "0.8",
    "Sound_EnablePetSounds": "1",
}
MUTED = {name: "0" for name in ORIGINAL}


@pytest.fixture
def addon_options():
    return {"db": {"fishing": True, "fishingKey": "F", "fishingMute": True}}


def setup_sounds(addon):
    """Sound CVars at their original values, and the pole item registered as a fishing pole."""
    g = addon.lua.globals()
    for name, value in ORIGINAL.items():
        g.WOWTEST["cvars"][name] = value
    g.WOWTEST["items"][POLE_ID] = to_lua(addon.lua, {
        "name": "Arcanite Fishing Pole", "link": "|cffffffff[Arcanite Fishing Pole]|r",
        "classID": 2, "subclassID": 20, "equipLoc": "INVTYPE_WEAPONMAINHAND",
        "itemType": "Weapon", "subType": "Fishing Poles",
    })
    return addon


def cvars(addon) -> dict:
    return {name: addon.lua.globals().GetCVar(name) for name in ORIGINAL}


def equip_pole(addon):
    addon.lua.globals().WOWTEST["equipped"][MAIN_HAND] = POLE_ID
    addon.fire_event("PLAYER_EQUIPMENT_CHANGED", MAIN_HAND, True)


def unequip_pole(addon):
    addon.lua.globals().WOWTEST["equipped"][MAIN_HAND] = None
    addon.fire_event("PLAYER_EQUIPMENT_CHANGED", MAIN_HAND, False)


def start_cast(addon):
    addon.fire_event("UNIT_SPELLCAST_CHANNEL_START", "player", "cast-1", FISHING_SPELL)


def end_cast(addon):
    addon.fire_event("UNIT_SPELLCAST_CHANNEL_STOP", "player", "cast-1", FISHING_SPELL)


def test_equipping_pole_mutes_without_a_cast(addon):
    setup_sounds(addon)
    equip_pole(addon)
    assert addon.errors() == []
    assert cvars(addon) == MUTED
    assert not addon.wow["sounds"]  # no cast started: nothing was played either


def test_unequipping_pole_restores_original_values(addon):
    setup_sounds(addon)
    equip_pole(addon)
    assert cvars(addon) == MUTED
    unequip_pole(addon)
    assert addon.errors() == []
    assert cvars(addon) == ORIGINAL


def test_cast_ending_with_pole_equipped_leaves_mute_on(addon):
    setup_sounds(addon)
    equip_pole(addon)
    start_cast(addon)
    assert cvars(addon) == MUTED
    end_cast(addon)
    assert addon.errors() == []
    assert cvars(addon) == MUTED
    # The mute is still in the saved restore list, so unequipping (or logging out) puts it back.
    restore = addon.lua.globals().EasyFishingDB.fishingRestore
    assert restore is not None
    assert restore.Sound_MusicVolume.o == "0.6"
    assert restore.Sound_EnablePetSounds.o == "1"


def test_cast_ending_with_pole_equipped_then_unequipping_restores(addon):
    setup_sounds(addon)
    equip_pole(addon)
    start_cast(addon)
    end_cast(addon)
    unequip_pole(addon)
    assert cvars(addon) == ORIGINAL


def test_equipping_pole_with_mute_off_changes_nothing(make_addon):
    addon = make_addon({"db": {"fishing": True, "fishingKey": "F", "fishingMute": False}})
    setup_sounds(addon)
    equip_pole(addon)
    assert addon.errors() == []
    assert cvars(addon) == ORIGINAL
    assert addon.lua.globals().EasyFishingDB.fishingRestore is None


def test_equipping_pole_mutes_on_retail_too(make_addon):
    # The pole events are registered on every client now, not only WoW: Forever.
    addon = make_addon({"db": {"fishing": True, "fishingKey": "F", "fishingMute": True}, "wow": {"toc": 120100}})
    setup_sounds(addon)
    equip_pole(addon)
    assert addon.errors() == []
    assert cvars(addon) == MUTED
    unequip_pole(addon)
    assert cvars(addon) == ORIGINAL
