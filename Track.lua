-- Track: works out whether each consumable's buff is up, running out or gone.
--
-- Out of combat every buff can be read directly. In combat WoW: Forever hides
-- most aura data from addons, so a buff that can't be read keeps the state and
-- expiry time it had when it was last seen, and is read again as soon as the
-- game allows. Weapon enchants can always be read.
local _, ns = ...

local Num, Str, Call, Secret = ns.Num, ns.Str, ns.Call, ns.Secret

local MAIN_HAND, OFF_HAND = 16, 17

function ns.AurasSecret()
	local fn = C_Secrets and C_Secrets.ShouldAurasBeSecret
	if not fn then return false end
	local ok, result = pcall(fn)
	if not ok then return false end
	if Secret(result) then return true end
	return result and true or false
end

function ns.FormatTime(seconds)
	if seconds >= 5400 then
		return ("%dh"):format(math.floor(seconds / 3600 + 0.5))
	elseif seconds >= 60 then
		return ("%dm"):format(math.ceil(seconds / 60))
	end
	return ("%d"):format(math.max(0, math.ceil(seconds)))
end

function ns.FormatClock(seconds)
	seconds = math.max(0, math.floor(seconds + 0.5))
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

local function SpellName(id)
	return Str(Call(C_Spell and C_Spell.GetSpellName, id))
end

---------------------------------------------------------------------------
-- Which buff an item gives
---------------------------------------------------------------------------
-- Spell IDs and names that count as this item's buff, most specific first:
-- a name typed in the menu, then the buff learned from using the item, then
-- a guess from the item itself (third return value true).
local candidateCache = setmetatable({}, { __mode = "k" })
local BuildCandidates

-- The lists are worked out once per item and reused until the typed name or
-- the learned buff changes, so a scan allocates nothing.
function ns.Candidates(entry)
	local cached = candidateCache[entry]
	if cached and cached.typed == entry.auraName and cached.learned == entry.learned then
		return cached.ids, cached.names, cached.guessed
	end
	local ids, names, guessed = BuildCandidates(entry)
	if #ids > 0 or #names > 0 then -- nothing yet means the item isn't loaded: ask again next time
		candidateCache[entry] = { ids = ids, names = names, guessed = guessed, typed = entry.auraName, learned = entry.learned }
	end
	return ids, names, guessed
end

