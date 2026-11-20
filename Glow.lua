-- Glow: the highlight drawn around an icon. Four styles, each with its own
-- color, speed and thickness.
--
-- Every moving part is a game animation (alpha or translation) that the
-- client runs by itself, so a glow costs no addon code per frame. Lua only
-- runs when a glow is turned on, turned off or reconfigured.
local _, ns = ...

local Glow = { rev = 0 }
ns.Glow = Glow

local HALO = "Interface\\Buttons\\CheckButtonGlow"
local DASHES = 3 -- per side: two visible plus one sliding in

-- The four sides, clockwise. Each has a strip that clips its dashes, and the
-- dashes ride a "belt" that slides one dash spacing and then repeats, which
-- looks like an endless march.
local SIDES = {
	{ from = "TOPLEFT", to = "TOPRIGHT", dx = 1, dy = 0, horizontal = true },
	{ from = "TOPRIGHT", to = "BOTTOMRIGHT", dx = 0, dy = -1 },
	{ from = "BOTTOMRIGHT", to = "BOTTOMLEFT", dx = -1, dy = 0, horizontal = true },
	{ from = "BOTTOMLEFT", to = "TOPLEFT", dx = 0, dy = 1 },
}

-- Call after changing a glow's settings table in place.
function Glow.Touch()
	Glow.rev = Glow.rev + 1
end

local function AlphaLoop(region)
	local group = region:CreateAnimationGroup()
	group:SetLooping("BOUNCE")
	group.anim = group:CreateAnimation("Alpha")
	group.anim:SetSmoothing("IN_OUT")
	return group
end

-- Animations stop while a frame is hidden; start them again when it shows.
local function Resume(g)
	local playing = g.playing
	for i = 1, #playing do
		if not playing[i]:IsPlaying() then playing[i]:Play() end
	end
end

local function StopAll(g)
	local playing = g.playing
	for i = #playing, 1, -1 do
		playing[i]:Stop()
		playing[i] = nil
	end
end

