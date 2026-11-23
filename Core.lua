-- Core: saved settings, shared helpers, events and the slash command.
--
-- Nothing here runs on a timer loop or every frame. Work happens when the
-- game reports a change (an event), or at the one moment an icon is next due
-- to look different (a single timer set for exactly then).
local ADDON, ns = ...

local issecret = issecretvalue or function() return false end

ns.version = "2.2.1"
ns.icon = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Icon"
ns.iconRound = "Interface\\AddOns\\" .. ADDON .. "\\Media\\IconRound"

ns.cache = {}       -- [button key] = last known state of that buff
ns.buttons = {}     -- every icon in use, across all bars
ns.bars = {}        -- the bars in use (see Bar.lua)
ns.allEntries = {}  -- every consumable of the active profile, across all bars

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
function ns.Secret(v) return issecret(v) end

-- A plain number / string, or nil when the game is hiding the value.
function ns.Num(v)
	if type(v) == "number" and not issecret(v) then return v end
end

function ns.Str(v)
	if type(v) == "string" and not issecret(v) then return v end
end

-- Calls a game function that may be missing or may refuse to answer.
function ns.Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d, e, f, g = pcall(fn, ...)
	if ok then return a, b, c, d, e, f, g end
end

function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffClickableConsumeBar|r: " .. tostring(msg))
end

function ns.InCombat()
	return InCombatLockdown() and true or false
end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------
function ns.ItemName(id)
	local name = ns.Str(ns.Call(C_Item.GetItemNameByID, id))
	if not name then
		ns.needItemInfo = true -- listen for the item's data arriving
		ns.Call(C_Item.RequestLoadItemDataByID, id)
		return "Item " .. id
	end
	return name
end

function ns.ItemIcon(id)
	return ns.Call(C_Item.GetItemIconByID, id) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

function ns.ItemCount(id)
	return ns.Num(ns.Call(C_Item.GetItemCount, id)) or 0
end

-- The spell an item casts when used: name, spell ID.
function ns.ItemSpell(id)
	local name, spellID = ns.Call(C_Item.GetItemSpell, id)
	return ns.Str(name), ns.Num(spellID)
end

-- classID, subClassID of an item.
function ns.ItemClass(id)
	local _, _, _, _, _, classID, subClassID = ns.Call(C_Item.GetItemInfoInstant, id)
	return ns.Num(classID), ns.Num(subClassID)
end

local foodNames
local function IsFoodSpellName(name)
	if not name then return false end
	if not foodNames then
		local names, any = {}, false
		for _, spellID in ipairs(ns.FOOD_SPELLS) do
			local known = ns.Str(ns.Call(C_Spell.GetSpellName, spellID))
			if known then names[known], any = true, true end
		end
		if not any then return false end -- spell names not loaded yet: try again later
		foodNames = names
	end
	return foodNames[name] == true
end

-- Food: filed under Food & Drink, or its use effect is the "Food" spell.
function ns.IsFood(id)
	local classID, subClassID = ns.ItemClass(id)
	if classID == 0 and subClassID == 5 then return true end
	return IsFoodSpellName((ns.ItemSpell(id)))
end

local function LooksLikeWeaponItem(id)
	if ns.WEAPON_ITEMS[id] then return true end
	local classID, subClassID = ns.ItemClass(id)
	if classID == 8 then return true end
	return classID == 0 and (subClassID == 6 or subClassID == 15)
end

---------------------------------------------------------------------------
-- Saved settings
---------------------------------------------------------------------------
local MAX_PROFILES = 8
local MAX_BARS = 4
ns.MAX_BARS = MAX_BARS
local CONTEXT_NAMES = { world = "open world", party = "dungeon", raid = "raid", pvp = "battleground" }

-- Shared by everything: glow, warning time, the lock, tooltips, the minimap
-- button and which profile goes with which kind of place.
local DEFAULTS = {
	auto = {},            -- [world | party | raid | pvp] = profile to switch to there
	warn = 300,
	desaturate = true,
	bar = { locked = false, tooltips = true },
	minimap = { show = true, angle = 215 },
	glow = {
		expiring = { enabled = true, style = "pixel", r = 1, g = 0.82, b = 0, a = 1, speed = 1, size = 2 },
		missing = { enabled = true, style = "pulse", r = 1, g = 0.15, b = 0.15, a = 1, speed = 1, size = 2 },
	},
}

