-- Loads EasyFishing the way the WoW client does: the files listed in EasyFishing.toc, in order,
-- each called with ("EasyFishing", ns) so that `local _, ns = ...` works.
--
-- Needs the global EASYFISHING_ADDON_DIR (set by conftest.py) to point at the addon folder.
-- Usage from Lua:  local ns = load_addon({ db = {...}, charDb = {...} })
--
-- Options:
--   db          preset for EasyFishingDB (account SavedVariables), merged in before load
--   charDb      preset for EasyFishingCharDB (per character)
--   wow         table of WOWTEST fields to set before load (toc, locale, combat, now, ...)
--   skipLogin   true to skip firing ADDON_LOADED / PLAYER_LOGIN after the files are loaded

local ADDON_NAME = "EasyFishing"
local loader = loadstring or load

local function readFile(path)
    local f, err = io.open(path, "rb")
    if not f then error("cannot open " .. path .. ": " .. tostring(err), 0) end
    local text = f:read("*a")
    f:close()
    -- WoW reads these files as UTF-8 without a BOM; a BOM is stripped to match
    if text:sub(1, 3) == "\239\187\191" then text = text:sub(4) end
    return text
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The file list from the toc: every non-blank line that is not a "##" directive or a comment.
function addon_file_list(addonDir)
    local tocText = readFile(addonDir .. "/" .. ADDON_NAME .. ".toc")
    local files = {}
    for line in (tocText .. "\n"):gmatch("([^\r\n]*)\r?\n") do
        local entry = trim(line)
        if entry ~= "" and entry:sub(1, 1) ~= "#" then
            files[#files + 1] = entry
        end
    end
    return files
end

local function copyInto(dst, src)
    for k, v in pairs(src or {}) do
        if type(v) == "table" and type(dst[k]) == "table" then
            copyInto(dst[k], v)
        else
            dst[k] = v
        end
    end
    return dst
end

-- Saved variables are loaded before any addon file runs, as the client does.
local function setSavedVariables(opts)
    EasyFishingDB = copyInto({}, opts.db or {})
    EasyFishingCharDB = copyInto({}, opts.charDb or {})
end

function load_addon(opts)
    opts = opts or {}
    local addonDir = EASYFISHING_ADDON_DIR
    if not addonDir then error("EASYFISHING_ADDON_DIR is not set", 0) end

    for k, v in pairs(opts.wow or {}) do WOWTEST[k] = v end
    setSavedVariables(opts)

    local ns = {}
    local files = addon_file_list(addonDir)
    for _, rel in ipairs(files) do
        local path = addonDir .. "/" .. rel
        local src = readFile(path)
        local chunk, err = loader(src, "@" .. path)
        if not chunk then
            error("syntax error in " .. rel .. ": " .. tostring(err), 0)
        end
        local ok, runErr = pcall(chunk, ADDON_NAME, ns)
        if not ok then
            error("error loading " .. rel .. ": " .. tostring(runErr), 0)
        end
    end

    if not opts.skipLogin then
        fire_event("ADDON_LOADED", ADDON_NAME)
        fire_event("PLAYER_LOGIN")
    end
    return ns
end
