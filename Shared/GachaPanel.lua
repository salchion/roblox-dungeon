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
	local W, H = 720, 520
	local PURPLE = Color3.fromRGB(165, 70, 245)

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
	local ticketLabel = makeLabel({
		Size = UDim2.new(0, 240, 0, 34), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0, CX, 0, CY + 84), Text = "", RichText = true,
		Font = Enum.Font.GothamBlack, TextSize = 24, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.5, ZIndex = 4,
	}, panel)
	local message = makeLabel({
		Size = UDim2.new(1, -40, 0, 22), Position = UDim2.new(0, 20, 0, CY + 120), Text = "", RichText = true, TextSize = 13, Font = Enum.Font.GothamBold, ZIndex = 4,
	}, panel)

	------------------------------------------------------------
	-- 왼쪽: 등급 확률 (등급 색 구슬 + %)
	------------------------------------------------------------
	makeLabel({ Size = UDim2.new(0, 170, 0, 20), Position = UDim2.new(0, 26, 0, 58), Text = "Rates", TextSize = 13, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(230, 210, 255) }, panel)
	for index, rate in ipairs(Config.Gacha.Rates) do
		local color = Config.Gear.RarityColors[index]
		local chip = create("Frame", { Size = UDim2.new(0, 170, 0, 34), Position = UDim2.new(0, 26, 0, 80 + (index - 1) * 40), BackgroundColor3 = Color3.fromRGB(30, 24, 50), BorderSizePixel = 0, ZIndex = 3 }, panel)
		rounded(chip, 17)
		create("UIStroke", { Color = color, Thickness = index >= 4 and 2.5 or 1.5, Transparency = 0.15 }, chip)
		local dot = create("Frame", { Size = UDim2.new(0, 22, 0, 22), Position = UDim2.new(0, 7, 0.5, -11), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 4 }, chip)
		rounded(dot, 11)
		makeLabel({ Size = UDim2.new(1, -90, 1, 0), Position = UDim2.new(0, 36, 0, 0), Text = Config.Gear.RarityNames[index], TextSize = 13, Font = Enum.Font.GothamBold, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 }, chip)
		makeLabel({ Size = UDim2.new(0, 52, 1, 0), Position = UDim2.new(1, -58, 0, 0), Text = rate .. "%", TextSize = 14, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 4 }, chip)
	end
	makeButton({ Size = UDim2.new(0, 170, 0, 28), Position = UDim2.new(0, 26, 0, 284), Text = "📊 Odds", TextSize = 13, BackgroundColor3 = Color3.fromRGB(60, 72, 130) }, panel, function()
		player:SetAttribute("OddsKind", "Gacha") -- OddsClient 가 확률 창을 연다 (유료 랜덤 아이템 정책)
		player:SetAttribute("OddsOpen", os.clock())
	end)

	------------------------------------------------------------
	-- 오른쪽: 천장 게이지 (전설 / 신화 확정까지)
	------------------------------------------------------------
	makeLabel({ Size = UDim2.new(0, 180, 0, 20), Position = UDim2.new(1, -206, 0, 58), Text = "Pity", TextSize = 13, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(230, 210, 255) }, panel)
	local function pityGauge(y, color, total)
		local card = create("Frame", { Size = UDim2.new(0, 180, 0, 92), Position = UDim2.new(1, -206, 0, y), BackgroundColor3 = Color3.fromRGB(30, 24, 50), BorderSizePixel = 0, ZIndex = 3 }, panel)
		rounded(card, 12)
		create("UIStroke", { Color = color, Thickness = 2, Transparency = 0.2 }, card)
		local title = makeLabel({ Size = UDim2.new(1, -16, 0, 40), Position = UDim2.new(0, 8, 0, 6), Text = "", RichText = true, TextSize = 13, Font = Enum.Font.GothamBold, TextColor3 = color, TextWrapped = true, ZIndex = 4 }, card)
		local back = create("Frame", { Size = UDim2.new(1, -20, 0, 14), Position = UDim2.new(0, 10, 0, 52), BackgroundColor3 = Color3.fromRGB(14, 12, 24), BorderSizePixel = 0, ZIndex = 4 }, card)
		rounded(back, 7)
		local fill = create("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 5 }, back)
		rounded(fill, 7)
		local count = makeLabel({ Size = UDim2.new(1, -20, 0, 16), Position = UDim2.new(0, 10, 0, 70), Text = "", TextSize = 10, TextColor3 = Color3.fromRGB(200, 196, 225), ZIndex = 4 }, card)
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
	-- 아래: 뽑기 버튼
	------------------------------------------------------------
	local bar = create("Frame", { Size = UDim2.new(1, -36, 0, 128), Position = UDim2.new(0, 18, 1, -142), BackgroundColor3 = Color3.fromRGB(58, 38, 92), BorderSizePixel = 0 }, panel)
	rounded(bar, 14)
	create("UIStroke", { Color = Color3.fromRGB(255, 210, 120), Thickness = 2 }, bar)
	create("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(110, 60, 170), Color3.fromRGB(48, 30, 80)), Rotation = 0 }, bar)
	makeLabel({
		Size = UDim2.new(0, 200, 1, -20), Position = UDim2.new(0, 16, 0, 10), TextSize = 11, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(215, 205, 240), Text = "Same or lower rarity converts to Gold · Tickets drop from dungeons / field bosses",
	}, bar)
	local rollOne = makeButton({
		Size = UDim2.new(0, 200, 0, 92), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -244, 0.5, 0),
		Text = "🎰 Roll x1\n1 Ticket", TextSize = 19, Font = Enum.Font.GothamBold, BackgroundColor3 = Color3.fromRGB(120, 80, 210),
	}, bar, function()
		Remotes.Gear:FireServer("Roll", 1)
	end)
	create("UIStroke", { Color = Color3.fromRGB(190, 170, 255), ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Thickness = 2 }, rollOne)
	local rollMany = makeButton({
		Size = UDim2.new(0, 224, 0, 92), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
		Text = "", TextSize = 21, Font = Enum.Font.GothamBold, BackgroundColor3 = PURPLE,
	}, bar, function()
		local many = math.min(10, player:GetAttribute("Tickets") or 0)
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
		rollOne.BackgroundColor3 = tickets > 0 and Color3.fromRGB(120, 80, 210) or Color3.fromRGB(80, 70, 100)
		local many = math.min(10, tickets)
		local canMany = many >= 2
		rollMany.AutoButtonColor = canMany
		rollMany.BackgroundColor3 = canMany and PURPLE or Color3.fromRGB(62, 58, 78)
		rollMany.TextTransparency = canMany and 0 or 0.45
		rollMany.Text = canMany and string.format("🎰 Roll x%d!\n%d Tickets", many, many) or "🎰 Multi Roll\nNeeds 2+ Tickets (max 10)"
		local l, m = player:GetAttribute("GachaPityL"), player:GetAttribute("GachaPityM")
		paintPity(pityL, l or Config.Gacha.Pity.Legendary, "⭐ Legendary guaranteed in %d")
		paintPity(pityM, m or Config.Gacha.Pity.Mythic, "🌈 Mythic in %d")
	end
	for _, name in ipairs({ "Tickets", "GachaPityL", "GachaPityM" }) do
		player:GetAttributeChangedSignal(name):Connect(function()
			if panel.Visible then api.Refresh() end
		end)
	end
	api.Refresh()
	return api
end

return M