-- Each bar has its own place and look...
local BAR_CFG = {
	point = "CENTER", relPoint = "CENTER", x = 0, y = -180,
	size = 36, spacing = 4, perRow = 12, vertical = false, alpha = 1,
	showTimer = true, showCount = true,
}
-- ...and its own rules for when it's shown.
local BAR_SHOW = {
	mode = "always",      -- always | attention
	combat = "any",       -- any | in | out
	group = "any",        -- any | solo | group | raid
	instance = "any",     -- any | inside | outside
	hideResting = false,
	hideMounted = false,
}

local function Fill(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			Fill(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

local function CopyTable(src)
	local dst = {}
	for k, v in pairs(src) do
		dst[k] = type(v) == "table" and CopyTable(v) or v
	end
	return dst
end

-- Where a bar starts out: the first under the middle of the screen, the
-- others stacked below it so they don't land on top of each other.
local function DefaultPosition(cfg, index)
	cfg.point, cfg.relPoint, cfg.x, cfg.y = "CENTER", "CENTER", 0, -180 - (index - 1) * 50
end

local function NewBar(index, name)
	local bar = { name = name or ("Bar " .. index), entries = {}, cfg = CopyTable(BAR_CFG), show = CopyTable(BAR_SHOW) }
	DefaultPosition(bar.cfg, index)
	return bar
end

-- Points ns.profile, ns.entries and friends at the profile and bar in use.
local function Activate()
	local db = ns.db
	ns.profile = db.profiles[db.profile]
	local bars = ns.profile.bars
	if not ns.editBar or not bars[ns.editBar] then ns.editBar = 1 end
	ns.entries = bars[ns.editBar].entries
end

-- A profile is a named set of up to four bars. Each bar has its own list of
-- consumables, its own position and look, and its own show rules. ns.profile
-- is the profile in use; ns.entries is the list of the bar being edited in
-- the menu; ns.allEntries (filled when the bars are built) is every
-- consumable of the profile.
local function InitDB()
	-- The addon used to be called ClickBuffBar. If that one is still installed
	-- its settings are in memory right now: take them over once.
	if ClickableConsumeBarDB == nil and type(ClickBuffBarDB) == "table" then
		ClickableConsumeBarDB = CopyTable(ClickBuffBarDB)
		ns.imported = true
	end
	if type(ClickableConsumeBarDB) ~= "table" then ClickableConsumeBarDB = {} end
	local db = ClickableConsumeBarDB
	Fill(db, DEFAULTS)
	if type(db.profiles) ~= "table" or next(db.profiles) == nil then
		-- First run, or settings from before profiles existed.
		db.profiles = { Default = { entries = type(db.entries) == "table" and db.entries or {} } }
		db.profile = "Default"
	end
	db.entries = nil

	-- Before bars existed a profile was one list, and position, look and show
	-- rules were shared. Each profile becomes one bar that keeps all of that.
	local oldCfg, oldShow = {}, type(db.show) == "table" and db.show or nil
	for key in pairs(BAR_CFG) do oldCfg[key] = db.bar[key] end
	for _, profile in pairs(db.profiles) do
		if type(profile.bars) ~= "table" or #profile.bars == 0 then
			profile.bars = { {
				name = "Bar 1",
				entries = type(profile.entries) == "table" and profile.entries or {},
				cfg = CopyTable(oldCfg),
				show = oldShow and CopyTable(oldShow) or {},
			} }
		end
		profile.entries = nil
		for index, bar in ipairs(profile.bars) do
			if type(bar.entries) ~= "table" then bar.entries = {} end
			if type(bar.cfg) ~= "table" then bar.cfg = {} end
			if type(bar.show) ~= "table" then bar.show = {} end
			Fill(bar.cfg, BAR_CFG)
			Fill(bar.show, BAR_SHOW)
			if type(bar.name) ~= "string" or bar.name == "" then bar.name = "Bar " .. index end
		end
	end
	for key in pairs(BAR_CFG) do db.bar[key] = nil end
	db.show = nil

	if not db.profiles[db.profile] then db.profile = next(db.profiles) end
	ns.db = db
	ns.editBar = 1
	Activate()
end
ns.InitDB = InitDB

function ns.ProfileNames()
	local names = {}
	for name in pairs(ns.db.profiles) do names[#names + 1] = name end
	table.sort(names)
	return names
end

-- Makes a new profile, empty or as a copy of another one.
function ns.CreateProfile(name, copyFrom)
	name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
	if name == "" then return nil, "Type a name for the profile first." end
	if #name > 24 then return nil, "That name is too long (24 characters at most)." end
	if ns.db.profiles[name] then return nil, "There's already a profile called \"" .. name .. "\"." end
	if #ns.ProfileNames() >= MAX_PROFILES then return nil, "You can have up to " .. MAX_PROFILES .. " profiles." end
	local source = copyFrom and ns.db.profiles[copyFrom]
	ns.db.profiles[name] = { bars = source and CopyTable(source.bars) or { NewBar(1) } }
	return name
end

-- How much is in a profile: consumables across all its bars, and bars.
function ns.ProfileCounts(name)
	local profile = ns.db.profiles[name]
	local items = 0
	for _, bar in ipairs(profile.bars) do items = items + #bar.entries end
	return items, #profile.bars
end

function ns.SwitchProfile(name)
	local profile = ns.db.profiles[name]
	if not profile then return false end
	ns.db.profile = name
	ns.editBar = 1
	Activate()
	ns.learning, ns.weaponPending = nil, nil
	ns.Rebuild()
	if ns.RefreshOptions then ns.RefreshOptions() end
	return true
end

-- Replaces the bars of the profile in use with copies of another profile's.
function ns.CopyProfileFrom(name)
	local source = ns.db.profiles[name]
	if not source then return nil, "No such profile." end
	if name == ns.db.profile then return nil, "That's the profile already in use." end
	ns.db.profiles[ns.db.profile].bars = CopyTable(source.bars)
	ns.editBar = 1
	Activate()
	ns.learning, ns.weaponPending = nil, nil
	ns.Rebuild()
	return true
end

function ns.DeleteProfile(name)
	if not ns.db.profiles[name] then return nil, "No such profile." end
	if name == ns.db.profile then return nil, "Switch to another profile before deleting this one." end
	ns.db.profiles[name] = nil
	for context, target in pairs(ns.db.auto) do
		if target == name then ns.db.auto[context] = nil end
	end
	return true
end

-- Where you are, for automatic switching: world, party, raid or pvp.
function ns.Context()
	local inInstance, kind = IsInInstance()
	if ns.Secret(inInstance) or ns.Secret(kind) or not inInstance then return "world" end
	if kind == "raid" then return "raid" end
	if kind == "pvp" or kind == "arena" then return "pvp" end
	return "party"
end

-- Switches profile when you move between the open world, a dungeon, a raid
-- and a battleground, if a profile is assigned to the new place. A profile
-- picked by hand stays until the kind of place changes again.
function ns.CheckContext()
	local context = ns.Context()
	if context == ns.context then return end
	ns.context = context
	local name = ns.db.auto[context]
	if name and ns.db.profiles[name] and name ~= ns.db.profile then
		ns.SwitchProfile(name)
		ns.Print(("Switched to profile \"%s\" (%s).%s"):format(name, CONTEXT_NAMES[context],
			ns.InCombat() and " The bar updates when combat ends." or ""))
	end
end

---------------------------------------------------------------------------
-- Bars
---------------------------------------------------------------------------
-- The saved settings of the bar being edited in the menu.
function ns.EditBar()
	return ns.profile.bars[ns.editBar]
end

-- Chooses which bar the menu, /ccb add and the functions below work on.
function ns.SelectBar(index)
	if not ns.profile.bars[index] then return false end
	ns.editBar = index
	Activate()
	if ns.RefreshOptions then ns.RefreshOptions() end
	return true
end

local function CleanBarName(name)
	name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
	if name == "" then return nil, "Type a name for the bar first." end
	if #name > 20 then return nil, "That name is too long (20 characters at most)." end
	return name
end

-- Adds an empty bar to the profile in use and selects it.
function ns.AddBar(name)
	local bars = ns.profile.bars
	if #bars >= MAX_BARS then return nil, "A profile can have up to " .. MAX_BARS .. " bars." end
	local index = #bars + 1
	if name ~= nil then
		local clean, err = CleanBarName(name)
		if not clean then return nil, err end
		name = clean
	else
		-- "Bar 3" may be taken after bars were deleted: use the first free number.
		local number, taken = index, true
		while taken do
			taken = false
			for _, bar in ipairs(bars) do
				if bar.name == "Bar " .. number then taken = true end
			end
			if taken then number = number + 1 end
		end
		name = "Bar " .. number
	end
	bars[index] = NewBar(index, name)
	ns.editBar = index
	Activate()
	ns.Rebuild()
	return index
end

function ns.DeleteBar(index)
	local bars = ns.profile.bars
	if not bars[index] then return nil, "No such bar." end
	if #bars == 1 then return nil, "A profile needs at least one bar." end
	table.remove(bars, index)
	if ns.editBar > #bars then ns.editBar = #bars end
	Activate()
	ns.learning, ns.weaponPending = nil, nil
	ns.Rebuild()
	return true
end

function ns.RenameBar(index, name)
	local bar = ns.profile.bars[index]
	if not bar then return nil, "No such bar." end
	local clean, err = CleanBarName(name)
	if not clean then return nil, err end
	bar.name = clean
	ns.UpdateMover()
	return true
end

-- Puts a bar back where it started.
function ns.ResetBarPosition(index)
	local bar = ns.profile.bars[index]
	if not bar then return end
	DefaultPosition(bar.cfg, index)
	ns.Rebuild()
end

---------------------------------------------------------------------------
-- The consumables of the bar being edited
---------------------------------------------------------------------------
function ns.FindEntry(id)
	for i, entry in ipairs(ns.entries) do
		if entry.id == id then return entry, i end
	end
end

-- Turns what was typed or dropped into an item ID: a number, an item link,
-- or the name of an item you're carrying.
function ns.ResolveItem(text)
	if type(text) == "number" then return text end
	if type(text) ~= "string" then return nil end
	text = text:match("^%s*(.-)%s*$")
	if text == "" then return nil end
	local id = tonumber(text) or tonumber(text:match("item:(%d+)"))
	if not id then
		id = ns.Num(ns.Call(C_Item.GetItemInfoInstant, text))
	end
	return id
end

function ns.AddItem(id)
	id = tonumber(id)
	if not id then return nil, "That doesn't look like an item." end
	if ns.FindEntry(id) then return nil, ns.ItemName(id) .. " is already on " .. ns.EditBar().name .. "." end
	if not ns.Call(C_Item.GetItemInfoInstant, id) then
		return nil, "No item with ID " .. id .. " exists."
	end
	local entry = { id = id, kind = "self", mh = true, oh = false, slotType = "auto" }
	local known
	for _, profile in pairs(ns.db.profiles) do
		for _, bar in ipairs(profile.bars) do
			for _, other in ipairs(bar.entries) do
				if other.id == id then known = other end
			end
		end
	end
	if known then
		-- Already set up on another bar or profile: bring its settings along.
		entry = CopyTable(known)
	elseif LooksLikeWeaponItem(id) then
		entry.kind = "weapon"
	elseif ns.Str(ns.Call(C_Item.GetItemNameByID, id)) and not ns.ItemSpell(id) then
		-- Loaded and has no use effect, like a reagent: just show the count.
		entry.kind = "view"
	end
	table.insert(ns.entries, entry)
	ns.Rebuild()
	return entry
end

function ns.RemoveItem(id)
	local _, index = ns.FindEntry(id)
	if index then
		table.remove(ns.entries, index)
		ns.Rebuild()
	end
end

function ns.MoveItem(id, delta)
	local list = ns.entries
	local _, index = ns.FindEntry(id)
	local other = index and index + delta
	if other and list[other] then
		list[index], list[other] = list[other], list[index]
		ns.Rebuild()
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {}

-- One timer at most is ever pending. A scan works out when an icon will
-- next change by itself (a minute ticking over, the warning time, expiry)
-- and asks to be woken then; events ask to be woken a moment later, which
-- also folds a burst of events into one scan.
local timer, wakeAt
local function OnWake()
	timer, wakeAt = nil, nil
	ns.Update()
end

function ns.ScheduleWake(delay)
	if delay < 0.01 then delay = 0.01 end
	local at = GetTime() + delay
	if timer then
		if wakeAt <= at then return end -- already waking sooner
		timer:Cancel()
	end
	timer, wakeAt = C_Timer.NewTimer(delay, OnWake), at
end

-- Asks for a re-read a moment from now. `what` limits it to the part of the
-- game that changed ("auras", "weapons" or "bags"); without it everything is
-- read. A burst of events becomes one read.
function ns.RequestScan(what)
	ns.MarkDirty(what)
	ns.ScheduleWake(0.1)
end

function handlers.ADDON_LOADED(name)
	if name ~= ADDON then return end
	InitDB()
	frame:UnregisterEvent("ADDON_LOADED")
end

function handlers.PLAYER_LOGIN()
	if not ns.db then InitDB() end
	ns.StartBars()
	ns.Rebuild()
	ns.InitOptions()
	ns.UpdateMinimapButton()
	ns.SettleMinimapButton()
	if ns.imported then
		ns.Print("Imported your settings from ClickBuffBar. Log out, then delete the old ClickBuffBar folder.")
	end
	if #ns.allEntries == 0 then
		ns.Print("Type /ccb to pick the consumables you want on the bar.")
	end
end

function handlers.PLAYER_ENTERING_WORLD()
	ns.UpdateMinimapButton()
	ns.CheckContext()
	ns.UpdateVisibility()
	ns.RequestScan()
end

function handlers.PLAYER_REGEN_DISABLED()
	ns.OnCombatStart()
	-- Read buffs and weapons right now, in the last moment before the game
	-- starts hiding buffs: the timers kept through the fight start from here.
	ns.MarkDirty("auras")
	ns.MarkDirty("weapons")
	ns.Update()
	ns.MarkEstimated()
end

function handlers.PLAYER_REGEN_ENABLED()
	-- Everything that had to wait for combat to end.
	ns.AfterCombat()
	ns.RequestScan()
end

function handlers.UNIT_AURA()
	-- In combat the game hides buffs, so unless a tracked buff is one it
	-- never hides there is nothing to read: ignore the event outright.
	if ns.combat and not ns.liveInCombat then return end
	ns.RequestScan("auras")
end

function handlers.UNIT_SPELLCAST_SUCCEEDED(_, _, spellID)
	ns.OnCastSucceeded(spellID)
end

function handlers.WEAPON_ENCHANT_CHANGED()
	ns.OnEnchantChanged()
	ns.RequestScan("weapons")
end

handlers.WEAPON_SLOT_CHANGED = handlers.WEAPON_ENCHANT_CHANGED
handlers.PLAYER_EQUIPMENT_CHANGED = handlers.WEAPON_ENCHANT_CHANGED
handlers.UNIT_INVENTORY_CHANGED = handlers.WEAPON_ENCHANT_CHANGED

function handlers.BAG_UPDATE_DELAYED()
	ns.InvalidateCounts()
	ns.RequestScan("bags")
	if ns.menuOpen then ns.RefreshOptions() end
end

function handlers.GET_ITEM_INFO_RECEIVED()
	-- Fires for every item the game loads, for any addon. Only act while one
	-- of our items is still waiting for its data, or the menu is open.
	if not ns.needItemInfo and not ns.menuOpen then return end
	ns.needItemInfo = false
	ns.spellMap = nil
	ns.RefreshIcons()
	ns.RequestScan()
	if ns.menuOpen then ns.RefreshOptions() end
end

function handlers.PLAYER_UPDATE_RESTING() ns.UpdateVisibility() end
function handlers.ZONE_CHANGED_NEW_AREA()
	ns.CheckContext()
	ns.UpdateVisibility()
end

frame:SetScript("OnEvent", function(_, event, ...)
	local handler = handlers[event]
	if handler then handler(...) end
end)

-- Events only some kinds of icon need. They're registered while such an icon
-- is on the bar and dropped when it isn't, so an empty bar, or one with only
-- view-only items, never hears about your buffs or casts at all.
local UNIT_EVENTS = { UNIT_AURA = true, UNIT_SPELLCAST_SUCCEEDED = true, UNIT_INVENTORY_CHANGED = true }
local OPTIONAL = {
	UNIT_AURA = "self",
	UNIT_SPELLCAST_SUCCEEDED = "usable",
	WEAPON_ENCHANT_CHANGED = "weapon",
	WEAPON_SLOT_CHANGED = "weapon",
	PLAYER_EQUIPMENT_CHANGED = "weapon",
	UNIT_INVENTORY_CHANGED = "weapon",
}
local listening = {}

local function Listen(event, want)
	if listening[event] == want then return end
	listening[event] = want
	-- An event this client doesn't have must not stop the others.
	if not want then
		pcall(frame.UnregisterEvent, frame, event)
	elseif UNIT_EVENTS[event] then
		pcall(frame.RegisterUnitEvent, frame, event, "player")
	else
		pcall(frame.RegisterEvent, frame, event)
	end
end

-- needs: { self = bool, weapon = bool, usable = bool }
function ns.UpdateEvents(needs)
	for event, kind in pairs(OPTIONAL) do
		Listen(event, needs[kind] and true or false)
	end
end

for event in pairs(handlers) do
	if not OPTIONAL[event] then Listen(event, true) end
end

---------------------------------------------------------------------------
-- Slash command and the addon button by the minimap
---------------------------------------------------------------------------
local function Status()
	ns.Print("Profile \"" .. ns.db.profile .. "\" is tracking:")
	for _, bar in ipairs(ns.bars) do
		if #ns.bars > 1 then ns.Print(" " .. bar.data.name .. ":") end
		for _, button in ipairs(bar.buttons) do
			local state = button.state or {}
			local left = state.expires and state.expires > 0 and ns.FormatTime(state.expires - GetTime()) or "-"
			ns.Print(("  %s%s: %s, time left %s%s"):format(ns.ItemName(button.entry.id),
				button.slot and (button.slot == 16 and " (main hand)" or " (off hand)") or "",
				tostring(state.status), left, state.predicted and " (estimated)" or ""))
		end
		if #bar.buttons == 0 and #ns.bars > 1 then ns.Print("  empty") end
	end
	if #ns.buttons == 0 then ns.Print("  none yet. Type /ccb to add some.") end
end

SLASH_CLICKABLECONSUMEBAR1 = "/ccb"
SLASH_CLICKABLECONSUMEBAR2 = "/clickableconsumebar"
SLASH_CLICKABLECONSUMEBAR3 = "/cbb" -- the command from when the addon was called ClickBuffBar
SlashCmdList["CLICKABLECONSUMEBAR"] = function(msg)
	msg = (msg or ""):match("^%s*(.-)%s*$")
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()
	if cmd == "" or cmd == "options" or cmd == "config" then
		ns.ToggleOptions()
	elseif cmd == "lock" or cmd == "unlock" then
		ns.db.bar.locked = (cmd == "lock")
		ns.UpdateMover()
		ns.UpdateVisibility()
		ns.Print(cmd == "lock" and "Bars locked." or "Bars unlocked. Drag each one by the handle above it.")
	elseif cmd == "reset" then
		for index, bar in ipairs(ns.profile.bars) do DefaultPosition(bar.cfg, index) end
		ns.Rebuild()
		ns.Print("Bars moved back to the middle of the screen.")
	elseif cmd == "add" then
		local id = ns.ResolveItem(rest)
		local entry, err = ns.AddItem(id)
		ns.Print(entry and ("Added " .. ns.ItemName(entry.id) .. ".") or err)
		if ns.RefreshOptions then ns.RefreshOptions() end
	elseif cmd == "profile" then
		if rest == "" then
			ns.Print("Profiles: " .. table.concat(ns.ProfileNames(), ", ") .. ". Active: " .. ns.db.profile .. ".")
		elseif ns.SwitchProfile(rest) then
			ns.Print("Switched to profile \"" .. rest .. "\".")
		else
			ns.Print("No profile called \"" .. rest .. "\". Profiles: " .. table.concat(ns.ProfileNames(), ", ") .. ".")
		end
	elseif cmd == "status" then
		Status()
	elseif cmd == "debug" then
		ns.DebugVisibility()
	elseif cmd == "buffs" then
		ns.DebugBuffs()
	else
		ns.Print("/ccb - open the menu")
		ns.Print("/ccb add <item ID, link or name> - add a consumable to the bar selected in the menu")
		ns.Print("/ccb profile <name> - switch profile (no name lists them)")
		ns.Print("/ccb lock | unlock - lock or unlock the bars for moving")
		ns.Print("/ccb reset - move the bars back to the middle of the screen")
		ns.Print("/ccb status - list what the bar is tracking")
		ns.Print("/ccb debug - explain why the bar is or isn't showing")
		ns.Print("/ccb buffs - show which buff each icon is tracking and what's on you")
	end
end

function ClickableConsumeBar_OnCompartmentClick()
	ns.ToggleOptions()
end