local function Start(g, group)
	g.playing[#g.playing + 1] = group
	group:Play()
end

function Glow.Build(owner)
	local g = CreateFrame("Frame", nil, owner)
	g:SetAllPoints(owner)
	g:SetFrameLevel(owner:GetFrameLevel() + 5)
	g.playing = {}

	-- Soft pulse: one additive halo.
	g.halo = g:CreateTexture(nil, "OVERLAY")
	g.halo:SetTexture(HALO)
	g.halo:SetBlendMode("ADD")
	g.halo:SetPoint("CENTER", g, "CENTER", 0, 0)
	g.halo:Hide()
	g.haloLoop = AlphaLoop(g.halo)

	-- Solid and blinking border: four edges on one frame, so a single
	-- animation fades them together.
	g.border = CreateFrame("Frame", nil, g)
	g.border:SetAllPoints(g)
	g.border:Hide()
	g.borderLoop = AlphaLoop(g.border)
	g.edges = {}
	for i = 1, 4 do
		g.edges[i] = g.border:CreateTexture(nil, "OVERLAY")
	end

	-- Marching pixels.
	g.sides = {}
	for i, side in ipairs(SIDES) do
		local clip = CreateFrame("Frame", nil, g)
		clip:SetPoint(side.from, g, side.from, 0, 0)
		clip:SetPoint(side.to, g, side.to, 0, 0)
		clip:SetClipsChildren(true)
		clip:Hide()
		local belt = CreateFrame("Frame", nil, clip)
		belt:SetAllPoints(clip)
		clip.belt = belt
		clip.loop = belt:CreateAnimationGroup()
		clip.loop:SetLooping("REPEAT")
		clip.loop.anim = clip.loop:CreateAnimation("Translation")
		clip.dashes = {}
		for k = 1, DASHES do
			clip.dashes[k] = belt:CreateTexture(nil, "OVERLAY")
		end
		g.sides[i] = clip
	end

	g:SetScript("OnShow", Resume)
	g:Hide()
	owner.glow = g
	return g
end

local function LayoutEdges(g, th)
	local top, bottom, left, right = g.edges[1], g.edges[2], g.edges[3], g.edges[4]
	top:ClearAllPoints()
	top:SetPoint("BOTTOMLEFT", g, "TOPLEFT", -th, 0)
	top:SetPoint("BOTTOMRIGHT", g, "TOPRIGHT", th, 0)
	top:SetHeight(th)
	bottom:ClearAllPoints()
	bottom:SetPoint("TOPLEFT", g, "BOTTOMLEFT", -th, 0)
	bottom:SetPoint("TOPRIGHT", g, "BOTTOMRIGHT", th, 0)
	bottom:SetHeight(th)
	left:ClearAllPoints()
	left:SetPoint("TOPRIGHT", g, "TOPLEFT", 0, 0)
	left:SetPoint("BOTTOMRIGHT", g, "BOTTOMLEFT", 0, 0)
	left:SetWidth(th)
	right:ClearAllPoints()
	right:SetPoint("TOPLEFT", g, "TOPRIGHT", 0, 0)
	right:SetPoint("BOTTOMLEFT", g, "BOTTOMRIGHT", 0, 0)
	right:SetWidth(th)
end

local function LayoutPixels(g, cfg, w, h, th, speed)
	for i, side in ipairs(SIDES) do
		local clip = g.sides[i]
		local length = side.horizontal and w or h
		local spacing = length / 2
		local dash = spacing * 0.55
		if side.horizontal then clip:SetHeight(th) else clip:SetWidth(th) end
		for k = 1, DASHES do
			local tex = clip.dashes[k]
			local pos = (k - 2) * spacing -- one dash waits just outside the strip
			tex:ClearAllPoints()
			tex:SetPoint(side.from, clip.belt, side.from, side.dx * pos, side.dy * pos)
			if side.horizontal then tex:SetSize(dash, th) else tex:SetSize(th, dash) end
			tex:SetColorTexture(cfg.r, cfg.g, cfg.b, cfg.a or 1)
		end
		clip.loop.anim:SetOffset(side.dx * spacing, side.dy * spacing)
		clip.loop.anim:SetDuration(spacing / (40 * speed))
		clip:Show()
		Start(g, clip.loop)
	end
end

-- Shows the glow described by cfg on owner, or hides it when cfg is nil or
-- turned off. Cheap to call repeatedly: nothing happens unless the settings,
-- or the icon's size, changed.
function Glow.Apply(owner, cfg, w, h)
	local g = owner.glow or Glow.Build(owner)
	if not cfg or not cfg.enabled then
		if g.cfg then
			g.cfg, g.style = nil, nil
			StopAll(g)
			g:Hide()
		end
		return
	end

	-- The caller passes the icon's size when it knows it, which saves asking
	-- the game every time; the usual case below is then pure comparisons.
	if not w then w, h = owner:GetWidth(), owner:GetHeight() end
	if not w or w <= 0 then w = 36 end
	if not h or h <= 0 then h = w end
	if g.cfg == cfg and g.rev == Glow.rev and g.w == w and g.h == h then return end
	g.cfg, g.rev, g.w, g.h = cfg, Glow.rev, w, h

	local style, th = cfg.style, math.max(1, cfg.size or 2)
	local speed, alpha = math.max(0.1, cfg.speed or 1), cfg.a or 1
	g.style = style

	StopAll(g)
	g.halo:Hide()
	g.border:Hide()
	for i = 1, 4 do g.sides[i]:Hide() end

	if style == "pulse" then
		local scale = 1.8 + 0.06 * th
		g.halo:SetSize(w * scale, h * scale)
		g.halo:SetVertexColor(cfg.r, cfg.g, cfg.b)
		g.halo:SetAlpha(alpha)
		g.halo:Show()
		g.haloLoop.anim:SetFromAlpha(alpha)
		g.haloLoop.anim:SetToAlpha(alpha * 0.3)
		g.haloLoop.anim:SetDuration(0.6 / speed)
		Start(g, g.haloLoop)
	elseif style == "pixel" then
		LayoutPixels(g, cfg, w, h, th, speed)
	else -- solid, blink
		LayoutEdges(g, th)
		for i = 1, 4 do g.edges[i]:SetColorTexture(cfg.r, cfg.g, cfg.b, 1) end
		g.border:SetAlpha(alpha)
		g.border:Show()
		if style == "blink" then
			g.borderLoop.anim:SetFromAlpha(alpha)
			g.borderLoop.anim:SetToAlpha(alpha * 0.1)
			g.borderLoop.anim:SetDuration(0.35 / speed)
			Start(g, g.borderLoop)
		end
	end
	g:Show()
end
