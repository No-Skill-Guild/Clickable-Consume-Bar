-- Options: the menu. Five pages: which consumables are on the bar, profiles,
-- when the bar is shown, how the glows look, and how the bar is laid out.
--
-- The window is drawn in a flat dark style (solid panels, one pixel borders,
-- an accent color on hover) with its own widgets instead of Blizzard's
-- templates. If ElvUI is installed its accent color, panel colors and font
-- are used, so the menu matches the rest of the interface.
local _, ns = ...

local Num, Call = ns.Num, ns.Call

local win
local pages, tabs = {}, {}
local refreshers = {}   -- functions that reload every control from the saved settings

local ROW_HEIGHT = 28
local CONTENT_WIDTH = 670
local LIST_HEIGHT = 406

---------------------------------------------------------------------------
-- Theme
---------------------------------------------------------------------------
local theme = {
	window = { 0.06, 0.06, 0.06, 0.95 },
	panel = { 0.1, 0.1, 0.1, 0.6 },
	widget = { 0.13, 0.13, 0.13, 1 },
	border = { 0, 0, 0 },
	accent = { 0.09, 0.52, 0.82 },
	text = { 0.92, 0.92, 0.92 },
	dim = { 0.55, 0.55, 0.55 },
	font = nil, -- nil keeps the game's own font
}

-- A color stored either as { r =, g =, b = } or as { r, g, b }.
local function ReadColor(color)
	if type(color) ~= "table" then return nil end
	local r, g, b, a = color.r or color[1], color.g or color[2], color.b or color[3], color.a or color[4]
	if type(r) == "number" and type(g) == "number" and type(b) == "number" then
		return r, g, b, type(a) == "number" and a or nil
	end
end

local function LoadElvUITheme()
	pcall(function()
		local engine = type(ElvUI) == "table" and ElvUI[1]
		local media = type(engine) == "table" and engine.media
		if type(media) ~= "table" then return end
		local r, g, b, a = ReadColor(media.rgbvaluecolor)
		if r then theme.accent = { r, g, b } end
		r, g, b = ReadColor(media.bordercolor)
		if r then theme.border = { r, g, b } end
		r, g, b = ReadColor(media.backdropcolor)
		if r then
			theme.widget = { r, g, b, 1 }
			theme.panel = { r, g, b, 0.6 }
		end
		r, g, b, a = ReadColor(media.backdropfadecolor)
		if r then theme.window = { r, g, b, math.max(a or 0.8, 0.9) } end
		if type(media.normFont) == "string" and media.normFont ~= "" then theme.font = media.normFont end
	end)
end

local function SetEdgeColor(frame, color)
	for i = 1, 4 do frame.edges[i]:SetColorTexture(color[1], color[2], color[3], 1) end
end

-- Gives a frame a flat background and a one pixel border.
local function Skin(frame, color)
	color = color or theme.widget
	frame.bg = frame:CreateTexture(nil, "BACKGROUND")
	frame.bg:SetAllPoints(frame)
	frame.bg:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
	local top, bottom, left, right = frame:CreateTexture(nil, "BORDER"), frame:CreateTexture(nil, "BORDER"),
		frame:CreateTexture(nil, "BORDER"), frame:CreateTexture(nil, "BORDER")
	top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	top:SetHeight(1)
	bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	bottom:SetHeight(1)
	left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	left:SetWidth(1)
	right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	right:SetWidth(1)
	frame.edges = { top, bottom, left, right }
	SetEdgeColor(frame, theme.border)
end

local function Text(parent, text, size, color)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	local path, _, flags = fs:GetFont()
	path = theme.font or path
	if path then fs:SetFont(path, size or 12, flags or "") end
	color = color or theme.text
	fs:SetTextColor(color[1], color[2], color[3])
	fs:SetJustifyH("LEFT")
	fs:SetText(text or "")
	return fs
end

---------------------------------------------------------------------------
-- Applying a change
---------------------------------------------------------------------------
local warnedCombat
local function LayoutChanged()
	if ns.InCombat() and not warnedCombat then
		warnedCombat = true
		ns.Print("You're in combat: changes to the bar itself apply when combat ends.")
	end
	ns.Rebuild()
end

local function LookChanged()
	ns.Invalidate()
	ns.UpdateVisibility()
	ns.Repaint()
end

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------
local function Tip(widget, title, text)
	widget:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(title)
		if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
		GameTooltip:Show()
	end)
	widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Button(parent, text, width, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, 20)
	Skin(b)
	b.label = Text(b, text, 11)
	b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
	b.label:SetJustifyH("CENTER")
	b:SetFontString(b.label)
	b:SetText(text)
	b:SetScript("OnEnter", function(self) SetEdgeColor(self, theme.accent) end)
	b:SetScript("OnLeave", function(self) SetEdgeColor(self, self.selected and theme.accent or theme.border) end)
	b:SetScript("OnClick", onClick)
	return b
end

local function SetCheck(box, value)
	value = value and true or false
	box:SetChecked(value)
	box.mark:SetShown(value)
end

-- A flat checkbox. With `text` it gets a label that can be clicked too.
local function CheckBox(parent, text, onClick)
	local c = CreateFrame("CheckButton", nil, parent)
	c:SetSize(16, 16)
	Skin(c)
	c.mark = c:CreateTexture(nil, "ARTWORK")
	c.mark:SetPoint("TOPLEFT", c, "TOPLEFT", 3, -3)
	c.mark:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -3, 3)
	c.mark:SetColorTexture(theme.accent[1], theme.accent[2], theme.accent[3], 1)
	c.mark:Hide()
	if text then
		c.label = Text(c, text, 12)
		c.label:SetPoint("LEFT", c, "RIGHT", 6, 0)
		local width = c.label:GetStringWidth()
		if not width or width <= 0 then width = #text * 6 end
		c:SetHitRectInsets(0, -(width + 8), 0, 0)
	end
	c:SetScript("OnEnter", function(self) SetEdgeColor(self, theme.accent) end)
	c:SetScript("OnLeave", function(self) SetEdgeColor(self, theme.border) end)
	c:SetScript("OnClick", function(self)
		local checked = self:GetChecked() and true or false
		self.mark:SetShown(checked)
		onClick(self, checked)
	end)
	return c
end

