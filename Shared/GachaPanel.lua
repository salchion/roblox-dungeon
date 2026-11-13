-- GachaPanel (ReplicatedStorage 안의 ModuleScript, 이름: GachaPanel)
-- 로비 뽑기 기계를 누르면 뜨는 창. 예전에는 장비 칸 + 캐릭터 + 강화가 같이 있어서 뽑기 정보가 작게 보였다.
-- 이제 뽑기만: 가운데 큰 뽑기 구슬(빛줄기가 돈다) + 티켓 수, 왼쪽 등급 확률, 오른쪽 천장(확정까지 남은 횟수) 게이지,
-- 아래 1회 / 여러 번 뽑기 버튼. 장비 착용 / 강화는 장비 창(캐릭터 탭)에서 한다.
-- PlayerClient 가 Init(deps) 를 부르고, 돌려받은 { Panel, Message, Refresh, Flash } 를 쓴다.

local M = {}

function M.Init(deps)
	local Config, Remotes, TweenService, RunService = deps.Config, deps.Remotes, deps.TweenService, deps.RunService
	local create, makeLabel, makeButton, makePanel, rounded = deps.create, deps.makeLabel, deps.makeButton, deps.makePanel, deps.rounded
	local player, gui = deps.player, deps.gui
	local W, H = 720, 610
	local PURPLE = Color3.fromRGB(214, 156, 52) -- (여러 번 뽑기 버튼: 보라 -> 금색. 가장 눈에 띄어야 할 버튼)

	local panel = makePanel({
		Size = UDim2.new(0, W, 0, H), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
		BackgroundColor3 = Color3.fromRGB(18, 14, 32), BackgroundTransparency = 0.03, Visible = false,
	}, gui)
	create("UIStroke", { Color = Color3.fromRGB(255, 210, 120), Thickness = 2.5, Transparency = 0.15 }, panel)
	create("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(90, 46, 130), Color3.fromRGB(18, 14, 32)), Rotation = 90 }, panel)
	local scale = create("UIScale", { Scale = 1 }, panel)
	local function fit()
		local camera = workspace.CurrentCamera
		if camera then scale.Scale = math.clamp(math.min((camera.ViewportSize.X - 20) / W, (camera.ViewportSize.Y - 20) / H), 0.45, 1) end
	end
	fit()
	if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit) end

	makeLabel({ Size = UDim2.new(1, 0, 0, 36), Position = UDim2.new(0, 0, 0, 8), Text = "🎰 Gear Gacha", Font = Enum.Font.GothamBlack, TextSize = 22, TextColor3 = Color3.fromRGB(255, 220, 140) }, panel)
	makeButton({ Size = UDim2.new(0, 72, 0, 30), Position = UDim2.new(1, -84, 0, 12), Text = "Close", TextSize = 12, BackgroundColor3 = Color3.fromRGB(54, 58, 82) }, panel, function()
		panel.Visible = false
	end)

	------------------------------------------------------------
	-- 가운데: 뽑기 구슬 + 빛줄기 + 티켓 수
	------------------------------------------------------------
	local CX, CY = W / 2, 190
	local rays = create("Frame", { Size = UDim2.new(0, 0, 0, 0), Position = UDim2.new(0, CX, 0, CY), BackgroundTransparency = 1 }, panel)
	local rayParts = {}
	for i = 1, 12 do
		local ray = create("Frame", {
			Size = UDim2.new(0, 10, 0, 250), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0, 0), Rotation = i * 15,
			BackgroundColor3 = Color3.fromRGB(255, 220, 150), BackgroundTransparency = 0.88, BorderSizePixel = 0, ZIndex = 1,
		}, rays)
		create("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) }) }, ray)
		table.insert(rayParts, ray)
	end
	local orb = create("Frame", {
		Size = UDim2.new(0, 150, 0, 150), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, CX, 0, CY),
		BackgroundColor3 = Color3.fromRGB(70, 40, 120), BorderSizePixel = 0, ZIndex = 3,
	}, panel)
	rounded(orb, 75)
	create("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(200, 150, 255), Color3.fromRGB(60, 30, 110)), Rotation = 60 }, orb)
	local orbStroke = create("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 4 }, orb)
	local orbRing = create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 120, 200)), ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 225, 120)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(120, 220, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 120, 200)),
		}),
	}, orbStroke)
	local orbScale = create("UIScale", { Scale = 1 }, orb)
	makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = "🎁", TextSize = 70, ZIndex = 4 }, orb)
	local ticketLabel = makeLabel({ -- 티켓 수: 금테 알약 안에
		Size = UDim2.new(0, 210, 0, 36), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0, CX, 0, CY + 84), Text = "", RichText = true,
		Font = Enum.Font.GothamBlack, TextSize = 21, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.6, ZIndex = 4,
		BackgroundTransparency = 0.1, BackgroundColor3 = Color3.fromRGB(30, 22, 48),
	}, panel)
	rounded(ticketLabel, 18)
	create("UIStroke", { Color = Color3.fromRGB(255, 205, 110), Thickness = 1.5, Transparency = 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, ticketLabel)
	local message = makeLabel({
		Size = UDim2.new(1, -40, 0, 20), Position = UDim2.new(0, 20, 0, CY + 124), Text = "", RichText = true, TextSize = 13, Font = Enum.Font.GothamBold, ZIndex = 4,
	}, panel)

	------------------------------------------------------------
	-- 왼쪽: 등급 확률 (등급 색 구슬 + %)
	------------------------------------------------------------
	-- 구역 제목: 왼쪽 정렬 + 아래 금빛 짧은 선 (게임 메뉴 느낌)
	local function sectionHead(text, x, anchorRight)
		local head = makeLabel({ Size = UDim2.new(0, 180, 0, 20), Position = UDim2.new(anchorRight and 1 or 0, x, 0, 58), Text = text, TextSize = 13, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 226, 160), TextXAlignment = Enum.TextXAlignment.Left }, panel)
		create("Frame", { Size = UDim2.new(0, 28, 0, 2), Position = UDim2.new(0, 0, 1, 1), BackgroundColor3 = Color3.fromRGB(255, 200, 110), BorderSizePixel = 0 }, head)
		return head
	end
	sectionHead("Rates", 26)
	-- 등급 확률: 굵은 알약 대신 얇은 줄 (왼쪽 등급색 막대 + 이름 + % + 아래 비율 막대)
	local maxRate = 0
	for _, rate in ipairs(Config.Gacha.Rates) do maxRate = math.max(maxRate, rate) end
	for index, rate in ipairs(Config.Gacha.Rates) do
		local color = Config.Gear.RarityColors[index]
		local row = create("Frame", { Size = UDim2.new(0, 180, 0, 34), Position = UDim2.new(0, 26, 0, 86 + (index - 1) * 38), BackgroundColor3 = Color3.fromRGB(26, 22, 42), BackgroundTransparency = 0.15, BorderSizePixel = 0, ZIndex = 3 }, panel)
		rounded(row, 8)
		local accent = create("Frame", { Size = UDim2.new(0, 4, 1, -10), Position = UDim2.new(0, 6, 0, 5), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 4 }, row)
		rounded(accent, 2)
		makeLabel({ Size = UDim2.new(1, -80, 0, 18), Position = UDim2.new(0, 16, 0, 3), Text = Config.Gear.RarityNames[index], TextSize = 12, Font = Enum.Font.GothamBlack, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 }, row)
		makeLabel({ Size = UDim2.new(0, 52, 0, 18), Position = UDim2.new(1, -60, 0, 3), Text = rate .. "%", TextSize = 13, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 4 }, row)
		local back = create("Frame", { Size = UDim2.new(1, -24, 0, 4), Position = UDim2.new(0, 16, 1, -9), BackgroundColor3 = Color3.fromRGB(46, 42, 66), BorderSizePixel = 0, ZIndex = 4 }, row)
		rounded(back, 2)
		local fillBar = create("Frame", { Size = UDim2.new(math.clamp(rate / maxRate, 0.03, 1), 0, 1, 0), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 5 }, back)
		rounded(fillBar, 2)
	end
	makeButton({ Size = UDim2.new(0, 180, 0, 28), Position = UDim2.new(0, 26, 0, 284), Text = "📊 Odds", TextSize = 13, BackgroundColor3 = Color3.fromRGB(60, 72, 130) }, panel, function()
		player:SetAttribute("OddsKind", "Gacha") -- OddsClient 가 확률 창을 연다 (유료 랜덤 아이템 정책)
		player:SetAttribute("OddsOpen", os.clock())
	end)

	------------------------------------------------------------
	-- 오른쪽: 천장 게이지 (전설 / 신화 확정까지)
	------------------------------------------------------------
	sectionHead("Pity", -206, true)
	local function pityGauge(y, color, total)
		local card = create("Frame", { Size = UDim2.new(0, 180, 0, 86), Position = UDim2.new(1, -206, 0, y + 6), BackgroundColor3 = Color3.fromRGB(26, 22, 42), BackgroundTransparency = 0.15, BorderSizePixel = 0, ZIndex = 3 }, panel)
		rounded(card, 10)
		create("UIStroke", { Color = color, Thickness = 1, Transparency = 0.45 }, card)
		local band = create("Frame", { Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 4 }, card) -- 위쪽 색 띠
		create("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 0.7) }) }, band)
		local title = makeLabel({ Size = UDim2.new(1, -20, 0, 34), Position = UDim2.new(0, 10, 0, 8), Text = "", RichText = true, TextSize = 13, Font = Enum.Font.GothamBlack, TextColor3 = color, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 }, card)
		local back = create("Frame", { Size = UDim2.new(1, -20, 0, 8), Position = UDim2.new(0, 10, 0, 50), BackgroundColor3 = Color3.fromRGB(14, 12, 24), BorderSizePixel = 0, ZIndex = 4 }, card)
		rounded(back, 4)
		local fill = create("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 5 }, back)
		rounded(fill, 4)
		create("UIGradient", { Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.35), color) }, fill)
		local count = makeLabel({ Size = UDim2.new(1, -20, 0, 14), Position = UDim2.new(0, 10, 0, 64), Text = "", TextSize = 10, TextColor3 = Color3.fromRGB(200, 196, 225), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 4 }, card)
		return { Title = title, Fill = fill, Count = count, Total = total }
	end
	local pityL = pityGauge(80, Color3.fromRGB(255, 217, 102), Config.Gacha.Pity.Legendary)
	local pityM = pityGauge(182, Color3.fromRGB(255, 154, 216), Config.Gacha.Pity.Mythic)
	local function paintPity(g, remain, fmt)
		g.Title.Text = string.format(fmt, remain)
		local done = g.Total - remain
		TweenService:Create(g.Fill, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { Size = UDim2.new(math.clamp(done / g.Total, 0, 1), 0, 1, 0) }):Play()
		g.Count.Text = string.format("%d / %d", done, g.Total)
	end

	------------------------------------------------------------
	-- 세트 고르기 (뽑기만의 장점): 고른 구역 세트 조각으로 나온다. 도달한 구역까지만
	-- 큼직한 카드 9장 (세트 없음 + 8개 구역): 아이콘 / 구역 번호 / 세트 이름. 고른 카드는 크고 환하게 빛난다
	------------------------------------------------------------
	local setHead = makeLabel({ Size = UDim2.new(0, 400, 0, 14), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0, CX, 0, CY + 142), Text = "Target set (gacha only)", TextSize = 10, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(180, 170, 210), ZIndex = 4 }, panel)
	local setTitle = makeLabel({ Size = UDim2.new(0, 560, 0, 20), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0, CX, 0, CY + 156), Text = "", TextSize = 15, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(230, 210, 255), ZIndex = 4 }, panel)
	local CARD_W, CARD_H, CARD_GAP = 70, 72, 6
	local count = Config.Field.ZoneCount + 1
	local rowW = count * CARD_W + (count - 1) * CARD_GAP
	local setRow = create("Frame", { Size = UDim2.new(0, rowW, 0, CARD_H + 8), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0, CX, 0, CY + 180), BackgroundTransparency = 1, ZIndex = 4 }, panel)
	local setButtons = {}
	for zone = 0, Config.Field.ZoneCount do
		local def = zone > 0 and Config.Sets[Config.Sets.ZoneKeys[zone]]
		local card = makeButton({
			Size = UDim2.new(0, CARD_W, 0, CARD_H), Position = UDim2.new(0, zone * (CARD_W + CARD_GAP), 0, 4), Text = "", ZIndex = 5,
			BackgroundColor3 = def and def.Color:Lerp(Color3.fromRGB(24, 20, 38), 0.7) or Color3.fromRGB(44, 40, 62), AutoButtonColor = false,
		}, setRow, function()
			Remotes.Gear:FireServer("GachaSet", zone)
		end)
		rounded(card, 10)
		local stroke = create("UIStroke", { Color = def and def.Color or Color3.fromRGB(150, 150, 180), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
		local scale = create("UIScale", { Scale = 1 }, card)
		local icon = makeLabel({ Size = UDim2.new(1, 0, 0, 32), Position = UDim2.new(0, 0, 0, 4), Text = def and (def.Icon or "★") or "🎲", TextSize = 24, ZIndex = 6 }, card)
		local zoneTag = makeLabel({ Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 0, 36), Text = zone > 0 and ("Z" .. zone) or "Any", TextSize = 10, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 226, 140), ZIndex = 6 }, card)
		local nameText = makeLabel({ Size = UDim2.new(1, -4, 0, 22), Position = UDim2.new(0, 2, 0, 48), Text = def and def.Name or "Random set", TextSize = 8, Font = Enum.Font.GothamBold, TextWrapped = true, TextColor3 = Color3.fromRGB(215, 210, 235), ZIndex = 6 }, card)
		local check = makeLabel({ Size = UDim2.new(0, 18, 0, 18), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -2, 0, 2), Text = "✔", TextSize = 12, Font = Enum.Font.GothamBlack, BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(60, 190, 110), ZIndex = 8, Visible = false }, card)
		rounded(check, 9)
		setButtons[zone] = { Card = card, Stroke = stroke, Scale = scale, Icon = icon, Tag = zoneTag, Name = nameText, Check = check, Def = def }
	end
	local function paintSets()
		local chosen = player:GetAttribute("GachaSet") or 0
		local reached = player:GetAttribute("MaxZone") or 1
		for zone, entry in pairs(setButtons) do
			local open = zone <= reached
			local picked = zone == chosen
			entry.Card.Active = open
			entry.Icon.Text = open and (entry.Def and (entry.Def.Icon or "★") or "🎲") or "🔒"
			entry.Icon.TextTransparency = open and 0 or 0.35
			entry.Name.TextTransparency = open and 0 or 0.5
			entry.Tag.TextTransparency = open and 0 or 0.4
			entry.Check.Visible = picked
			entry.Stroke.Thickness = picked and 2.5 or 1
			entry.Stroke.Color = picked and Color3.new(1, 1, 1) or (entry.Def and entry.Def.Color or Color3.fromRGB(150, 150, 180))
			local base = entry.Def and entry.Def.Color or Color3.fromRGB(150, 150, 180)
			entry.Card.BackgroundColor3 = picked and base:Lerp(Color3.fromRGB(24, 20, 38), 0.2) or (open and base:Lerp(Color3.fromRGB(24, 20, 38), 0.72) or Color3.fromRGB(30, 28, 42))
			TweenService:Create(entry.Scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = picked and 1.08 or 1 }):Play()
		end
		local def = chosen > 0 and Config.Sets[Config.Sets.ZoneKeys[chosen]]
		if def then
			setTitle.Text = (def.Icon or "★") .. " " .. def.Name
			setTitle.TextColor3 = def.Color:Lerp(Color3.new(1, 1, 1), 0.35)
		else
			setTitle.Text = "🎲 A random set from the zones you've cleared"
			setTitle.TextColor3 = Color3.fromRGB(230, 210, 255)
		end
	end
	player:GetAttributeChangedSignal("GachaSet"):Connect(paintSets)
	player:GetAttributeChangedSignal("MaxZone"):Connect(paintSets)
	paintSets()

	------------------------------------------------------------
	-- 아래: 뽑기 버튼
	------------------------------------------------------------
	local bar = create("Frame", { Size = UDim2.new(1, -36, 0, 128), Position = UDim2.new(0, 18, 1, -142), BackgroundColor3 = Color3.fromRGB(58, 38, 92), BorderSizePixel = 0 }, panel)
	rounded(bar, 14)
	bar.BackgroundColor3 = Color3.fromRGB(24, 18, 40)
	create("UIStroke", { Color = Color3.fromRGB(255, 210, 120), Thickness = 1, Transparency = 0.5 }, bar)
	makeLabel({ Size = UDim2.new(0, 210, 0, 18), Position = UDim2.new(0, 18, 0, 18), Text = "ℹ How it works", TextSize = 12, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 226, 160), TextXAlignment = Enum.TextXAlignment.Left }, bar)
	makeLabel({
		Size = UDim2.new(0, 210, 1, -50), Position = UDim2.new(0, 18, 0, 40), TextSize = 11, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Color3.fromRGB(200, 192, 226), Text = "Same or lower rarity converts to Gold · Tickets drop from dungeons / field bosses",
	}, bar)
	local rollOne = makeButton({
		Size = UDim2.new(0, 200, 0, 92), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -244, 0.5, 0),
		Text = "🎰 Roll x1\n1 Ticket", TextSize = 19, Font = Enum.Font.GothamBold, BackgroundColor3 = Color3.fromRGB(84, 62, 140),
	}, bar, function()
		Remotes.Gear:FireServer("Roll", 1)
	end)
	create("UIStroke", { Color = Color3.fromRGB(170, 150, 240), ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Thickness = 1.5, Transparency = 0.2 }, rollOne)
	local rollMany = makeButton({
		Size = UDim2.new(0, 224, 0, 92), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
		Text = "", TextSize = 21, Font = Enum.Font.GothamBold, BackgroundColor3 = PURPLE,
	}, bar, function()
		local many = math.min(10, player:GetAttribute("Tickets") or 0)
		local setCost = Config.GetGachaSetCost(math.min(player:GetAttribute("GachaSet") or 0, player:GetAttribute("MaxZone") or 1))
		if setCost > 0 then many = math.min(many, math.floor((player:GetAttribute("Gold") or 0) / setCost)) end
		if many >= 2 then Remotes.Gear:FireServer("Roll", many) end
	end)
	create("UIStroke", { Color = Color3.fromRGB(255, 225, 140), ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Thickness = 3 }, rollMany)
	rollMany.ClipsDescendants = true
	local shimmer = create("Frame", {
		Size = UDim2.new(0, 40, 1.8, 0), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(-0.2, 0, 0.5, 0), Rotation = 20,
		BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.7, BorderSizePixel = 0, ZIndex = 3,
	}, rollMany)

	-- 빛줄기 / 구슬 테두리가 천천히 돈다 (창이 열려 있을 때만)
	local flashColor, flashUntil = nil, 0
	RunService.RenderStepped:Connect(function()
		if not panel.Visible then return end
		local t = os.clock()
		rays.Rotation = (t * 18) % 360
		orbRing.Rotation = (t * 90) % 360
		local hot = t < flashUntil
		for _, ray in ipairs(rayParts) do
			ray.BackgroundColor3 = hot and flashColor or Color3.fromRGB(255, 220, 150)
			ray.BackgroundTransparency = hot and 0.55 or 0.88
		end
		if not hot then orbScale.Scale = 1 + 0.03 * math.sin(t * 2.5) end
	end)
	task.spawn(function()
		while panel.Parent do
			if panel.Visible and (player:GetAttribute("Tickets") or 0) > 0 then
				shimmer.Position = UDim2.new(-0.1, 0, 0.5, 0)
				TweenService:Create(shimmer, TweenInfo.new(0.9, Enum.EasingStyle.Quad), { Position = UDim2.new(1.1, 0, 0.5, 0) }):Play()
			end
			task.wait(2)
		end
	end)

	local api = { Panel = panel, Message = message }
	-- 뽑기 결과가 오면 구슬이 등급 색으로 번쩍인다
	function api.Flash(color)
		flashColor, flashUntil = color, os.clock() + 1.2
		orbScale.Scale = 1.25
		TweenService:Create(orbScale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	function api.Refresh()
		local tickets = player:GetAttribute("Tickets") or 0
		ticketLabel.Text = string.format("🎫 Tickets: %d", tickets)
		ticketLabel.TextColor3 = tickets > 0 and Color3.fromRGB(255, 235, 160) or Color3.fromRGB(170, 165, 190)
		local setCost = Config.GetGachaSetCost(math.min(player:GetAttribute("GachaSet") or 0, player:GetAttribute("MaxZone") or 1)) -- 세트를 골랐으면 한 번에 이만큼의 골드가 든다
		local gold = player:GetAttribute("Gold") or 0
		rollOne.Text = setCost > 0 and string.format("🎰 Roll x1\n1 Ticket\n💰 %s G", string.format("%d", setCost)) or "🎰 Roll x1\n1 Ticket"
		rollOne.TextSize = setCost > 0 and 16 or 19
		rollOne.BackgroundColor3 = (tickets > 0 and gold >= setCost) and Color3.fromRGB(84, 62, 140) or Color3.fromRGB(60, 56, 76)
		local many = math.min(10, tickets)
		if setCost > 0 then many = math.min(many, math.floor(gold / setCost)) end -- 골드가 모자라면 살 수 있는 만큼만
		local canMany = many >= 2
		rollMany.AutoButtonColor = canMany
		rollMany.BackgroundColor3 = canMany and PURPLE or Color3.fromRGB(62, 58, 78)
		rollMany.TextTransparency = canMany and 0 or 0.45
		rollMany.Text = canMany and (setCost > 0 and string.format("🎰 Roll x%d!\n%d Tickets\n💰 %d G", many, many, setCost * many) or string.format("🎰 Roll x%d!\n%d Tickets", many, many)) or "🎰 Multi Roll\nNeeds 2+ Tickets (max 10)"
		local l, m = player:GetAttribute("GachaPityL"), player:GetAttribute("GachaPityM")
		paintPity(pityL, l or Config.Gacha.Pity.Legendary, "⭐ Legendary guaranteed in %d")
		paintPity(pityM, m or Config.Gacha.Pity.Mythic, "🌈 Mythic in %d")
	end
	for _, name in ipairs({ "Tickets", "GachaPityL", "GachaPityM", "GachaSet", "Gold", "MaxZone" }) do
		player:GetAttributeChangedSignal(name):Connect(function()
			if panel.Visible then api.Refresh() end
		end)
	end
	api.Refresh()
	return api
end

return M
