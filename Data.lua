-- Data: the few things the addon can't work out by itself.
local _, ns = ...

-- On Forever a weapon has two timed enchant slots that can be filled at the
-- same time: "temp" (sharpening stones, weightstones, oils) and "imbue"
-- (poisons, Firestone, Spellstone). Items listed here are known weapon
-- consumables; anything else is learned the first time you apply it, or can
-- be set by hand in the menu.
ns.WEAPON_ITEMS = {
	-- Sharpening stones: Rough, Coarse, Heavy, Solid, Dense, Elemental, Consecrated
	[2862] = "temp", [2863] = "temp", [2871] = "temp", [7964] = "temp",
	[12404] = "temp", [18262] = "temp", [23122] = "temp",
	-- Weightstones: Rough, Coarse, Heavy, Solid, Dense
	[3239] = "temp", [3240] = "temp", [3241] = "temp", [7965] = "temp", [12643] = "temp",
	-- Wizard oils: Minor, Lesser, Wizard, Brilliant, Blessed
	[20744] = "temp", [20746] = "temp", [20750] = "temp", [20749] = "temp", [23123] = "temp",
	-- Mana oils: Minor, Lesser, Brilliant
	[20745] = "temp", [20747] = "temp", [20748] = "temp",
	-- Shadow Oil, Frost Oil
	[3824] = "temp", [3829] = "temp",
	-- Instant Poison I to VI
	[6947] = "imbue", [6949] = "imbue", [6950] = "imbue", [8926] = "imbue", [8927] = "imbue", [8928] = "imbue",
	-- Deadly Poison I to V
	[2892] = "imbue", [2893] = "imbue", [8984] = "imbue", [8985] = "imbue", [20844] = "imbue",
	-- Wound Poison I to IV
	[10918] = "imbue", [10920] = "imbue", [10921] = "imbue", [10922] = "imbue",
	-- Mind-numbing Poison I to III
	[5237] = "imbue", [6951] = "imbue", [9186] = "imbue",
	-- Crippling Poison I, II
	[3775] = "imbue", [3776] = "imbue",
	-- Firestones: Lesser, Firestone, Greater, Major
	[1254] = "imbue", [13699] = "imbue", [13700] = "imbue", [13701] = "imbue",
	-- Spellstones: Spellstone, Greater, Major
	[5522] = "imbue", [13602] = "imbue", [13603] = "imbue",
}

-- Food leaves a buff with a different name from the "Food" spell the item
-- casts. These spells are only used for their (localized) name, as a first
-- guess; the real buff is learned the first time you eat.
ns.WELL_FED_SPELLS = { 19705, 1249519 }

-- The sit-and-eat spell that food items cast, again only for its localized
-- name: an item whose use effect has this name is food, whatever category
-- the game files it under.
ns.FOOD_SPELLS = { 433, 5004 }

ns.GLOW_STYLES = { "pulse", "pixel", "solid", "blink" }
ns.GLOW_STYLE_NAMES = {
	pulse = "Soft Pulse",
	pixel = "Marching Pixels",
	solid = "Solid Border",
	blink = "Blinking Border",
}