local function Check(parent, text, get, set)
	local c = CheckBox(parent, text, function(_, checked) set(checked) end)
	c.Refresh = function() SetCheck(c, get()) end
	refreshers[#refreshers + 1] = c.Refresh
	return c
end

-- An accent-colored heading with a thin rule under it.
local function Header(parent, text, x, y, width)
	local heading = Text(parent, text, 13, theme.accent)
	heading:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	local rule = parent:CreateTexture(nil, "ARTWORK")
	rule:SetColorTexture(theme.accent[1], theme.accent[2], theme.accent[3], 0.35)
	rule:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 17)
	rule:SetSize(width, 1)
	return heading
end

-- A heading and a column of checkboxes of which exactly one is ticked.
local function Choice(parent, title, options, get, set, x, y)
	Header(parent, title, x, y, 270)
	local boxes = {}
	local function RefreshAll()
		for _, box in ipairs(boxes) do SetCheck(box, get() == box.value) end
	end
	for i, option in ipairs(options) do
		local box = CheckBox(parent, option[2], function(self)
			set(self.value)
			RefreshAll()
		end)
		box.value = option[1]
		box:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 4, y - 4 - i * 22)
		boxes[i] = box
	end
	refreshers[#refreshers + 1] = RefreshAll
	return y - 22 - (#options + 1) * 22
end

-- Blizzard's thumb art is replaced by a flat block in the accent color.
local function FlatThumb(slider, width, height)
	slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	local thumb = slider:GetThumbTexture()
	if thumb then
		thumb:SetColorTexture(theme.accent[1], theme.accent[2], theme.accent[3], 1)
		thumb:SetSize(width, height)
	end
end

local function Slider(parent, text, low, high, step, get, set, format)
	local s = CreateFrame("Slider", nil, parent)
	s:SetOrientation("HORIZONTAL")
	s:EnableMouse(true)
	s:SetSize(230, 12)
	Skin(s)
	FlatThumb(s, 10, 12)
	s:SetMinMaxValues(low, high)
	s:SetValueStep(step)
	s:SetObeyStepOnDrag(true)
	format = format or tostring
	s.caption = Text(s, text, 12)
	s.caption:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 5)
	s.value = Text(s, "", 12, theme.accent)
	s.value:SetPoint("BOTTOMRIGHT", s, "TOPRIGHT", 0, 5)
	s:SetScript("OnEnter", function(self) SetEdgeColor(self, theme.accent) end)
	s:SetScript("OnLeave", function(self) SetEdgeColor(self, theme.border) end)
	s:SetScript("OnValueChanged", function(self, value)
		if self.loading then return end
		value = math.floor(value / step + 0.5) * step
		set(value)
		self.value:SetText(format(value))
	end)
	s.Refresh = function()
		s.loading = true
		s:SetValue(get())
		s.loading = false
		s.value:SetText(format(get()))
	end
	refreshers[#refreshers + 1] = s.Refresh
	return s
end

-- A flat text box. Set `onBlur(self, cancelled)` to act when typing ends;
-- Enter confirms and Escape cancels.
local function EditBox(parent, width)
	local e = CreateFrame("EditBox", nil, parent)
	e:SetSize(width, 20)
	Skin(e)
	e:SetFontObject("GameFontHighlightSmall")
	if theme.font then e:SetFont(theme.font, 11, "") end
	e:SetTextInsets(4, 4, 0, 0)
	e:SetAutoFocus(false)
	e:SetScript("OnEditFocusGained", function(self)
		self.cancelled = nil
		SetEdgeColor(self, theme.accent)
		if self.onFocus then self.onFocus(self) end
	end)
	e:SetScript("OnEditFocusLost", function(self)
		SetEdgeColor(self, theme.border)
		if self.onBlur then self.onBlur(self, self.cancelled) end
	end)
	e:SetScript("OnEscapePressed", function(self)
		self.cancelled = true
		self:ClearFocus()
	end)
	e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	return e
end

local function Trim(text)
	return (text or ""):match("^%s*(.-)%s*$")
end

local function Clock(seconds)
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

---------------------------------------------------------------------------
-- Page 1: consumables
---------------------------------------------------------------------------
local rows = {}
local listContent, listBar, addBox

local KIND_LABELS = { self = "Self", weapon = "Weapon", view = "View Only" }
local KIND_NEXT = { self = "weapon", weapon = "view", view = "self" }
local SLOT_LABELS = { auto = "Auto", temp = "Stone / Oil", imbue = "Poison" }
local SLOT_NEXT = { auto = "temp", temp = "imbue", imbue = "auto" }

local function AddFromText(text)
	local id = ns.ResolveItem(text)
	local entry, err = ns.AddItem(id)
	if entry then
		ns.Print("Added " .. ns.ItemName(entry.id) .. ".")
	else
		ns.Print(err)
	end
	ns.RefreshOptions()
	return entry
end

-- An item held on the cursor and dropped on the menu.
local function TakeCursorItem()
	local kind, id = GetCursorInfo()
	if kind == "item" and id then
		ClearCursor()
		AddFromText(id)
		return true
	end
end

local function IsCandidate(id)
	if ns.WEAPON_ITEMS[id] then return true end
	local classID, subClassID = ns.ItemClass(id)
	-- Reagents have no use effect; they can go on the bar as view-only.
	if classID == 5 or (classID == 15 and subClassID == 1) then return true end
	if classID ~= 0 and classID ~= 7 and classID ~= 8 then return false end
	if classID == 0 and subClassID == 7 then return false end -- bandages
	return ns.ItemSpell(id) ~= nil
end

-- Usable items in your bags that aren't on the bar yet.
local function BagCandidates()
	local list, seen = {}, {}
	if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemID) then return list end
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		local slots = Num(Call(C_Container.GetContainerNumSlots, bag)) or 0
		for slot = 1, slots do
			local id = Num(Call(C_Container.GetContainerItemID, bag, slot))
			if id and not seen[id] then
				seen[id] = true
				if not ns.FindEntry(id) and IsCandidate(id) then list[#list + 1] = id end
			end
		end
	end
	-- Look each name up once, not on every comparison of the sort.
	local names = {}
	for _, id in ipairs(list) do names[id] = ns.ItemName(id) end
	table.sort(list, function(a, b) return names[a] < names[b] end)
	return list
end

local function CreateRow(index)
	local row = CreateFrame("Frame", nil, listContent)
	row:SetSize(CONTENT_WIDTH, ROW_HEIGHT)
	row:SetPoint("TOPLEFT", listContent, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(22, 22)
	row.icon:SetPoint("LEFT", row, "LEFT", 1, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	-- The name gets most of the column and the bag count its own slot, so a
	-- long name never pushes the count out of view.
	row.name = Text(row, "", 12)
	row.name:SetPoint("LEFT", row, "LEFT", 30, 0)
	row.name:SetWidth(186)
	row.name:SetWordWrap(false)
	row.count = Text(row, "", 11, theme.dim)
	row.count:SetPoint("RIGHT", row, "LEFT", 254, 0)
	row.count:SetJustifyH("RIGHT")

	-- Hovering the icon or name shows the item, full name included.
	row.hover = CreateFrame("Frame", nil, row)
	row.hover:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	row.hover:SetSize(254, ROW_HEIGHT)
	row.hover:EnableMouse(true)
	row.hover:SetScript("OnEnter", function(self)
		if not row.itemID then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
		if not pcall(GameTooltip.SetItemByID, GameTooltip, row.itemID) then
			GameTooltip:SetText(ns.ItemName(row.itemID))
		end
		GameTooltip:Show()
	end)
	row.hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row.hover:SetScript("OnReceiveDrag", TakeCursorItem)
	row.hover:SetScript("OnMouseUp", TakeCursorItem)

	row.header = Text(row, "", 13, theme.accent)
	row.header:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 6)
	row.rule = row:CreateTexture(nil, "ARTWORK")
	row.rule:SetColorTexture(theme.accent[1], theme.accent[2], theme.accent[3], 0.35)
	row.rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 2)
	row.rule:SetSize(CONTENT_WIDTH, 1)

	row.kind = Button(row, "", 62, function()
		local entry = row.entry
		if not entry then return end
		entry.kind = KIND_NEXT[entry.kind] or "self"
		LayoutChanged()
		ns.RefreshOptions()
	end)
	row.kind:SetPoint("LEFT", row, "LEFT", 260, 0)
	Tip(row.kind, "Icon Type", "Click to switch.\nSelf: a buff on you, like an elixir, flask, scroll or food.\nWeapon: applied to a weapon, like a sharpening stone, oil or poison.\nView Only: just shows how many you carry, like a reagent. Clicking it does nothing.")

	row.mh = CheckBox(row, nil, function(_, checked)
		if not row.entry then return end
		row.entry.mh = checked
		LayoutChanged()
	end)
	row.mh:SetPoint("LEFT", row, "LEFT", 330, 0)
	Tip(row.mh, "Main Hand", "Put an icon on the bar that applies this to your main hand weapon.")
	row.mhLabel = Text(row, "MH", 11, theme.dim)
	row.mhLabel:SetPoint("LEFT", row.mh, "RIGHT", 4, 0)

	row.oh = CheckBox(row, nil, function(_, checked)
		if not row.entry then return end
		row.entry.oh = checked
		LayoutChanged()
	end)
	row.oh:SetPoint("LEFT", row, "LEFT", 380, 0)
	Tip(row.oh, "Off Hand", "Put an icon on the bar that applies this to your off hand weapon.")
	row.ohLabel = Text(row, "OH", 11, theme.dim)
	row.ohLabel:SetPoint("LEFT", row.oh, "RIGHT", 4, 0)

	row.slot = Button(row, "", 82, function()
		local entry = row.entry
		if not entry then return end
		entry.slotType = SLOT_NEXT[entry.slotType or "auto"] or "auto"
		ns.RequestScan()
		ns.RefreshOptions()
	end)
	row.slot:SetPoint("LEFT", row, "LEFT", 430, 0)
	Tip(row.slot, "Weapon Enchant Type", "A weapon can carry a stone or oil and a poison at the same time, so the bar needs to know which one to look for.\nStone / Oil: sharpening stones, weightstones and oils.\nPoison: poisons, Firestone and Spellstone.\nAuto: known items are recognized, others are learned the first time you apply them.")

	row.aura = EditBox(row, 152)
	row.aura:SetPoint("LEFT", row, "LEFT", 330, 0)
	row.aura.onFocus = function() row.auraHint:Hide() end
	row.aura.onBlur = function(self, cancelled)
		local entry = row.entry
		if entry and not cancelled then
			local text = Trim(self:GetText())
			entry.auraName = text ~= "" and text or nil
			ns.RequestScan()
		end
		ns.RefreshOptions()
	end
	Tip(row.aura, "Buff To Look For", "Leave empty and the bar works it out: usually the buff has the item's own spell, and for items like food it's learned the first time you use one.\nType a buff name or spell ID to set it yourself.")
	-- Lives on the text box itself so the box's background can't cover it.
	row.auraHint = Text(row.aura, "", 11, theme.dim)
	row.auraHint:SetPoint("LEFT", row.aura, "LEFT", 5, 0)
	row.auraHint:SetWidth(142)
	row.auraHint:SetWordWrap(false)

	row.forget = Button(row, "R", 20, function()
		if not row.entry then return end
		row.entry.learned = nil
		ns.RequestScan()
		ns.RefreshOptions()
	end)
	row.forget:SetPoint("LEFT", row, "LEFT", 488, 0)
	Tip(row.forget, "Forget Learned Buff", "The buff will be learned again the next time you use the item.")

	row.warn = EditBox(row, 36)
	row.warn:SetPoint("LEFT", row, "LEFT", 520, 0)
	row.warn:SetNumeric(true)
	row.warn:SetMaxLetters(4)
	row.warn.onBlur = function(self, cancelled)
		local entry = row.entry
		if entry and not cancelled then
			local value = tonumber(self:GetText())
			entry.warn = value and value > 0 and value or nil
			ns.RequestScan()
		end
		ns.RefreshOptions()
	end
	Tip(row.warn, "Warn At (Seconds)", "Start the expiring glow this many seconds before the buff runs out. Leave empty to use the default from the Glow page.")
	row.warnLabel = Text(row, "Sec", 11, theme.dim)
	row.warnLabel:SetPoint("LEFT", row.warn, "RIGHT", 5, 0)

	row.viewHint = Text(row, "Shows How Many You Carry", 11, theme.dim)
	row.viewHint:SetPoint("LEFT", row, "LEFT", 332, 0)
	row.low = EditBox(row, 36)
	row.low:SetPoint("LEFT", row, "LEFT", 520, 0)
	row.low:SetNumeric(true)
	row.low:SetMaxLetters(4)
	row.low.onBlur = function(self, cancelled)
		local entry = row.entry
		if entry and not cancelled then
			local value = tonumber(self:GetText())
			entry.low = value and value > 0 and value or nil
			ns.RequestScan()
		end
		ns.RefreshOptions()
	end
	Tip(row.low, "Low At (Count)", "Glow like an expiring buff when you carry this many or fewer. Leave empty for no low warning. The icon is always desaturated when you have none.")
	row.lowLabel = Text(row, "Low", 11, theme.dim)
	row.lowLabel:SetPoint("LEFT", row.low, "RIGHT", 5, 0)

	row.up = Button(row, "<", 20, function()
		if not row.entry then return end
		ns.MoveItem(row.entry.id, -1)
		ns.RefreshOptions()
	end)
	row.up:SetPoint("LEFT", row, "LEFT", 602, 0)
	Tip(row.up, "Move Earlier")
	row.down = Button(row, ">", 20, function()
		if not row.entry then return end
		ns.MoveItem(row.entry.id, 1)
		ns.RefreshOptions()
	end)
	row.down:SetPoint("LEFT", row, "LEFT", 624, 0)
	Tip(row.down, "Move Later")
	row.remove = Button(row, "X", 20, function()
		if not row.entry then return end
		ns.RemoveItem(row.entry.id)
		ns.RefreshOptions()
	end)
	row.remove:SetPoint("LEFT", row, "LEFT", 648, 0)
	Tip(row.remove, "Remove")

	row.add = Button(row, "Add", 62, function()
		if not row.itemID then return end
		AddFromText(row.itemID)
	end)
	row.add:SetPoint("LEFT", row, "LEFT", 260, 0)

	row.tracked = { row.kind, row.up, row.down, row.remove }
	row.timed = { row.warn, row.warnLabel }
	row.viewOnly = { row.viewHint, row.low, row.lowLabel }
	row.weaponOnly = { row.mh, row.mhLabel, row.oh, row.ohLabel, row.slot }
	row.selfOnly = { row.aura, row.auraHint, row.forget }
	return row
end

local function SetShown(list, shown)
	for _, widget in ipairs(list) do widget:SetShown(shown) end
end

local function FillRow(row, item)
	row.entry, row.itemID = nil, nil
	local isHeader = item.header ~= nil
	row.header:SetShown(isHeader or item.note ~= nil)
	row.rule:SetShown(isHeader)
	local isItem = item.entry ~= nil or item.bagItem ~= nil
	row.icon:SetShown(isItem)
	row.name:SetShown(isItem)
	row.count:SetShown(isItem)
	row.hover:SetShown(isItem)
	SetShown(row.tracked, item.entry ~= nil)
	SetShown(row.timed, false)
	SetShown(row.viewOnly, false)
	SetShown(row.weaponOnly, false)
	SetShown(row.selfOnly, false)
	row.add:SetShown(item.bagItem ~= nil)

	if isHeader then
		row.header:SetText(item.header)
		row.header:SetTextColor(theme.accent[1], theme.accent[2], theme.accent[3])
		return
	elseif item.note then
		row.header:SetText(item.note)
		row.header:SetTextColor(theme.dim[1], theme.dim[2], theme.dim[3])
		return
	end

	local id = item.entry and item.entry.id or item.bagItem
	row.itemID = id
	row.icon:SetTexture(ns.ItemIcon(id))
	local count = ns.ItemCount(id)
	row.name:SetText(ns.ItemName(id))
	row.count:SetText(count > 0 and ("x" .. count) or "|cffff4444x0|r")

	local entry = item.entry
	if not entry then return end
	row.entry = entry
	row.kind:SetText(KIND_LABELS[entry.kind] or "Self")

	if entry.kind == "view" then
		SetShown(row.viewOnly, true)
		if not row.low:HasFocus() then row.low:SetText(entry.low and tostring(entry.low) or "") end
		return
	end
	SetShown(row.timed, true)
	if not row.warn:HasFocus() then row.warn:SetText(entry.warn and tostring(entry.warn) or "") end

	if entry.kind == "weapon" then
		SetShown(row.weaponOnly, true)
		SetCheck(row.mh, entry.mh)
		SetCheck(row.oh, entry.oh)
		local known = ns.WEAPON_ITEMS[entry.id]
		local label = SLOT_LABELS[entry.slotType or "auto"] or "Auto"
		if (entry.slotType or "auto") == "auto" then
			local kind = known or entry.learnedKind
			if kind then label = "Auto: " .. (kind == "temp" and "Stone" or "Poison") end
		end
		row.slot:SetText(label)
	else
		SetShown(row.selfOnly, true)
		row.forget:SetShown(entry.learned ~= nil)
		if not row.aura:HasFocus() then
			row.aura:SetText(entry.auraName or "")
			local hint = ns.TrackedBuffName(entry)
			row.auraHint:SetText(hint or "Learned On First Use")
			row.auraHint:SetShown(not entry.auraName or entry.auraName == "")
		else
			row.auraHint:Hide()
		end
	end
end

local function RefreshList()
	if not listContent then return end
	local items = {}
	items[#items + 1] = { header = "On The Bar  (Profile: " .. ns.db.profile .. ")" }
	for _, entry in ipairs(ns.entries) do items[#items + 1] = { entry = entry } end
	if #ns.entries == 0 then
		items[#items + 1] = { note = "Nothing yet. Add consumables from the list below." }
	end
	local bag = BagCandidates()
	items[#items + 1] = { header = "In Your Bags" }
	for _, id in ipairs(bag) do items[#items + 1] = { bagItem = id } end
	if #bag == 0 then
		items[#items + 1] = { note = "No other usable consumables found in your bags." }
	end

	for i, item in ipairs(items) do
		local row = rows[i]
		if not row then
			row = CreateRow(i)
			rows[i] = row
		end
		FillRow(row, item)
		row:Show()
	end
	for i = #items + 1, #rows do rows[i]:Hide() end

	local height = #items * ROW_HEIGHT
	listContent:SetHeight(math.max(1, height))
	local range = math.max(0, height - LIST_HEIGHT)
	listBar:SetMinMaxValues(0, range)
	if (listBar:GetValue() or 0) > range then listBar:SetValue(range) end
	listBar:SetShown(range > 0)
end

local function BuildConsumables(page)
	local help = Text(page, "Each icon uses its item when clicked. View Only icons just show how many you carry.", 11, theme.dim)
	help:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
	help:SetWidth(CONTENT_WIDTH)

	local addLabel = Text(page, "Add By Item ID, Link Or Name", 12)
	addLabel:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -26)

	addBox = EditBox(page, 230)
	addBox:SetPoint("TOPLEFT", page, "TOPLEFT", 200, -22)
	addBox:SetScript("OnEnterPressed", function(self)
		if AddFromText(self:GetText()) then self:SetText("") end
		self:ClearFocus()
	end)
	addBox:SetScript("OnReceiveDrag", TakeCursorItem)
	addBox:HookScript("OnMouseDown", TakeCursorItem)
	Tip(addBox, "Add A Consumable", "Type an item ID or the name of an item you're carrying and press Enter, or drop an item from your bags here.")

	local addButton = Button(page, "Add", 62, function()
		if AddFromText(addBox:GetText()) then addBox:SetText("") end
		addBox:ClearFocus()
	end)
	addButton:SetPoint("LEFT", addBox, "RIGHT", 6, 0)

	local scroll = CreateFrame("ScrollFrame", "ClickableConsumeBarOptionsScroll", page)
	scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -52)
	scroll:SetSize(CONTENT_WIDTH, LIST_HEIGHT)
	listContent = CreateFrame("Frame", nil, scroll)
	listContent:SetSize(CONTENT_WIDTH, 1)
	scroll:SetScrollChild(listContent)
	scroll:EnableMouse(true)
	scroll:SetScript("OnReceiveDrag", TakeCursorItem)
	scroll:SetScript("OnMouseUp", TakeCursorItem)

	listBar = CreateFrame("Slider", nil, page)
	listBar:SetOrientation("VERTICAL")
	listBar:EnableMouse(true)
	listBar:SetSize(8, LIST_HEIGHT)
	listBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
	Skin(listBar)
	FlatThumb(listBar, 8, 40)
	listBar:SetMinMaxValues(0, 0)
	listBar:SetValue(0)
	listBar:SetScript("OnValueChanged", function(_, value) scroll:SetVerticalScroll(value) end)

	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(_, delta)
		local low, high = listBar:GetMinMaxValues()
		local value = (listBar:GetValue() or 0) - delta * ROW_HEIGHT * 2
		listBar:SetValue(math.max(low or 0, math.min(high or 0, value)))
	end)

	refreshers[#refreshers + 1] = RefreshList
end

---------------------------------------------------------------------------
-- Page: profiles
---------------------------------------------------------------------------
local profileRows, autoButtons = {}, {}
local profileBox

local CONTEXTS = {
	{ "world", "Open World" },
	{ "party", "Dungeons" },
	{ "raid", "Raids" },
	{ "pvp", "Battlegrounds And Arenas" },
}

local function RefreshProfiles()
	local names = ns.ProfileNames()
	for i, row in ipairs(profileRows) do
		local name = names[i]
		row.profile, row.confirmDelete, row.confirmCopy = name, nil, nil
		row:SetShown(name ~= nil)
		if name then
			local active = name == ns.db.profile
			local color = active and theme.accent or theme.text
			local count = #ns.db.profiles[name].entries
			row.name:SetText(name)
			row.name:SetTextColor(color[1], color[2], color[3])
			row.count:SetText(count == 1 and "1 Item" or (count .. " Items"))
			row.active:SetShown(active)
			row.use:SetShown(not active)
			row.copy:SetShown(not active)
			row.copy:SetText("Copy From")
			row.delete:SetShown(not active)
			row.delete:SetText("Delete")
		end
	end
	for _, button in ipairs(autoButtons) do
		local name = ns.db.auto[button.context]
		if name and not ns.db.profiles[name] then
			name = nil
			ns.db.auto[button.context] = nil
		end
		button:SetText(name or "Don't Switch")
	end
end

local function NewProfile(copyFrom)
	local name, err = ns.CreateProfile(profileBox:GetText(), copyFrom)
	if name then
		profileBox:SetText("")
		ns.SwitchProfile(name)
		ns.Print("Profile \"" .. name .. "\" created and switched to.")
	else
		ns.Print(err)
	end
	profileBox:ClearFocus()
	ns.RefreshOptions()
end

-- One click: a Dungeon, a Raid and a PvP profile, each starting as a copy of
-- the current one, switched to automatically.
local function QuickSetup()
	local current = ns.db.profile
	local made = {}
	for _, spec in ipairs { { "party", "Dungeon" }, { "raid", "Raid" }, { "pvp", "PvP" } } do
		local context, name = spec[1], spec[2]
		if not ns.db.profiles[name] then
			local created, err = ns.CreateProfile(name, current)
			if created then made[#made + 1] = name else ns.Print(err) end
		end
		if ns.db.profiles[name] then ns.db.auto[context] = name end
	end
	if not ns.db.auto.world then ns.db.auto.world = current end
	if #made > 0 then
		ns.Print("Created " .. table.concat(made, ", ") .. " as copies of \"" .. current .. "\". Switch to each one to change its list.")
	else
		ns.Print("Dungeon, Raid and PvP profiles already exist; automatic switching is set.")
	end
	ns.RefreshOptions()
end

local function BuildProfiles(page)
	Header(page, "Profiles", 0, 0, CONTENT_WIDTH)
	local help = Text(page, "Each profile has its own list of consumables. Glow, layout and show rules are shared by all of them.", 11, theme.dim)
	help:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -24)
	help:SetWidth(CONTENT_WIDTH)

	for i = 1, 8 do
		local row = CreateFrame("Frame", nil, page)
		row:SetSize(CONTENT_WIDTH, 24)
		row:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -44 - (i - 1) * 24)
		row.name = Text(row, "", 12)
		row.name:SetPoint("LEFT", row, "LEFT", 4, 0)
		row.name:SetWidth(200)
		row.name:SetWordWrap(false)
		row.count = Text(row, "", 11, theme.dim)
		row.count:SetPoint("LEFT", row, "LEFT", 214, 0)
		row.active = Text(row, "In Use", 11, theme.accent)
		row.active:SetPoint("LEFT", row, "LEFT", 300, 0)
		row.use = Button(row, "Use", 60, function()
			if row.profile then ns.SwitchProfile(row.profile) end
		end)
		row.use:SetPoint("LEFT", row, "LEFT", 296, 0)
		Tip(row.use, "Use This Profile", "Switch the bar to this profile's list.")
		row.copy = Button(row, "Copy From", 90, function(self)
			if not row.profile then return end
			if not row.confirmCopy then
				row.confirmCopy = true
				self:SetText("Overwrite?")
				return
			end
			local done, err = ns.CopyProfileFrom(row.profile)
			ns.Print(done and ("Copied the list from \"" .. row.profile .. "\" into \"" .. ns.db.profile .. "\".") or err)
			ns.RefreshOptions()
		end)
		row.copy:SetPoint("LEFT", row, "LEFT", 362, 0)
		Tip(row.copy, "Copy From This Profile", "Replaces the list of the profile in use with a copy of this profile's list. Click twice to confirm. This can't be undone.")
		row.delete = Button(row, "Delete", 70, function(self)
			if not row.profile then return end
			if not row.confirmDelete then
				row.confirmDelete = true
				self:SetText("Sure?")
				return
			end
			local done, err = ns.DeleteProfile(row.profile)
			if not done then ns.Print(err) end
			ns.RefreshOptions()
		end)
		row.delete:SetPoint("LEFT", row, "LEFT", 458, 0)
		Tip(row.delete, "Delete This Profile", "Click twice to confirm. This can't be undone.")
		profileRows[i] = row
	end

	local newLabel = Text(page, "New Profile", 12)
	newLabel:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -248)
	profileBox = EditBox(page, 170)
	profileBox:SetPoint("TOPLEFT", page, "TOPLEFT", 90, -244)
	profileBox:SetMaxLetters(24)
	Tip(profileBox, "Profile Name", "Type a name, then choose whether the new profile starts empty or as a copy of the one in use.")
	local empty = Button(page, "Create Empty", 100, function() NewProfile(nil) end)
	empty:SetPoint("LEFT", profileBox, "RIGHT", 6, 0)
	local copy = Button(page, "Copy Current", 100, function() NewProfile(ns.db.profile) end)
	copy:SetPoint("LEFT", empty, "RIGHT", 6, 0)

	local quick = Button(page, "Set Up Dungeon, Raid And PvP Profiles", 270, QuickSetup)
	quick:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -272)
	Tip(quick, "Quick Setup", "Creates Dungeon, Raid and PvP profiles as copies of the one in use and switches to them automatically. The current profile is used in the open world.")

	Header(page, "Switch Automatically", 0, -310, CONTENT_WIDTH)
	for i, spec in ipairs(CONTEXTS) do
		local label = Text(page, spec[2], 12)
		label:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -340 - (i - 1) * 24)
		local button = Button(page, "", 200, function(self)
			local names = ns.ProfileNames()
			local current, nextName = ns.db.auto[self.context], names[1]
			for index, name in ipairs(names) do
				if name == current then nextName = names[index + 1] end
			end
			ns.db.auto[self.context] = nextName
			ns.RefreshOptions()
		end)
		button.context = spec[1]
		button:SetPoint("TOPLEFT", page, "TOPLEFT", 220, -336 - (i - 1) * 24)
		Tip(button, spec[2], "Click to choose the profile to switch to when you enter this kind of place. A profile you pick by hand stays until you move to a different kind of place.")
		autoButtons[i] = button
	end

	refreshers[#refreshers + 1] = RefreshProfiles
end

---------------------------------------------------------------------------
-- Page: when the bar is shown
---------------------------------------------------------------------------
local function BuildShow(page)
	local show = ns.db.show
	local function Setter(key)
		return function(value)
			show[key] = value
			LookChanged()
		end
	end

	local y = Choice(page, "Show The Bar", {
		{ "always", "Always" },
		{ "attention", "Only When Missing Or Expiring" },
	}, function() return show.mode end, Setter("mode"), 0, 0)

	local yRight = Choice(page, "Group", {
		{ "any", "Solo Or Grouped" },
		{ "solo", "Only When Solo" },
		{ "group", "Only In A Party Or Raid" },
		{ "raid", "Only In A Raid" },
	}, function() return show.group end, Setter("group"), 310, y)

	y = Choice(page, "Combat", {
		{ "any", "In And Out Of Combat" },
		{ "in", "Only In Combat" },
		{ "out", "Only Out Of Combat" },
	}, function() return show.combat end, Setter("combat"), 0, y)

	y = Choice(page, "Place", {
		{ "any", "Anywhere" },
		{ "inside", "Only Inside Instances" },
		{ "outside", "Only Outside Instances" },
	}, function() return show.instance end, Setter("instance"), 0, math.min(y, yRight))

	local resting = Check(page, "Hide While Resting", function() return show.hideResting end, Setter("hideResting"))
	resting:SetPoint("TOPLEFT", page, "TOPLEFT", 4, y)
	Tip(resting, "Hide While Resting", "Hides the bar in cities and inns.")
	local mounted = Check(page, "Hide While Mounted", function() return show.hideMounted end, Setter("hideMounted"))
	mounted:SetPoint("TOPLEFT", page, "TOPLEFT", 4, y - 22)

	local note = Text(page, "While the bar is unlocked it's always shown so you can place it. Tick Lock The Bar on the Layout page for these rules to apply.\n\nWith \"Only When Missing Or Expiring\", the bar is invisible in combat until a buff needs you, because addons can't show or hide clickable buttons mid-fight.", 11, theme.dim)
	note:SetPoint("TOPLEFT", page, "TOPLEFT", 0, y - 56)
	note:SetWidth(CONTENT_WIDTH)
end

---------------------------------------------------------------------------
-- Page 3: glow
---------------------------------------------------------------------------
local previews = {}

local function RefreshPreviews()
	local first = ns.entries[1]
	for key, preview in pairs(previews) do
		if first then preview.icon:SetTexture(ns.ItemIcon(first.id)) end
		ns.Glow.Apply(preview, ns.db.glow[key])
	end
end

local function PickColor(cfg, onChange)
	local function Read()
		local r, g, b = ColorPickerFrame:GetColorRGB()
		local a = ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha() or 1
		cfg.r, cfg.g, cfg.b, cfg.a = r, g, b, a
		onChange()
	end
	ColorPickerFrame:SetupColorPickerAndShow({
		r = cfg.r, g = cfg.g, b = cfg.b, opacity = cfg.a, hasOpacity = true,
		swatchFunc = Read,
		opacityFunc = Read,
		cancelFunc = function(previous)
			if previous then
				cfg.r, cfg.g, cfg.b, cfg.a = previous.r, previous.g, previous.b, previous.a or 1
				onChange()
			end
		end,
	})
end

local function BuildGlowColumn(page, key, title, x, y, desaturated)
	local cfg = ns.db.glow[key]

	Header(page, title, x, y, 270)

	local preview = CreateFrame("Frame", nil, page)
	preview:SetSize(36, 36)
	preview:SetPoint("TOPLEFT", page, "TOPLEFT", x + 222, y - 34)
	preview.icon = preview:CreateTexture(nil, "ARTWORK")
	preview.icon:SetAllPoints(preview)
	preview.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
	preview.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	preview.icon:SetDesaturated(desaturated)
	previews[key] = preview

	local swatch
	local function Changed()
		if swatch then swatch.color:SetColorTexture(cfg.r, cfg.g, cfg.b, 1) end
		ns.Glow.Touch()
		RefreshPreviews()
		LookChanged()
	end

	local enabled = Check(page, "Glow", function() return cfg.enabled end, function(value)
		cfg.enabled = value
		Changed()
	end)
	enabled:SetPoint("TOPLEFT", page, "TOPLEFT", x + 4, y - 30)

	local style = Button(page, "", 150, function(self)
		local styles = ns.GLOW_STYLES
		local nextIndex = 1
		for i, name in ipairs(styles) do
			if name == cfg.style then nextIndex = i % #styles + 1 end
		end
		cfg.style = styles[nextIndex]
		self:SetText(ns.GLOW_STYLE_NAMES[cfg.style])
		Changed()
	end)
	style:SetPoint("TOPLEFT", page, "TOPLEFT", x + 4, y - 58)
	Tip(style, "Glow Style", "Click to switch between the styles.")
	refreshers[#refreshers + 1] = function() style:SetText(ns.GLOW_STYLE_NAMES[cfg.style] or cfg.style) end

	swatch = CreateFrame("Button", nil, page)
	swatch:SetSize(20, 20)
	swatch:SetPoint("LEFT", style, "RIGHT", 8, 0)
	Skin(swatch)
	swatch.color = swatch:CreateTexture(nil, "ARTWORK")
	swatch.color:SetPoint("TOPLEFT", swatch, "TOPLEFT", 1, -1)
	swatch.color:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -1, 1)
	swatch:SetScript("OnEnter", function(self) SetEdgeColor(self, theme.accent) end)
	swatch:SetScript("OnLeave", function(self) SetEdgeColor(self, theme.border) end)
	swatch:SetScript("OnClick", function() PickColor(cfg, Changed) end)
	Tip(swatch, "Glow Color", "Click to pick the color and opacity.")
	refreshers[#refreshers + 1] = function() swatch.color:SetColorTexture(cfg.r, cfg.g, cfg.b, 1) end

	local speed = Slider(page, "Speed", 0.25, 3, 0.25, function() return cfg.speed end, function(value)
		cfg.speed = value
		Changed()
	end, function(value) return ("%.2fx"):format(value) end)
	speed:SetPoint("TOPLEFT", page, "TOPLEFT", x + 4, y - 112)

	local size = Slider(page, "Thickness", 1, 6, 1, function() return cfg.size end, function(value)
		cfg.size = value
		Changed()
	end)
	size:SetPoint("TOPLEFT", page, "TOPLEFT", x + 4, y - 156)
end

local function BuildGlow(page)
	local db = ns.db
	Header(page, "Warning", 0, 0, CONTENT_WIDTH)

	local warn = Slider(page, "Expiring Warning Time", 30, 900, 30, function() return db.warn end, function(value)
		db.warn = value
		ns.RequestScan()
	end, Clock)
	warn:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -50)
	warn:SetWidth(340)
	Tip(warn, "Expiring Warning Time", "Minutes and seconds left. Short buffs are warned about later, at a third of their duration at most. Each consumable can have its own time on the Consumables page.")

	local desaturate = Check(page, "Desaturate Missing Icons", function() return db.desaturate end, function(value)
		db.desaturate = value
		LookChanged()
	end)
	desaturate:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -76)
	Tip(desaturate, "Desaturate Missing Icons", "Shows the icon of a missing or expired buff in grey.")

	BuildGlowColumn(page, "expiring", "Expiring", 0, -116, false)
	BuildGlowColumn(page, "missing", "Missing Or Expired", 310, -116, true)

	refreshers[#refreshers + 1] = RefreshPreviews
end

---------------------------------------------------------------------------
-- Page 4: layout
---------------------------------------------------------------------------
local function BuildLayout(page)
	local bar = ns.db.bar

	Header(page, "Position", 0, 0, CONTENT_WIDTH)
	local locked = Check(page, "Lock The Bar", function() return bar.locked end, function(value)
		bar.locked = value
		ns.UpdateMover()
		ns.UpdateVisibility()
	end)
	locked:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -30)
	Tip(locked, "Lock The Bar", "Hides the drag handle and applies the Show When rules. While unlocked the bar is always shown so you can place it.")

	local minimap = Check(page, "Show Minimap Button", function() return ns.db.minimap.show end, function(value)
		ns.db.minimap.show = value
		ns.UpdateMinimapButton()
	end)
	minimap:SetPoint("TOPLEFT", page, "TOPLEFT", 314, -30)
	Tip(minimap, "Show Minimap Button", "Left-click it to open this menu, right-click to lock or unlock the bar, drag to move it around the minimap.")

	local reset = Button(page, "Reset Position", 130, function()
		bar.point, bar.relPoint, bar.x, bar.y = "CENTER", "CENTER", 0, -180
		LayoutChanged()
	end)
	reset:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -56)

	Header(page, "Icons", 0, -98, CONTENT_WIDTH)
	local size = Slider(page, "Icon Size", 20, 64, 2, function() return bar.size end, function(value)
		bar.size = value
		LayoutChanged()
	end)
	size:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -148)

	local spacing = Slider(page, "Spacing", 0, 20, 1, function() return bar.spacing end, function(value)
		bar.spacing = value
		LayoutChanged()
	end)
	spacing:SetPoint("TOPLEFT", page, "TOPLEFT", 314, -148)

	local perRow = Slider(page, "Icons Per Row", 1, 24, 1, function() return bar.perRow end, function(value)
		bar.perRow = value
		LayoutChanged()
	end)
	perRow:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -192)

	local alpha = Slider(page, "Opacity", 0.2, 1, 0.05, function() return bar.alpha end, function(value)
		bar.alpha = value
		ns.UpdateVisibility()
	end, function(value) return ("%d%%"):format(value * 100 + 0.5) end)
	alpha:SetPoint("TOPLEFT", page, "TOPLEFT", 314, -192)

	local vertical = Check(page, "Grow Downward", function() return bar.vertical end, function(value)
		bar.vertical = value
		LayoutChanged()
	end)
	vertical:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -222)
	Tip(vertical, "Grow Downward", "Fill columns from top to bottom instead of rows from left to right.")

	Header(page, "On Each Icon", 0, -262, CONTENT_WIDTH)
	local timer = Check(page, "Show Time Left", function() return bar.showTimer end, function(value)
		bar.showTimer = value
		LookChanged()
	end)
	timer:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -292)

	local count = Check(page, "Show Bag Count", function() return bar.showCount end, function(value)
		bar.showCount = value
		LookChanged()
	end)
	count:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -314)
	Tip(count, "Show Bag Count", "Shows how many of the item are in your bags. View Only icons always show it.")

	local tooltips = Check(page, "Show Tooltips", function() return bar.tooltips end, function(value)
		bar.tooltips = value
	end)
	tooltips:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -336)
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local function SelectTab(index)
	for i, page in ipairs(pages) do
		local tab, selected = tabs[i], i == index
		page:SetShown(selected)
		tab.selected = selected
		SetEdgeColor(tab, selected and theme.accent or theme.border)
		local color = selected and theme.accent or theme.text
		tab.label:SetTextColor(color[1], color[2], color[3])
	end
