-- TrainingTree (ReplicatedStorage 안의 ModuleScript, 이름: TrainingTree)
-- 성장 탭의 "훈련장"을 목록 대신 특성 나무처럼 그린다 (서버 동작은 그대로: Remotes.Growth "Train" / "Skip").
--   맨 위 뿌리(🏋) -> 가지 4개(공격 / 체력 / 치명타 / 속도). 가지마다 5단계마다 노드 하나(Lv5 ~ Lv30), 찍은 만큼 색이 채워진다.
--   가지를 누르면 아래 칸에 다음 단계 효과 / 시간 / 골드와 [훈련 시작] 또는 [시간 건너뛰기] 버튼이 나온다.
-- PlayerClient 의 buildGrowthTab 이 Build(env) 를 부른다 (PlayerClient 가 용량 / 지역 변수 한도에 가까워서 따로 뺐다).

local M = {}

local COLORS = {
	Attack = Color3.fromRGB(255, 120, 80),
	Health = Color3.fromRGB(255, 90, 130),
	Crit = Color3.fromRGB(255, 210, 80),
	Speed = Color3.fromRGB(90, 210, 255),
}
local TIER_STEP = 5
local selected = nil -- 마지막으로 고른 가지 (메뉴를 다시 그려도 유지)

-- env: { Config, Remotes, State, NewRow, MakeLabel, MakeButton, Create, Rounded, Remaining(endAt), GREEN, GRAY, Refresh }
function M.Build(env)
	local Config, state = env.Config, env.State
	local G = Config.Growth
	local order = G.Stats.Order
	local maxLevel = G.MaxLevel
	local tiers = math.floor(maxLevel / TIER_STEP)
	local create, label = env.Create, env.MakeLabel

	local jobs = {}
	for _, job in ipairs(state.Jobs) do jobs[job.Stat] = job end
	if not selected or not G.Stats[selected] then
		selected = order[1]
		for _, stat in ipairs(order) do if jobs[stat] then selected = stat break end end
	end

	-- 1) 나무
	local treeH = 120 + tiers * 44 + 20
	local row = env.NewRow(treeH, Color3.fromRGB(20, 18, 34))
	row.ClipsDescendants = true
	create("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 140, 190)), Rotation = 90 }, row)
	local function line(x0, y0, x1, y1, color, thick)
		-- 가로 / 세로 선만 (x 는 0~1 비율, y 는 픽셀)
		local f = create("Frame", { BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 2 }, row)
		if x0 == x1 then
			f.Size = UDim2.new(0, thick, 0, math.abs(y1 - y0))
			f.Position = UDim2.new(x0, -thick / 2, 0, math.min(y0, y1))
		else
			f.Size = UDim2.new(math.abs(x1 - x0), 0, 0, thick)
			f.Position = UDim2.new(math.min(x0, x1), 0, 0, y0 - thick / 2)
		end
		return f
	end
	local function node(x, y, size, fill, stroke, strokeW, text, textSize)
		local n = create("Frame", { Size = UDim2.new(0, size, 0, size), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(x, 0, 0, y), BackgroundColor3 = fill, BorderSizePixel = 0, ZIndex = 4 }, row)
		create("UICorner", { CornerRadius = UDim.new(1, 0) }, n)
		local s = create("UIStroke", { Color = stroke, Thickness = strokeW }, n)
		if text then label({ Size = UDim2.new(1, 0, 1, 0), Text = text, TextSize = textSize or 16, ZIndex = 5 }, n) end
		return n, s
	end

	local dim = Color3.fromRGB(70, 66, 96)
	local xs = {}
	for i = 1, #order do xs[i] = (i - 0.5) / #order end
	-- 뿌리 + 가로 가지
	local rootY, barY, headY = 26, 52, 92
	line(0.5, rootY, 0.5, barY, Color3.fromRGB(225, 196, 118), 3)
	line(xs[1], barY, xs[#xs], barY, Color3.fromRGB(225, 196, 118), 3)
	node(0.5, rootY, 40, Color3.fromRGB(48, 40, 24), Color3.fromRGB(225, 196, 118), 2.5, "🏋", 20)
	label({ Size = UDim2.new(0, 220, 0, 18), Position = UDim2.new(0.5, 26, 0, rootY - 9), Text = string.format("Training slots %d / %d", #state.Jobs, state.Slots), TextSize = 12, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(225, 196, 118), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5 }, row)

	for i, stat in ipairs(order) do
		local def = G.Stats[stat]
		local color = COLORS[stat] or Color3.fromRGB(200, 200, 220)
		local level = state.Levels[stat] or 0
		local x = xs[i]
		local isSel = stat == selected
		-- 고른 가지는 은은하게 밝은 기둥
		if isSel then
			local glow = create("Frame", { Size = UDim2.new(1 / #order, -8, 1, -barY - 4), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(x, 0, 0, barY + 4), BackgroundColor3 = color, BackgroundTransparency = 0.88, BorderSizePixel = 0, ZIndex = 1 }, row)
			create("UICorner", { CornerRadius = UDim.new(0, 12) }, glow)
		end
		line(x, barY, x, headY, level > 0 and color or dim, 3)
		-- 머리 노드: 큰 아이콘 + 이름 / 레벨
		local _, headStroke = node(x, headY, 50, color:Lerp(Color3.fromRGB(20, 18, 34), 0.7), level > 0 and color or dim, isSel and 4 or 2.5, def.Icon, 24)
		if jobs[stat] then headStroke.Color = Color3.fromRGB(255, 225, 120) end
		label({ Size = UDim2.new(1 / #order, -10, 0, 16), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(x, 0, 0, headY + 28), Text = string.format("<b>%s</b>  Lv.%d", def.Name, level), RichText = true, TextSize = 12, ZIndex = 5 }, row)
		if jobs[stat] then
			label({ Size = UDim2.new(1 / #order, -10, 0, 14), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(x, 0, 0, headY + 44), Text = "⏳ " .. Config.FormatDuration(env.Remaining(jobs[stat].EndAt)), TextSize = 11, TextColor3 = Color3.fromRGB(255, 225, 120), ZIndex = 5 }, row)
		end
		-- 단계 노드: Lv5, 10, ... 30
		local prevY = headY + 25
		for t = 1, tiers do
			local tierLevel = t * TIER_STEP
			local y = headY + 70 + (t - 1) * 44
			local reached = level >= tierLevel
			local partial = not reached and level > tierLevel - TIER_STEP -- 지금 채우는 중인 단계
			line(x, prevY, x, y - 13, reached and color or dim, reached and 3 or 2)
			local fill = reached and color or (partial and color:Lerp(Color3.fromRGB(20, 18, 34), 0.7) or Color3.fromRGB(32, 30, 48))
			local _, s = node(x, y, 26, fill, reached and Color3.fromRGB(255, 255, 255) or (partial and color or dim), reached and 2 or 1.5, nil)
			if partial then
				label({ Size = UDim2.new(1, 0, 1, 0), Text = string.format("%d/%d", level - (tierLevel - TIER_STEP), TIER_STEP), TextSize = 9, Font = Enum.Font.GothamBold, ZIndex = 6 }, s.Parent)
			end
			label({ Size = UDim2.new(0, 120, 0, 16), Position = UDim2.new(x, 18, 0, y - 8), Text = Config.FormatTrainEffect(stat, tierLevel), TextSize = 10, TextColor3 = reached and color or Color3.fromRGB(130, 128, 155), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5 }, row)
			prevY = y + 13
		end
		-- 가지 전체를 누르면 고른다
		local hit = create("TextButton", { Size = UDim2.new(1 / #order, 0, 1, -barY), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(x, 0, 0, barY), BackgroundTransparency = 1, Text = "", ZIndex = 8 }, row)
		hit.Activated:Connect(function()
			selected = stat
			if env.Refresh then env.Refresh() end
		end)
	end

	-- 2) 고른 가지의 상세 + 버튼
	local stat = selected
	local def = G.Stats[stat]
	local level = state.Levels[stat] or 0
	local job = jobs[stat]
	local detail = env.NewRow(76, Color3.fromRGB(30, 28, 46))
	local color = COLORS[stat] or Color3.fromRGB(200, 200, 220)
	create("UIStroke", { Color = color, Thickness = 1.5, Transparency = 0.3 }, detail)
	local status
	if job then
		status = string.format("<font color='#ffd966'>Training · Time left %s</font>", Config.FormatDuration(env.Remaining(job.EndAt)))
	elseif level >= maxLevel then
		status = "<font color='#78ff8c'>Max level!</font>"
	else
		status = string.format("<font color='#bbbbcc'>Time needed %s · 💰 %d G</font>", Config.FormatDuration(Config.GetTrainTime(level)), Config.GetTrainGold(level))
	end
	local nextText = level < maxLevel and ("  →  <font color='#78ff8c'>" .. Config.FormatTrainEffect(stat, level + 1) .. "</font>") or ""
	label({
		Size = UDim2.new(1, -200, 1, -12), Position = UDim2.new(0, 14, 0, 6), RichText = true, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
		Text = string.format("<font size='15'><b>%s %s</b></font>  Lv.%d / %d\n%s%s\n%s", def.Icon, def.Name, level, maxLevel, Config.FormatTrainEffect(stat, level), nextText, status),
	}, detail)
	if job then
		env.MakeButton({
			Size = UDim2.new(0, 170, 0, 40), Position = UDim2.new(1, -182, 0.5, -20), Text = "⏱ Use Time Skip", TextSize = 13,
			BackgroundColor3 = state.TimeSkip > 0 and Color3.fromRGB(200, 130, 40) or env.GRAY,
		}, detail, function() env.Remotes.Growth:FireServer("Skip", "Train", stat) end)
	elseif level < maxLevel then
		env.MakeButton({
			Size = UDim2.new(0, 170, 0, 40), Position = UDim2.new(1, -182, 0.5, -20), Text = "Start Training", TextSize = 14, BackgroundColor3 = env.GREEN,
		}, detail, function() env.Remotes.Growth:FireServer("Train", stat) end)
	end
end

return M