BuildCandidates = function(entry)
	local ids, names = {}, {}
	local typed = entry.auraName
	if typed and typed ~= "" then
		if tonumber(typed) then ids[1] = tonumber(typed) else names[1] = typed end
		return ids, names
	end
	local learned = entry.learned
	if learned then
		if learned.id then ids[1] = learned.id end
		if learned.name then names[1] = learned.name end
		return ids, names
	end
	if ns.IsFood(entry.id) then
		for _, spellID in ipairs(ns.WELL_FED_SPELLS) do
			local name = SpellName(spellID)
			local listed = false
			for i = 1, #names do
				if names[i] == name then listed = true end
			end
			if name and not listed then names[#names + 1] = name end
		end
		if #names > 0 then return ids, names, true end
	end
	local name, spellID = ns.ItemSpell(entry.id)
	if spellID then ids[1] = spellID end
	if name then names[1] = name end
	if not spellID and not name then
		-- The item's data may not be loaded yet (right after login). Asking
		-- for its name requests it, and the icon is re-read when it arrives.
		ns.ItemName(entry.id)
	end
	return ids, names, true
end

-- The name shown in the menu for the buff being tracked.
function ns.TrackedBuffName(entry)
	local ids, names = ns.Candidates(entry)
	return names[1] or (ids[1] and SpellName(ids[1])) or nil
end

---------------------------------------------------------------------------
-- Reading buffs
---------------------------------------------------------------------------
local function AuraFields(aura)
	return Num(aura.expirationTime), Num(aura.duration)
end

-- Folds one lookup result into `best`. Keeps the buff that lasts longest; a
-- buff with no timer beats them all.
local function Consider(best, aura, guessed)
	if aura == nil then return end
	if Secret(aura) or type(aura) ~= "table" then
		best.found = true
		return
	end
	local ok, expires, duration = pcall(AuraFields, aura)
	-- A guess that matches something lasting under a minute is the wrong
	-- buff, like the "Food" effect while you sit and eat.
	if guessed and ok and duration and duration > 0 and duration < 60 then return end
	best.found = true
	if not ok or not expires then return end
	if expires == 0 then
		best.expires, best.duration = 0, 0
	elseif best.expires ~= 0 and (not best.expires or expires > best.expires) then
		best.expires, best.duration = expires, duration
	end
end

-- True when the game answers for these buffs even in combat, so "not found"
-- really means missing. Only spell IDs can be checked.
local function AllNeverSecret(ids, names)
	local fn = C_Secrets and C_Secrets.GetSpellAuraSecrecy
	local levels = Enum and Enum.SecrecyLevel
	if not fn or not levels or #ids == 0 or #names > #ids then return false end
	for _, id in ipairs(ids) do
		local ok, level = pcall(fn, id)
		if not ok or Secret(level) or level ~= levels.NeverSecret then return false end
	end
	return true
end

-- Every helpful buff on you, read into reusable records so a scan leaves no
-- garbage behind. Returns false when the game won't allow it (combat).
local auraList, auraCount = {}, 0
local function ReadAuras()
	auraCount = 0
	if ns.AurasSecret() then return false end
	local fn = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	if not fn then return false end
	local count = 0
	for i = 1, 255 do
		local aura = fn("player", i, "HELPFUL")
		if aura == nil then break end
		if Secret(aura) or type(aura) ~= "table" then return false end
		local id = Num(aura.spellId)
		if not id then return false end
		local rec = auraList[i]
		if not rec then
			rec = {}
			auraList[i] = rec
		end
		rec.id, rec.name = id, Str(aura.name)
		rec.duration, rec.expires = Num(aura.duration) or 0, Num(aura.expirationTime) or 0
		rec.timeMod = Num(aura.timeMod)
		-- Whose buff it is. The caster's unit says so when the game knows it
		-- ("player" is you); a buff from an NPC is flagged separately. When
		-- neither is known the buff counts as yours.
		-- "self", "other", or "unknown": the game only names the caster when
		-- it's you or someone in your group, so a buff from a passing player
		-- comes through with no caster at all.
		local source, fromPlayers = aura.sourceUnit, aura.isFromPlayerOrPlayerPet
		if type(source) == "string" and not Secret(source) then
			rec.caster = (source == "player" or source == "pet" or source == "vehicle") and "self" or "other"
		elseif not Secret(fromPlayers) and fromPlayers == false then
			rec.caster = "other"
		else
			rec.caster = "unknown"
		end
		rec.mine = rec.caster ~= "other"
		count = i
	end
	auraCount = count
	return true
end

-- nil = not read yet this scan, false = can't be read, true = auraList is current
local passAuras

local function Matches(rec, ids, names)
	for i = 1, #ids do
		if ids[i] == rec.id then return true end
	end
	local name = rec.name
	if name then
		for i = 1, #names do
			if names[i] == name then return true end
		end
	end
	return false
end

local best = {}
local function ReadSelf(entry, cache)
	local ids, names, guessed = ns.Candidates(entry)
	cache.na = false

	if passAuras == nil then
		local ok, readable = pcall(ReadAuras)
		passAuras = ok and readable or false
	end
	if passAuras then
		-- Everything on you can be read: look at all of it and keep the
		-- match that lasts longest, in case several buffs fit (two buffs
		-- with the same name, or a learned buff beside the usual one).
		local found, expires, duration = false, nil, nil
		for i = 1, auraCount do
			local rec = auraList[i]
			-- A guess that matches something under a minute long is the wrong
			-- buff, like the "Food" effect while you sit and eat.
			if Matches(rec, ids, names) and not (guessed and rec.duration > 0 and rec.duration < 60) then
				if not found or rec.expires == 0 or (expires ~= 0 and rec.expires > expires) then
					expires, duration = rec.expires, rec.duration
				end
				found = true
			end
		end
		cache.predicted = false
		if found and expires == 0 and entry.learned and not (entry.auraName and entry.auraName ~= "") then
			-- A learned buff with no timer can't be what a consumable gives
			-- (it's a passive or a stance that happened to appear while the
			-- item was used). Forget it and go back to the plain guess.
			entry.learned = nil
			cache.active, cache.expires, cache.duration = false, nil, nil
			ns.RequestScan()
			if ns.RefreshOptions then ns.RefreshOptions() end
		elseif found then
			cache.active, cache.expires, cache.duration = true, expires, duration
			if duration > 0 then entry.dur = duration end
		else
			cache.active, cache.expires, cache.duration = false, nil, nil
		end
		return
	end

	-- Restricted: ask about each candidate directly, which still answers for
	-- buffs the game never hides.
	best.found, best.expires, best.duration = false, nil, nil
	for _, id in ipairs(ids) do
		Consider(best, Call(C_UnitAuras.GetPlayerAuraBySpellID, id), guessed)
	end
	for _, name in ipairs(names) do
		Consider(best, Call(C_UnitAuras.GetAuraDataBySpellName, "player", name, "HELPFUL"), guessed)
	end

	if best.found then
		cache.active, cache.predicted = true, false
		if best.expires then
			cache.expires, cache.duration = best.expires, best.duration
			if best.duration and best.duration > 0 then entry.dur = best.duration end
		end
	elseif ns.AurasSecret() and not AllNeverSecret(ids, names) then
		-- Can't tell missing from hidden: keep what we knew.
		cache.predicted = cache.active and true or false
	else
		cache.active, cache.expires, cache.duration, cache.predicted = false, nil, nil, false
	end
end

---------------------------------------------------------------------------
-- Reading weapon enchants
---------------------------------------------------------------------------
-- The timed enchants on a hand: { temp = {...}, imbue = {...} }, either may
-- be missing. Returns nil when the game won't say.
function ns.ReadEnchants(slot)
	local result = {}
	if C_Item and C_Item.GetWeaponEnchantInfo then
		local hand = slot == MAIN_HAND and 0 or 1
		if Enum and Enum.WeaponSlot then
			hand = slot == MAIN_HAND and Enum.WeaponSlot.MainHand or Enum.WeaponSlot.OffHand
		end
		local ok, list = pcall(C_Item.GetWeaponEnchantInfo, hand)
		if not ok or type(list) ~= "table" or Secret(list) then return nil end
		local types = Enum and Enum.ItemEnchantType
		local tempType, imbueType = types and types.Temporary or 2, types and types.Imbue or 3
		for _, info in pairs(list) do
			if Secret(info) or type(info) ~= "table" then return nil end
			local has, kind = info.hasEnchant, info.enchantType
			if Secret(has) or Secret(kind) then return nil end
			if has and (kind == tempType or kind == imbueType) then
				result[kind == tempType and "temp" or "imbue"] = {
					left = Num(info.timeLeft) or 0,
					charges = Num(info.charges),
					id = Num(info.enchantID),
				}
			end
		end
		return result
	end
	if GetWeaponEnchantInfo then
		-- Older call: one enchant per hand, kind unknown, so it counts as both.
		local ok, hasMain, leftMain, chargesMain, idMain, hasOff, leftOff, chargesOff, idOff = pcall(GetWeaponEnchantInfo)
		if not ok or Secret(hasMain) or Secret(hasOff) then return nil end
		local has, left, charges, id = hasMain, leftMain, chargesMain, idMain
		if slot == OFF_HAND then has, left, charges, id = hasOff, leftOff, chargesOff, idOff end
		if has then
			local info = { left = Num(left) or 0, charges = Num(charges), id = Num(id) }
			result.temp, result.imbue = info, info
		end
		return result
	end
	return nil
end

-- Each hand is read once per scan however many icons look at it.
local weaponMemo, enchantMemo = {}, {}

local function HasWeapon(slot)
	local value = weaponMemo[slot]
	if value == nil then
		value = ns.SlotHasWeapon(slot)
		weaponMemo[slot] = value
	end
	return value
end

local function Enchants(slot)
	local value = enchantMemo[slot]
	if value == nil then
		value = ns.ReadEnchants(slot) or false
		enchantMemo[slot] = value
	end
	return value or nil
end

function ns.SlotHasWeapon(slot)
	local itemID = Num(Call(GetInventoryItemID, "player", slot))
	if not itemID then return false end
	local classID = ns.ItemClass(itemID)
	return classID == nil or classID == 2
end

-- Which of the two enchant slots this item fills: "temp", "imbue" or nil
-- when it isn't known yet.
function ns.EnchantKind(entry)
	if entry.slotType == "temp" or entry.slotType == "imbue" then return entry.slotType end
	return ns.WEAPON_ITEMS[entry.id] or entry.learnedKind
end

local function ReadWeapon(entry, slot, cache, now)
	if not HasWeapon(slot) then
		cache.na, cache.active, cache.expires = true, false, nil
		return
	end
	cache.na = false
	local enchants = Enchants(slot)
	if not enchants then
		cache.predicted = cache.active and true or false
		return
	end
	local kind = ns.EnchantKind(entry)
	local info
	if kind then
		info = enchants[kind]
	else
		info = enchants.temp or enchants.imbue
		if enchants.temp and enchants.imbue and enchants.imbue.left > enchants.temp.left then
			info = enchants.imbue
		end
	end
	cache.predicted = false
	if info then
		local left = info.left / 1000
		cache.active = true
		cache.expires = left > 0 and now + left or 0
		cache.charges = info.charges
		if left > (entry.dur or 0) then entry.dur = left end
		cache.duration = entry.dur
	else
		cache.active, cache.expires, cache.charges = false, nil, nil
	end
end

---------------------------------------------------------------------------
-- View-only items
---------------------------------------------------------------------------
-- Nothing to track but how many you carry: fine, running low, or out.
local function ReadView(entry, cache)
	local count = ns.ItemCount(entry.id)
	cache.na, cache.predicted, cache.expires, cache.duration = false, false, nil, nil
	cache.count = count
	cache.active = count > 0
	cache.low = count > 0 and entry.low ~= nil and count <= entry.low
end

---------------------------------------------------------------------------
-- Status
---------------------------------------------------------------------------
-- active | expiring | missing | na (no weapon in that hand)
-- For view-only items: enough | running low | none left.
local function Finish(entry, cache, now)
	local status
	cache.threshold = nil
	if entry.kind == "view" then
		status = (not cache.active and "missing") or (cache.low and "expiring") or "active"
	elseif cache.na then
		status = "na"
	elseif not cache.active then
		status = "missing"
	else
		status = "active"
		local expires = cache.expires
		if expires and expires > 0 then
			local left = expires - now
			if left <= 0 then
				status = "missing"
			else
				local threshold = entry.warn or ns.db.warn
				local duration = cache.duration or entry.dur
				if duration and duration > 0 then threshold = math.min(threshold, duration / 3) end
				cache.threshold = threshold
				if left <= threshold then status = "expiring" end
			end
		end
	end
	cache.status = status
	return status
end

-- Seconds until this icon will look different without anything happening:
-- its timer text ticking over, the warning time arriving, or the buff
-- running out. nil when it won't change until the game reports something.
local function NextChange(button, cache, now)
	local delay
	local expires = cache.expires
	if cache.active and expires and expires > now then
		local left = expires - now
		delay = left
		local threshold = cache.threshold
		if threshold and left > threshold then delay = left - threshold end
		if ns.db.bar.showTimer then
			-- "2h" changes on the half hour, "12m" on the minute, "45" each second.
			local tick
			if left >= 5400 then
				tick = (left + 1800) % 3600
			elseif left >= 60 then
				tick = left % 60
			else
				tick = left % 1
			end
			if tick < delay then delay = tick end
		end
		delay = delay + 0.02
	end
	return delay
end

-- What needs reading from the game. Events mark the part they are about;
-- an update then asks the game only for that, and for nothing at all when
-- it was woken just to let a timer tick.
local dirtyAuras, dirtyWeapons, dirtyBags = true, true, true
local weaponReadDue = 0
local WEAPON_REREAD = 15

function ns.MarkDirty(what)
	if what == "auras" then
		dirtyAuras = true
	elseif what == "weapons" then
		dirtyWeapons = true
	elseif what == "bags" then
		dirtyBags = true
	else
		dirtyAuras, dirtyWeapons, dirtyBags = true, true, true
	end
end

-- The one update routine: reads whatever is marked dirty, works out each
-- icon's status, repaints what changed, and books the next wake-up.
function ns.Update()
	if not ns.bar then return end
	local now = GetTime()
	local readAuras, readWeapons, readBags = dirtyAuras, dirtyWeapons, dirtyBags
	dirtyAuras, dirtyWeapons, dirtyBags = false, false, false
	local attention, wake, hasWeapon = false, nil, false
	passAuras = nil
	-- Learning reads your buffs; when it has, the icons below reuse that read.
	if readAuras and ns.learning then passAuras = ns.CheckLearning() or nil end
	weaponMemo[MAIN_HAND], weaponMemo[OFF_HAND] = nil, nil
	enchantMemo[MAIN_HAND], enchantMemo[OFF_HAND] = nil, nil
	local buttons = ns.buttons
	for i = 1, #buttons do
		local button = buttons[i]
		local entry, cache = button.entry, button.cache
		if entry.kind == "view" then
			if readBags or not cache.status then ReadView(entry, cache) end
		elseif button.slot then
			hasWeapon = true
			-- Weapon enchants are reported by events, the same ones Blizzard's
			-- own buff frame relies on; a slow re-read backs them up.
			if readWeapons or not cache.status or now >= weaponReadDue then
				readWeapons = true
				ReadWeapon(entry, button.slot, cache, now)
			end
		elseif readAuras or not cache.status then
			ReadSelf(entry, cache)
		end
		local status = Finish(entry, cache, now)
		if status == "missing" or status == "expiring" then attention = true end
		button.state = cache
		ns.PaintButton(button, now)
		local delay = NextChange(button, cache, now)
		if delay and (not wake or delay < wake) then wake = delay end
	end
	if hasWeapon then
		if readWeapons then weaponReadDue = now + WEAPON_REREAD end
		local delay = weaponReadDue - now
		if not wake or delay < wake then wake = delay end
	end
	ns.SetAttention(attention)
	if wake then ns.ScheduleWake(wake) end
end

-- From here until combat ends, self buffs run on the timers just read: flag
-- them so tooltips can say the time is an estimate.
function ns.MarkEstimated()
	if ns.liveInCombat then return end
	for _, button in ipairs(ns.buttons) do
		if button.entry.kind == "self" and button.cache.active then button.cache.predicted = true end
	end
end

-- True when a tracked buff can still be read in combat, which is the only
-- case where buff events are worth listening to during a fight.
function ns.AnyLiveInCombat()
	for _, button in ipairs(ns.buttons) do
		local entry = button.entry
		if entry.kind == "self" then
			local ids, names = ns.Candidates(entry)
			if AllNeverSecret(ids, names) then return true end
		end
	end
	return false
end

-- Reads everything again from the game.
function ns.Scan()
	ns.MarkDirty()
	ns.Update()
end

-- Repaints from what is already known, without asking the game anything.
function ns.Repaint()
	ns.Update()
end

---------------------------------------------------------------------------
-- Learning from what you use
---------------------------------------------------------------------------
local wellFedNames
local function IsWellFedName(name)
	if not name then return false end
	if not wellFedNames then
		local names, any = {}, false
		for _, spellID in ipairs(ns.WELL_FED_SPELLS) do
			local known = SpellName(spellID)
			if known then names[known], any = true, true end
		end
		if not any then return false end -- spell names not loaded yet: try again later
		wellFedNames = names
	end
	return wellFedNames[name] == true
end

local function Outlasts(a, b)
	if a.expires == 0 then return b.expires ~= 0 end
	if b.expires == 0 then return false end
	return a.expires > b.expires + 1
end

-- Some items leave a buff that isn't the spell they cast (food leaves Well
-- Fed). For 45 seconds after such an item is used, the buffs that newly
-- appear on you are weighed, and the best one is remembered as that item's
-- buff (returns true when it has just read your buffs):
--   1. the item's own spell, then
--   2. a buff called Well Fed, then
--   3. a buff the game says you cast, the longest first, then
--   4. a buff whose caster the game doesn't report, the longest first.
-- Buffs known to come from someone else (a group member, an NPC) are
-- ignored, and so are buffs with no timer (passives, stances and the like,
-- which no consumable gives). Every use weighs them again, so a wrong choice
-- corrects itself the next time you use the item.
function ns.CheckLearning()
	local learning = ns.learning
	if not learning then return end
	if GetTime() - learning.time > 45 then
		ns.learning = nil
		return
	end
	local ok, readable = pcall(ReadAuras)
	if not ok or not readable then return end

	local entry = learning.entry
	local current = entry.learned
	local _, useSpell = ns.ItemSpell(entry.id)
	local pick, pickScore
	for i = 1, auraCount do
		local rec = auraList[i]
		local fresh = rec.mine and rec.duration >= 60 and rec.expires > 0
			and (rec.expires - rec.duration) >= learning.time - 0.3
		if fresh then
			local score = (rec.id == useSpell and 4) or (IsWellFedName(rec.name) and 3) or (rec.caster == "self" and 2) or 1
			local better = not pick or score > pickScore
			if not better and score == pickScore then
				-- on a tie: the longer buff, else stay with what was learned before
				better = Outlasts(rec, pick) or (current ~= nil and rec.id == current.id and not Outlasts(pick, rec))
			end
			if better then pick, pickScore = rec, score end
		end
	end
	if not pick then return true end

	-- Nothing needs remembering when the item would be tracked by that buff
	-- anyway: its own spell, or Well Fed for an item the game calls food.
	local plain = pick.id == useSpell or (ns.IsFood(entry.id) and IsWellFedName(pick.name))
	local changed = false
	if plain then
		if current then
			entry.learned = nil
			changed = true
		end
	elseif not current or current.id ~= pick.id then
		entry.learned = { id = pick.id, name = pick.name }
		changed = true
		ns.Print(("%s: tracking the buff \"%s\" from now on."):format(ns.ItemName(entry.id), pick.name or pick.id))
	end
	if changed then
		ns.RequestScan("auras")
		if ns.RefreshOptions then ns.RefreshOptions() end
	end
	return true -- the buff list read above is current
