-- MinimapButton: the addon's icon on the edge of the minimap.
-- Left-click opens the menu, right-click locks or unlocks the bar, and
-- dragging slides the button around the map.
--
-- The button follows whatever other addons do to the minimap:
--   * Shape. Minimap addons announce their shape through GetMinimapShape
--     (round, square, or round on only some corners). The button rides the
--     curve on rounded corners and the straight edge on square ones.
--   * Size. It re-seats itself whenever the minimap is resized or reshaped.
--   * Its own size. If another addon resizes the button, its art scales too.
--   * Collectors. If another addon moves the button off the minimap into its
--     own bar, the button stops positioning itself and leaves that to them.
-- It runs no code except when one of those things happens or it is dragged.
local _, ns = ...

local button
local BASE = 31 -- the size the art below is laid out for

---------------------------------------------------------------------------
-- Shape
---------------------------------------------------------------------------
local OPPOSITE = { TOPLEFT = "BOTTOMRIGHT", TOPRIGHT = "BOTTOMLEFT", BOTTOMLEFT = "TOPRIGHT", BOTTOMRIGHT = "TOPLEFT" }
local cornerCache = {}

-- Which corners of the map are rounded for a shape name:
--   ROUND, SQUARE
--   CORNER-<corner>     only that corner is rounded
--   SIDE-<side>         the two corners on that side are rounded
--   TRICORNER-<corner>  every corner but the opposite one is rounded
-- Anything unrecognized is treated as round.
local function RoundedCorners(shape)
	if type(shape) ~= "string" then shape = "ROUND" end
	local corners = cornerCache[shape]
	if corners then return corners end
	corners = { TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }
	local kind, where = shape:match("^(%u+)%-(%u+)$")
	if shape == "SQUARE" then
		for name in pairs(corners) do corners[name] = false end
	elseif kind == "CORNER" and corners[where] ~= nil then
		for name in pairs(corners) do corners[name] = (name == where) end
	elseif kind == "SIDE" and (where == "LEFT" or where == "RIGHT" or where == "TOP" or where == "BOTTOM") then
		for name in pairs(corners) do corners[name] = name:find(where, 1, true) ~= nil end
	elseif kind == "TRICORNER" and corners[where] ~= nil then
		corners[OPPOSITE[where]] = false
	end
	cornerCache[shape] = corners
	return corners
end

local function Clamp(value, limit)
	if value > limit then return limit end
	if value < -limit then return -limit end
	return value
end

-- Puts the button on the minimap's edge at the saved angle.
local function Place()
	if not button or not button:IsShown() then return end
	-- Moved into another addon's button bar: that addon places it now.
	if button:GetParent() ~= Minimap then return end

	local angle = math.rad(ns.db.minimap.angle or 215)
	local x, y = math.cos(angle), math.sin(angle)
	local w, h = Minimap:GetWidth(), Minimap:GetHeight()
	if not w or w <= 0 then w = 140 end
	if not h or h <= 0 then h = w end
	w, h = w / 2 + 5, h / 2 + 5

	local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
	local corner = (y > 0 and "TOP" or "BOTTOM") .. (x < 0 and "LEFT" or "RIGHT")
	if RoundedCorners(shape)[corner] then
		x, y = x * w, y * h
	else
		-- Push out to the corner's diagonal, then hold to the straight edges.
		x, y = Clamp(x * w * 1.41421356, w), Clamp(y * h * 1.41421356, h)
	end
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

---------------------------------------------------------------------------
-- The button
---------------------------------------------------------------------------
-- Sizes the art to the button, so it still looks right if another addon
-- makes the button bigger or smaller.
local function Layout()
	if button:GetParent() ~= Minimap then return end -- a collector styles it its own way
	local size = button:GetWidth()
	if not size or size <= 0 then size = BASE end
	local k = size / BASE
	button.background:ClearAllPoints()
	button.background:SetSize(20 * k, 20 * k)
	button.background:SetPoint("TOPLEFT", button, "TOPLEFT", 7 * k, -5 * k)
	button.icon:ClearAllPoints()
	button.icon:SetSize(21 * k, 21 * k)
	button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 6 * k, -5 * k)
	button.border:ClearAllPoints()
	button.border:SetSize(53 * k, 53 * k)
	button.border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
end

local function FollowCursor()
	local mx, my = Minimap:GetCenter()
	local scale = Minimap:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	if not (mx and my and cx and cy) or not scale or scale == 0 then return end
	ns.db.minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
	Place()
end

local function OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText("ClickableConsumeBar")
	GameTooltip:AddLine("Left-click: open the menu", 1, 1, 1)
	GameTooltip:AddLine("Right-click: lock or unlock the bars", 1, 1, 1)
	GameTooltip:AddLine("Drag: move this button", 1, 1, 1)
	GameTooltip:Show()
end

local function Create()
	button = CreateFrame("Button", "ClickableConsumeBarMinimapButton", Minimap)
	button:SetSize(BASE, BASE)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	-- Named the way minimap button addons expect, so they can restyle them.
	button.background = button:CreateTexture(nil, "BACKGROUND")
	button.background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetTexture(ns.iconRound)
	button.border = button:CreateTexture(nil, "OVERLAY")
	button.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	Layout()

	button:SetScript("OnClick", function(_, mouseButton)
		if mouseButton == "RightButton" then
			local bar = ns.db.bar
			bar.locked = not bar.locked
			ns.UpdateMover()
			ns.UpdateVisibility()
			ns.Print(bar.locked and "Bars locked." or "Bars unlocked. Drag each one by the handle above it.")
			if ns.RefreshOptions then ns.RefreshOptions() end
		else
			ns.ToggleOptions()
		end
	end)
	button:SetScript("OnDragStart", function(self)
		if self:GetParent() == Minimap then self:SetScript("OnUpdate", FollowCursor) end
	end)
	button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	button:SetScript("OnEnter", OnEnter)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button:SetScript("OnSizeChanged", Layout)

	-- Follow the minimap when another addon resizes, reshapes or re-shows it.
	Minimap:HookScript("OnSizeChanged", Place)
	Minimap:HookScript("OnShow", Place)
	if Minimap.SetMaskTexture then
		pcall(hooksecurefunc, Minimap, "SetMaskTexture", Place)
	end
end

-- Shows or hides the button to match the setting; made on first use. Safe to
-- call again at any time to re-seat the button.
function ns.UpdateMinimapButton()
	if not Minimap then return end
	if not ns.db.minimap.show then
		if button then button:Hide() end
		return
	end
	if not button then Create() end
	button:Show()
	Place()
end

-- Minimap addons often finish setting up a moment after login, with no
-- event to say so: look again once they have.
function ns.SettleMinimapButton()
	C_Timer.After(3, ns.UpdateMinimapButton)
end