end

local function CreateWindow()
	LoadElvUITheme()

	win = CreateFrame("Frame", "ClickableConsumeBarOptions", UIParent)
	win:SetSize(864, 540)
	win:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	win:SetFrameStrata("DIALOG")
	Skin(win, theme.window)
	win:EnableMouse(true)
	win:SetMovable(true)
	win:SetClampedToScreen(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", function(self) self:StartMoving() end)
	win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	-- Other code asks "is the menu open?" on frequent events; keeping the
	-- answer in a plain flag makes that free.
	win:SetScript("OnShow", function() ns.menuOpen = true end)
	win:SetScript("OnHide", function() ns.menuOpen = false end)
	win:Hide()
	ns.menuOpen = false
	table.insert(UISpecialFrames, "ClickableConsumeBarOptions") -- Escape closes it

	-- Title strip
	local header = CreateFrame("Frame", nil, win)
	header:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0)
	header:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, 0)
	header:SetHeight(30)
	Skin(header, theme.widget)
	local icon = header:CreateTexture(nil, "ARTWORK")
	icon:SetSize(22, 22)
	icon:SetPoint("LEFT", header, "LEFT", 6, 0)
	icon:SetTexture(ns.icon)
	local title = Text(header, "ClickableConsumeBar", 14, theme.accent)
	title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
	local version = Text(header, "v" .. ns.version, 11, theme.dim)
	version:SetPoint("LEFT", title, "RIGHT", 8, -1)

	local close = Button(header, "x", 20, function() win:Hide() end)
	close:SetPoint("RIGHT", header, "RIGHT", -5, 0)

	local profile = Text(header, "", 12, theme.dim)
	profile:SetPoint("RIGHT", close, "LEFT", -12, 0)
	refreshers[#refreshers + 1] = function()
		profile:SetText(("Profile: |cff%02x%02x%02x%s|r"):format(theme.accent[1] * 255, theme.accent[2] * 255,
			theme.accent[3] * 255, ns.db.profile))
	end

	-- Page list down the left, the page itself on the right
	local sidebar = CreateFrame("Frame", nil, win)
	sidebar:SetPoint("TOPLEFT", win, "TOPLEFT", 8, -38)
	sidebar:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 8, 8)
	sidebar:SetWidth(134)
	Skin(sidebar, theme.panel)

	local body = CreateFrame("Frame", nil, win)
	body:SetPoint("TOPLEFT", win, "TOPLEFT", 148, -38)
	body:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -8, 8)
	Skin(body, theme.panel)

	local builders = {
		{ "Consumables", BuildConsumables },
		{ "Profiles", BuildProfiles },
		{ "Show When", BuildShow },
		{ "Glow", BuildGlow },
		{ "Layout", BuildLayout },
	}
	for i, spec in ipairs(builders) do
		local tab = Button(sidebar, spec[1], 122, function() SelectTab(i) end)
		tab:SetHeight(24)
		tab:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 6, -6 - (i - 1) * 28)
		tabs[i] = tab

		local page = CreateFrame("Frame", nil, body)
		page:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -12)
		page:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -12, 12)
		pages[i] = page
		spec[2](page)
	end
	SelectTab(1)