end

-- For /ccb buffs: what each self-buff icon is looking for and what it found,
-- then every long buff on you, so a wrong match is easy to spot.
function ns.DebugBuffs()
	local ok, readable = pcall(ReadAuras)
	passAuras = nil
	if not ok or not readable then
		ns.Print("Your buffs can't be read right now (the game hides them in combat). Try again out of combat.")
		return
	end
	local now = GetTime()
	local function Describe(rec)
		local left = rec.expires > 0 and ns.FormatClock(rec.expires - now) or "no timer"
		local total = rec.duration > 0 and (" of " .. ns.FormatClock(rec.duration)) or ""
		local rate = rec.timeMod and rec.timeMod ~= 1 and (", time rate " .. rec.timeMod) or ""
		local caster = (rec.caster == "other" and ", not cast by you") or (rec.caster == "unknown" and ", caster not reported") or ""
		return ("%s (spell %d): %s%s%s%s"):format(rec.name or "?", rec.id, left, total, rate, caster)
	end
	local any = false
	for _, button in ipairs(ns.buttons) do
		local entry = button.entry
		if entry.kind == "self" then
			any = true
			local ids, names, guessed = ns.Candidates(entry)
			local wanted = {}
			for _, name in ipairs(names) do wanted[#wanted + 1] = "\"" .. name .. "\"" end
			for _, id in ipairs(ids) do wanted[#wanted + 1] = "spell " .. id end
			local source = (entry.auraName and entry.auraName ~= "" and "typed") or (entry.learned and "learned") or "guessed"
			ns.Print(("%s looks for %s (%s). Status: %s."):format(ns.ItemName(entry.id),
				#wanted > 0 and table.concat(wanted, " or ") or "nothing yet", source, tostring(button.state and button.state.status)))
			local matched = false
			for i = 1, auraCount do
				local rec = auraList[i]
				if Matches(rec, ids, names) and not (guessed and rec.duration > 0 and rec.duration < 60) then
					matched = true
					ns.Print("   matches " .. Describe(rec))
				end
			end
			if not matched then ns.Print("   no matching buff on you") end
		end
	end
	if not any then ns.Print("No self-buff icons on the bar.") end
	ns.Print("Long buffs on you now:")
	local shown = 0
	for i = 1, auraCount do
		local rec = auraList[i]
		if (rec.duration == 0 or rec.duration >= 60) and shown < 20 then
			shown = shown + 1
			ns.Print("   " .. Describe(rec))
		end
	end
	if shown == 0 then ns.Print("   none") end
end

local lastGain, lastEnchants

local function SnapshotEnchants()
	return { [MAIN_HAND] = ns.ReadEnchants(MAIN_HAND) or {}, [OFF_HAND] = ns.ReadEnchants(OFF_HAND) or {} }
end

-- Learning which enchant slot an item fills only matters while a weapon item
-- of unknown kind is on the bar. Otherwise enchant events skip that work.
function ns.UpdateLearnFlag()
	local need = false
	for _, entry in ipairs(ns.entries) do
		if entry.kind == "weapon" and not ns.EnchantKind(entry) then need = true end
	end
	ns.learnKinds = need
	lastEnchants = need and SnapshotEnchants() or nil
end

function ns.CheckWeaponLearn()
	local pending = ns.weaponPending
	if not pending or not lastGain then return end
	-- The enchant has to land with the cast: just before it or soon after.
	if lastGain.time >= pending.time - 0.5 and lastGain.time <= pending.time + 3 then
		local entry = pending.entry
		if entry.slotType == "auto" and not ns.WEAPON_ITEMS[entry.id] and entry.learnedKind ~= lastGain.kind then
			entry.learnedKind = lastGain.kind
			ns.UpdateLearnFlag()
			if ns.RefreshOptions then ns.RefreshOptions() end
		end
		ns.weaponPending = nil
	end
end

-- Notices which enchant slot was just filled, to learn what kind of weapon
-- buff an unknown item is.
function ns.OnEnchantChanged()
	if not ns.learnKinds then return end
	local now = GetTime()
	local current = SnapshotEnchants()
	if lastEnchants then
		for slot, enchants in pairs(current) do
			for kind, info in pairs(enchants) do
				local old = lastEnchants[slot][kind]
				if not old or old.id ~= info.id or info.left > old.left + 5000 then
					lastGain = { time = now, kind = kind }
				end
			end
		end
	end
	lastEnchants = current
	ns.CheckWeaponLearn()
end

-- [spell ID] = the tracked items that cast it, so each of your casts costs
-- one table lookup. Rebuilt when the list changes.
local function SpellMap()
	local map = ns.spellMap
	if map then return map end
	map = {}
	for _, entry in ipairs(ns.entries) do
		if entry.kind ~= "view" then
			local _, spellID = ns.ItemSpell(entry.id)
			if spellID then
				local list = map[spellID]
				if not list then
					list = {}
					map[spellID] = list
				end
				list[#list + 1] = entry
			else
				ns.ItemName(entry.id) -- not loaded yet: asks for it, and the map is rebuilt when it arrives
			end
		end
	end
	ns.spellMap = map
	return map
end

-- Any use of a tracked consumable, from the bar or from your bags.
function ns.OnCastSucceeded(spellID)
	spellID = Num(spellID)
	if not spellID or not ns.db then return end
	local list = SpellMap()[spellID]
	if not list then return end
	local now = GetTime()
	for _, entry in ipairs(list) do
		if entry.kind == "weapon" then
			ns.weaponPending = { entry = entry, time = now }
			ns.CheckWeaponLearn()
		elseif ns.AurasSecret() then
			-- The new buff can't be read yet: assume it's up, for as long as
			-- it lasted the last time it was seen.
			local cache = ns.cache[entry.id .. ":0"]
			if cache then
				cache.active, cache.predicted = true, true
				cache.expires = entry.dur and now + entry.dur or nil
				cache.duration = entry.dur
			end
		elseif not (entry.auraName and entry.auraName ~= "") then
			-- Watch what the item adds over the next moments.
			ns.learning = { entry = entry, time = now }
		end
	end
	ns.RequestScan("auras")
end
