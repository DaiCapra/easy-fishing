"""The Fishing Log's percentages: each catch's share of everything caught this session."""

from __future__ import annotations

from conftest import to_lua, to_py


def rows(addon, counts):
    return addon.ns.LootSession.Shares(to_lua(addon.lua, [{"count": c} for c in counts]))


def test_shares_add_up_from_counts(addon, ns):
    got = [r["pct"] for r in to_py(rows(addon, [6, 3, 1]))]
    assert got == [60, 30, 10]


def test_share_rounds_to_whole_percent(addon, ns):
    got = [r["pct"] for r in to_py(rows(addon, [2, 1]))]
    assert got == [67, 33]


def test_empty_rows_have_no_shares(addon, ns):
    assert to_py(rows(addon, [])) in ([], {}, None)


def test_count_text_shows_percent(addon, ns):
    r = rows(addon, [12, 18])
    assert ns.LootSession.CountText(r[1]) == "x12 · 40%"


def test_count_text_tiny_share(addon, ns):
    r = rows(addon, [1, 300])
    assert ns.LootSession.CountText(r[1]) == "x1 · <1%"


def test_count_text_without_share(addon, ns):
    assert ns.LootSession.CountText(to_lua(addon.lua, {"count": 5})) == "x5"