end

function ns.RefreshOptions()
	if not ns.menuOpen then return end
	for _, refresh in ipairs(refreshers) do refresh() end
end

function ns.ToggleOptions(forceOpen)
	if not ns.db then return end
	if not win then CreateWindow() end
	if win:IsShown() and not forceOpen then
		win:Hide()
		ns.menuOpen = false
	else
		win:Show()
		ns.menuOpen = true
		ns.RefreshOptions()
	end
end

-- An entry in the game's own Options > AddOns list that opens the menu.
function ns.InitOptions()
	if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
	pcall(function()
		local panel = CreateFrame("Frame")
		local icon = panel:CreateTexture(nil, "ARTWORK")
		icon:SetSize(40, 40)
		icon:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -12)
		icon:SetTexture(ns.icon)
		local title = Text(panel, "ClickableConsumeBar", 16, theme.accent)
		title:SetPoint("LEFT", icon, "RIGHT", 10, 0)
		local text = Text(panel, "A clickable bar for the consumable buffs you want to keep up.\nYou can also open the menu with /ccb.", 12)
		text:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -64)
		local open = Button(panel, "Open The Menu", 160, function() ns.ToggleOptions(true) end)
		open:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -110)
		local category = Settings.RegisterCanvasLayoutCategory(panel, "ClickableConsumeBar")
		Settings.RegisterAddOnCategory(category)
	end)
end
