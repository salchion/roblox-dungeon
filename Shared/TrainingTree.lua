-- TrainingTree (ReplicatedStorage 안의 ModuleScript, 이름: TrainingTree)
-- 성장 탭 전체를 한 장의 "특성 나무" 로 그린다. 한눈에 보이게 세 칸으로 나란히:
--   왼쪽  ⚔ 스킬: C / F / V (액티브) + 패시브 스킬
--   가운데 🏋 훈련: 1층(공격 / 체력 / 치명타 / 속도) -> 2층(더블샷 / 골드 감각 / 치명타 피해) -> 3층(공격 속도)
--          아래 칸은 선으로 이어진 위 칸의 단계를 채워야 열린다 (Config.Growth.Stats[키].Req). 동시에 여러 칸 훈련 가능
--   오른쪽 🐾 펫: 기능들이 사슬처럼 이어진다
-- 노드를 누르면 나무 바로 아래 한 줄에 설명 + 버튼 (강화 / 훈련 / 펫 레벨업 / 시간 건너뛰기).
-- 서버 동작은 그대로다 (Growth "Train" / "Skip", Meta "SkillUp" / "PetUnlock" / "PetLevel"). 잠긴 칸은 서버도 막는다.
-- PlayerClient 가 BuildAll(env) 을 부른다 (PlayerClient 가 용량 / 지역 변수 한도에 가까워서 따로 뺐다).

local M = {}

local DARK = Color3.fromRGB(20, 18, 34)
local DIM = Color3.fromRGB(70, 66, 96)
local GOLD = Color3.fromRGB(225, 196, 118)
local PET_COLOR = Color3.fromRGB(255, 200, 120)
local TIER_Y = { 66, 152, 238 } -- 세 칸이 같은 높이의 층을 쓴다
local CARD_H = 36 -- 노드 카드 높이
local CANVAS_H = 272 -- (306 -> 272: 성장 탭이 스크롤 없이 한 화면에 들어가게)
-- 칸마다 가로 범위 (0~1): 스킬(액티브 3, 세로 한 줄) | 훈련 | 패시브(훈련 바로 옆: 둘 다 상시 효과) | 펫
local COLS = { Skill = { 0, 0.17 }, Train = { 0.17, 0.47 }, Passive = { 0.47, 0.75 }, Pet = { 0.75, 1 } } -- (Passive = 특성 트리)
local selected = { Kind = "Skill", Key = nil } -- 마지막으로 고른 노드 (메뉴를 다시 그려도 유지)

local TRAIN_COLORS = {
	Attack = Color3.fromRGB(255, 120, 80), Health = Color3.fromRGB(255, 90, 130), Crit = Color3.fromRGB(255, 210, 80), Speed = Color3.fromRGB(90, 210, 255),
	Armor = Color3.fromRGB(120, 170, 255), Regen = Color3.fromRGB(255, 120, 190), Double = Color3.fromRGB(255, 160, 90), Gold = Color3.fromRGB(255, 215, 90), CritDmg = Color3.fromRGB(255, 120, 60), AtkSpeed = Color3.fromRGB(140, 220, 255),
}
-- 훈련 노드 자리: { 칸 안의 x(0~1), 층 }
-- 유형별 줄: 왼쪽 두 줄 = 공격(공격 -> 더블샷, 치명타 -> 치명타 피해, 둘 다 -> 공격 속도) / 체력 = 방어 / 오른쪽 = 유틸(속도 -> 골드 감각)
local TRAIN_ORDER = { "Attack", "Crit", "Double", "CritDmg", "AtkSpeed", "Health", "Speed", "Armor", "Gold", "Regen" }
local TRAIN_SPOT = { -- { 칸 안의 x(0~1), y } : 공격 묶음 (위) / 생존·유틸 묶음 (아래, 조금 띄움)
	Attack = { 0.25, 50 }, Crit = { 0.75, 50 }, Double = { 0.25, 88 }, CritDmg = { 0.75, 88 }, AtkSpeed = { 0.5, 126, true },
	Health = { 0.25, 172 }, Speed = { 0.75, 172 }, Armor = { 0.25, 210 }, Gold = { 0.75, 210 }, Regen = { 0.25, 248 },
}
local TRAIN_POS = {
	Attack = { 0.125, 1 }, Crit = { 0.375, 1 }, Health = { 0.625, 1 }, Speed = { 0.875, 1 },
	Double = { 0.125, 2 }, CritDmg = { 0.375, 2 }, Armor = { 0.625, 2 }, Gold = { 0.875, 2 }, AtkSpeed = { 0.25, 3 }, Regen = { 0.625, 3 },
}

local function colX(col, fraction)
	local range = COLS[col]
	return range[1] + (range[2] - range[1]) * fraction
end

local function comma(n)
	local s = tostring(math.floor(n or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function isSel(kind, key)
	return selected.Kind == kind and selected.Key == key
end

-- 나무 한 장 (세 칸 공용) + 그리는 도구
local function canvas(env)
	local create, label = env.Create, env.MakeLabel
	local row = env.NewRow(CANVAS_H, DARK)
	row.ClipsDescendants = true
	create("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 140, 190)), Rotation = 90 }, row)
	local C = { Row = row }
	-- 칸 제목: 금테 리본 (가운데 정렬, 양끝이 어두워지는 그라데이션)
	function C.title(col, text)
		local range = COLS[col]
		local ribbon = create("Frame", { Size = UDim2.new(range[2] - range[1], -14, 0, 24), Position = UDim2.new(range[1], 7, 0, 7), BackgroundColor3 = Color3.fromRGB(58, 44, 30), BorderSizePixel = 0, ZIndex = 4 }, row)
		create("UICorner", { CornerRadius = UDim.new(0, 6) }, ribbon)
		create("UIGradient", { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(70, 60, 90)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(70, 60, 90)) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 0.6) }) }, ribbon)
		local edge = create("UIStroke", { Color = GOLD, Thickness = 1.2, Transparency = 0.25, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, ribbon)
		create("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 0.9) }) }, edge)
		label({ Size = UDim2.new(1, -8, 1, 0), Position = UDim2.new(0, 4, 0, 0), Text = text, RichText = true, TextSize = 13, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 226, 150),
			TextStrokeTransparency = 0.3, TextStrokeColor3 = Color3.fromRGB(40, 24, 10), ZIndex = 5 }, ribbon)
	end
	function C.divider(x)
		create("Frame", { Size = UDim2.new(0, 2, 1, -24), Position = UDim2.new(x, -1, 0, 12), BackgroundColor3 = Color3.fromRGB(60, 56, 88), BackgroundTransparency = 0.3, BorderSizePixel = 0, ZIndex = 2 }, row)
	end
	function C.line(x0, y0, x1, y1, color, thick)
		local f = create("Frame", { BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 2 }, row)
		if x0 == x1 then
			f.Size = UDim2.new(0, thick, 0, math.abs(y1 - y0))
			f.Position = UDim2.new(x0, -thick / 2, 0, math.min(y0, y1))
		else
			f.Size = UDim2.new(math.abs(x1 - x0), thick, 0, thick)
			f.Position = UDim2.new(math.min(x0, x1), -thick / 2, 0, y0 - thick / 2)
		end
	end
	-- ㄴ자 연결선: (x0, y0) 아래로 -> 가운데 높이에서 옆으로 -> (x1, y1) 위까지
	function C.elbow(x0, y0, x1, y1, color, thick)
		local mid = (y0 + y1) / 2
		C.line(x0, y0, x0, mid, color, thick)
		if x0 ~= x1 then C.line(x0, mid, x1, mid, color, thick) end
		C.line(x1, mid, x1, y1, color, thick)
	end
	-- 노드 = 납작한 카드 (예전: 동그라미 + 아래 글자 두 줄이라 세로 공간을 많이 먹어 칸이 모자랐다)
	--   [아이콘] 이름 / Lv (또는 남은 시간) + 아래 진행 막대. state = "done" / "active"(찍는 중) / "open" / "locked"
	--   width: 카드 너비 (나무 전체 너비 대비 비율, 0~1)
	-- 소켓 중심 (나무 선을 이을 때 쓴다): 칸 왼쪽에서 조금 안쪽
	function C.cx(x, width) return x - width / 2 + 0.024 end
	-- 노드 = 네모 판 없이 "금속 테두리 원형 소켓 + 오른쪽 이름 / 레벨 + 가는 막대". 고르거나 찍는 중일 때만 옅은 빛이 깔린다
	function C.node(x, y, icon, color, state, ratio, caption, sub, chosen, width, onClick)
		local locked = state == "locked"
		local cx = C.cx(x, width)
		if chosen or state == "active" then -- 옅은 빛 띠 (네모 판이 아니라 양끝이 사라지는 빛)
			local glowBand = create("Frame", { Size = UDim2.new(width, -10, 0, 30), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(x, 0, 0, y), BackgroundColor3 = chosen and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(255, 220, 120), BorderSizePixel = 0, ZIndex = 3 }, row)
			create("UICorner", { CornerRadius = UDim.new(1, 0) }, glowBand)
			create("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.82), NumberSequenceKeypoint.new(0.6, 0.9), NumberSequenceKeypoint.new(1, 1) }) }, glowBand)
		end
		local socket = create("Frame", { Size = UDim2.new(0, 28, 0, 28), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(cx, 0, 0, y), BackgroundColor3 = locked and Color3.fromRGB(32, 30, 46) or color:Lerp(DARK, state == "done" and 0.25 or 0.5), BorderSizePixel = 0, ZIndex = 6 }, row)
		create("UICorner", { CornerRadius = UDim.new(1, 0) }, socket)
		create("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(100, 92, 130)), Rotation = 45 }, socket)
		local ring = create("UIStroke", { Thickness = chosen and 2.6 or 1.8, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = chosen and Color3.new(1, 1, 1) or (locked and Color3.fromRGB(80, 76, 100) or (state == "done" and Color3.fromRGB(255, 214, 110) or Color3.fromRGB(225, 196, 130))) }, socket)
		if not locked and not chosen then create("UIGradient", { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 248, 220)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(150, 112, 52)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 232, 165)) }), Rotation = 45 }, ring) end
		label({ Size = UDim2.new(1, 0, 1, 0), Text = locked and "🔒" or icon, TextSize = locked and 10 or 13, ZIndex = 7 }, socket)
		label({ Size = UDim2.new(width, -46, 0, 14), Position = UDim2.new(cx, 20, 0, y - 13), Text = caption, RichText = true, TextSize = 11, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.GothamBlack, ZIndex = 5,
			TextColor3 = locked and Color3.fromRGB(135, 131, 160) or Color3.new(1, 1, 1), TextStrokeTransparency = 0.45, TextStrokeColor3 = Color3.fromRGB(10, 8, 20) }, row)
		if sub and sub ~= "" then
			label({ Size = UDim2.new(width, -46, 0, 11), Position = UDim2.new(cx, 20, 0, y + 1), Text = sub, RichText = true, TextSize = 9, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5,
				TextColor3 = state == "active" and Color3.fromRGB(255, 225, 120) or Color3.fromRGB(180, 176, 205) }, row)
		end
		if not locked then -- 아주 가는 진행 막대 (글자 아래)
			local bar = create("Frame", { Size = UDim2.new(width * 0.5, 0, 0, 2), Position = UDim2.new(cx, 20, 0, y + 13), BackgroundColor3 = Color3.fromRGB(20, 18, 32), BorderSizePixel = 0, ZIndex = 5 }, row)
			create("Frame", { Size = UDim2.new(math.clamp(ratio or 0, 0, 1), 0, 1, 0), BackgroundColor3 = state == "done" and Color3.fromRGB(255, 214, 110) or color, BorderSizePixel = 0, ZIndex = 6 }, bar)
		end
		if state == "active" then
			game:GetService("TweenService"):Create(ring, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 3.2 }):Play()
		end
		local hit = create("TextButton", { Size = UDim2.new(width, -6, 0, CARD_H), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(x, 0, 0, y), BackgroundTransparency = 1, Text = "", ZIndex = 8 }, row)
		hit.Activated:Connect(onClick)
		return socket
	end
	return C
end

-- 고른 노드의 설명 + 버튼 한 줄 (나무 바로 아래)
-- 스킬 갈래 (레벨 5 / 10): 두 길 중 하나를 고른다. 처음 고르는 건 무료, 바꾸면 골드가 든다 (서버도 확인한다)
-- 스킬을 고르면 설명 줄 오른쪽에 두 줄(Lv.5 / Lv.10)로 붙는다: 스크롤 없이 한 화면에서 본다
local function branchCards(env, key, parent)
	local Config = env.Config
	local defs = Config.SkillBranch and Config.SkillBranch[key]
	if not defs then return end
	local level = env.Meta and env.Meta.Skills and env.Meta.Skills[key] or 1
	do -- 나무 줄기: Lv 표시를 세로로 잇는 선 (갈래가 단계마다 갈라지는 모양)
		local rows = #Config.SkillBranchTiers
		local trunk = env.Create("Frame", { Size = UDim2.new(0, 2, 0, 38 * (rows - 1)), Position = UDim2.new(0.44, 22, 0, 23), BackgroundColor3 = Color3.fromRGB(150, 120, 70), BorderSizePixel = 0, ZIndex = 2 }, parent)
		trunk.BackgroundTransparency = 0.3
	end
	for rowIndex, tier in ipairs(Config.SkillBranchTiers) do
		local pair = defs[tier]
		if pair then
			local orLabel = env.MakeLabel({ Size = UDim2.new(0, 18, 0, 14), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.44 + 0.07 + (0.56 - 0.07) / 2, 1, 0, 6 + (rowIndex - 1) * 38 + 17), Text = "or", TextSize = 9, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(220, 200, 150) }, parent)
			orLabel.ZIndex = 6
			local chosen = env.Player:GetAttribute("SkillBr" .. tier .. "_" .. key)
			local unlocked = level >= tier
			local y = 6 + (rowIndex - 1) * 38 -- (갈래가 네 단계로 늘어 한 줄을 낮췄다: 아래가 잘렸다)
			local tag = env.MakeLabel({ Size = UDim2.new(0, 46, 0, 34), Position = UDim2.new(0.44, 0, 0, y), RichText = true, TextSize = 12, TextWrapped = true,
				Text = string.format("<font color='#ffd966'><b>Lv.%d</b></font>\n%s", tier, unlocked and (chosen and "<font color='#78ff8c' size='10'>✔</font>" or "") or "🔒") }, parent)
			tag.ZIndex = 3
			for index, side in ipairs({ "A", "B" }) do
				local def = pair[side]
				local picked = chosen == side
				local cost = chosen and not picked and math.floor(Config.GetSkillUpgradeCost(tier) * Config.SkillBranchSwapRatio) or nil
				local text = string.format("%s %s\n%s", picked and "✔" or def.Icon, def.Name, def.Desc)
				if cost then text = text .. string.format("\nSwitch path: %s G", comma(cost)) end
				local button = env.MakeButton({
					Size = UDim2.new(0.56, -52, 0, 34), Position = UDim2.new(0.44, 46 + (index - 1) * 0, 0, y), TextSize = 9, TextWrapped = true, Text = text,
					BackgroundColor3 = picked and Color3.fromRGB(46, 112, 84) or (unlocked and Color3.fromRGB(58, 60, 92) or Color3.fromRGB(44, 44, 56)),
					TextColor3 = unlocked and Color3.new(1, 1, 1) or Color3.fromRGB(150, 150, 170),
				}, parent, function()
					if unlocked and not picked then env.Remotes.Meta:FireServer("SkillBranch", string.format("%s|%d|%s", key, tier, side)) end
				end)
				button.AnchorPoint = Vector2.new(0, 0)
				button.Size = UDim2.new((0.56 - 0.07) / 2, -4, 0, 34)
				button.Position = UDim2.new(0.44 + 0.07 + (index - 1) * ((0.56 - 0.07) / 2), 2, 0, y)
			end
		end
	end
end

local function detailRow(env, color, text, button, skillKey, tall)
	local create, label = env.Create, env.MakeLabel
	local withBranch = skillKey ~= nil and env.Config.SkillBranch ~= nil and env.Config.SkillBranch[skillKey] ~= nil
	local detail = env.NewRow(withBranch and (12 + 38 * #env.Config.SkillBranchTiers) or ((skillKey or tall) and 124 or 76), Color3.fromRGB(30, 28, 46)) -- (갈래 단계 수만큼: Lv.3 / 5 / 7 / 10 = 네 줄) -- (스킬: 지금 ▶ 다음 레벨 비교 줄이 들어갈 자리)
	create("UIStroke", { Color = color, Thickness = 1.5, Transparency = 0.3 }, detail)
	if button and env.InTown == false then -- 필드에서는 업그레이드 못 한다: 버튼이 "마을에서"로 바뀐다 (서버도 막는다)
		button = { Text = "🏘 Upgrade in town", Color = env.GRAY, OnClick = function() end }
	end
	if withBranch then
		-- 설명 + "지금 ▶ 다음 레벨" 비교가 길어 칸을 넘으면 잘리던 것: 이 부분만 살짝 스크롤된다 (마우스 휠 / 드래그)
		local scroller = create("ScrollingFrame", { Size = UDim2.new(0.44, -16, 1, -52), Position = UDim2.new(0, 12, 0, 4), BackgroundTransparency = 1, BorderSizePixel = 0,
			ScrollBarThickness = 4, ScrollBarImageColor3 = Color3.fromRGB(200, 190, 230), ScrollBarImageTransparency = 0.3, ScrollingDirection = Enum.ScrollingDirection.Y,
			CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, ElasticBehavior = Enum.ElasticBehavior.Never }, detail)
		label({ Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, RichText = true, TextSize = 12, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = text }, scroller)
		if button then
			env.MakeButton({ Size = UDim2.new(0.44, -24, 0, 38), Position = UDim2.new(0, 12, 1, -44), Text = button.Text, TextSize = 12, BackgroundColor3 = button.Color }, detail, button.OnClick)
		end
		branchCards(env, skillKey, detail)
		return
	end
	local buttons = (button and button[1]) and button or (button and { button } or {}) -- (버튼 여러 개: 특성 선택 칸 / 초기화)
	label({ Size = UDim2.new(1, -24 - 188 * math.max(1, #buttons), 1, -12), Position = UDim2.new(0, 14, 0, 6), RichText = true, TextSize = 12, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center, Text = text }, detail)
	for index, b in ipairs(buttons) do
		env.MakeButton({ Size = UDim2.new(0, 180, 0, 44), Position = UDim2.new(1, -192 - (#buttons - index) * 188, 0.5, -22), Text = b.Text, TextSize = 12, BackgroundColor3 = b.Color }, detail, b.OnClick)
	end
end

local function pick(env, kind, key)
	return function()
		selected.Kind, selected.Key = kind, key
		if env.Refresh then env.Refresh() end
	end
end

------------------------------------------------------------
-- 1) 스킬 (왼쪽 칸, 2 x 2)
------------------------------------------------------------
local function skillColor(key)
	return key == "Ult" and Color3.fromRGB(255, 200, 80) or (key == "Heal" and Color3.fromRGB(120, 230, 140) or (key == "Focus" and Color3.fromRGB(150, 170, 255) or Color3.fromRGB(255, 140, 200)))
end

local function drawSkills(env, C)
	local Config, meta = env.Config, env.Meta
	local U = Config.SkillUpgrade
	C.title("Skill", "⚔ Skills")
	for index, key in ipairs(Config.Skills.UpgradeOrder) do -- 스킬 칸에 세로 한 줄 (액티브 3 + 기운 집중)
		local cfg = Config.Skills[key]
		local level = meta and meta.Skills and meta.Skills[key] or 1
		local remaining = env.UpgradeRemaining(key)
		local state = level >= U.MaxLevel and "done" or (remaining and "active" or "open")
		C.node(colX("Skill", 0.5), 52 + (index - 1) * 46, cfg.Icon, skillColor(key), state, level / U.MaxLevel, string.format("<b>%s</b>", cfg.Name),
			remaining and ("⏳ " .. Config.FormatDuration(remaining)) or string.format("%sLv.%d / %d", (not cfg.Passive and cfg.Key) and ("[" .. cfg.Key .. "] ") or "", level, U.MaxLevel), isSel("Skill", key), COLS.Skill[2] - COLS.Skill[1], pick(env, "Skill", key))
	end
end

-- 스킬 시너지 한 줄: "🔗 Blade Bloom damage +4% per Focus level" + 지금 얼마나 받고 있는지
local function synergyLine(env, key)
	local Config = env.Config
	local syn = Config.SkillSynergy and Config.SkillSynergy[key]
	if not syn then return "" end
	local fromLevel = env.Meta and env.Meta.Skills and env.Meta.Skills[syn.From] or 1
	local now = syn.Per * math.max(0, fromLevel - 1)
	local shown = syn.Stat == "NearMissTime" and string.format("+%.2fs", now) or string.format("%+d%%", math.floor(now * 100 + (now >= 0 and 0.5 or -0.5)))
	return string.format("\n<font color='#9ad7ff'>🔗 %s</font> <font color='#78ff8c'>(%s)</font>", syn.Text, shown)
end

local function skillDetail(env, key)
	local Config, meta = env.Config, env.Meta
	local U = Config.SkillUpgrade
	local cfg = Config.Skills[key]
	if not cfg then return nil end
	local level = meta and meta.Skills and meta.Skills[key] or 1
	local remaining = env.UpgradeRemaining(key)
	local maxed = level >= U.MaxLevel
	local owned = env.Player:GetAttribute("TimeSkip") or 0
	local button
	if maxed then
		button = nil
	elseif remaining then
		button = { Text = string.format("⏱ Time Skip\n%s left", Config.FormatDuration(remaining)), Color = owned > 0 and Color3.fromRGB(200, 130, 40) or env.GRAY, OnClick = function() env.Remotes.Growth:FireServer("Skip", "Skill", key) end }
	else
		button = { Text = string.format("Upgrade %s G\n⏱ %s", comma(Config.GetSkillUpgradeCost(level)), Config.FormatDuration(Config.GetSkillUpgradeTime(level))), Color = env.GREEN, OnClick = function() env.Remotes.Meta:FireServer("SkillUp", key) end }
	end
	return skillColor(key), string.format("<font size='14'><b>[%s] %s %s</b></font>  <font color='#ffd966'>Lv.%d / %d</font>%s\n<font color='#bbbbcc'>%s</font>",
		cfg.Key or "", cfg.Icon, cfg.Name, level, U.MaxLevel, maxed and "  <font color='#78ff8c'>MAX</font>" or "", cfg.Desc or "") .. (env.SkillDetail and ("\n" .. env.SkillDetail(key, level)) or "") .. synergyLine(env, key), button
end

------------------------------------------------------------
-- 2) 훈련 나무 (가운데 칸)
------------------------------------------------------------
local function drawTraining(env, C)
	local Config, state = env.Config, env.Growth
	local G = Config.Growth
	if env.TrainLocked or not state then
		C.title("Train", "🏋 Training")
		local range = COLS.Train
		env.MakeLabel({ Size = UDim2.new(range[2] - range[1], -20, 0, 60), Position = UDim2.new(range[1], 10, 0, CANVAS_H / 2 - 30), RichText = true, TextWrapped = true, TextSize = 14, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(200, 196, 225), ZIndex = 5,
			Text = env.TrainLocked and "🔒 Unlocks after clearing Zone 2" or "Loading..." }, C.Row)
		return
	end
	local levels = state.Levels
	local jobs = {}
	for _, job in ipairs(state.Jobs) do jobs[job.Stat] = job end
	C.title("Train", string.format("🏋 Training<font size='11' color='#cfc8e8'>   Slots %d / %d</font>", #state.Jobs, state.Slots))
	-- 두 줄씩 놓고, 먼저 찍어야 하는 칸에서 가지가 이어진다 (열렸으면 그 색, 아니면 어두운 선)
	local slotW = (COLS.Train[2] - COLS.Train[1]) / 2
	-- 두 묶음: 위 = 공격(공격 / 치명타 -> 더블 샷 / 치명타 피해 -> 둘이 모여 공격 속도), 아래 = 생존 / 유틸(체력 -> 질긴 피부 -> 회복력, 속도 -> 골드 감각)
	-- 시작 칸은 항상 묶음의 맨 위에 있어서, 가지가 엉뚱한 칸에서 이어지는 것처럼 보이지 않는다
	local spots = {}
	for stat, at in pairs(TRAIN_SPOT) do
		if G.Stats[stat] then
			local x = colX("Train", at[1])
			if at[3] then x += slotW / 2 - 0.024 end -- 가운데 칸: 동그라미가 칸 한가운데 오게 (카드는 동그라미 왼쪽 정렬이라 그냥 두면 왼쪽으로 쏠려 보였다)
			spots[stat] = { X = x, Y = at[2] }
		end
	end
	for stat, spot in pairs(spots) do
		for _, req in ipairs(G.Stats[stat].Req or {}) do
			local from = spots[req.Stat]
			if from then
				local met = (levels[req.Stat] or 0) >= req.Level
				C.elbow(C.cx(from.X, slotW), from.Y + 15, C.cx(spot.X, slotW), spot.Y - 15, met and (TRAIN_COLORS[stat] or GOLD) or Color3.fromRGB(56, 52, 78), met and 2 or 1)
			end
		end
	end
	for _, stat in ipairs(TRAIN_ORDER) do
		local def, spot = G.Stats[stat], spots[stat]
		if def and spot then
			local level = levels[stat] or 0
			local max = Config.TrainMax(stat)
			local unlocked = Config.TrainUnlocked(stat, levels)
			local nodeState = not unlocked and "locked" or (jobs[stat] and "active" or (level >= max and "done" or "open"))
			local sub = jobs[stat] and ("⏳ " .. Config.FormatDuration(env.Remaining(jobs[stat].EndAt))) or string.format("Lv.%d / %d", level, max)
			if not unlocked then
				for _, req in ipairs(def.Req or {}) do
					if (levels[req.Stat] or 0) < req.Level and G.Stats[req.Stat] then sub = string.format("🔒 %s Lv.%d", G.Stats[req.Stat].Name, req.Level) break end
				end
			end
			C.node(spot.X, spot.Y, def.Icon, TRAIN_COLORS[stat] or GOLD, nodeState, level / max, def.Name, sub, isSel("Train", stat), slotW, pick(env, "Train", stat))
		end
	end
end

local function trainDetail(env, stat)
	local Config, state = env.Config, env.Growth
	local G = Config.Growth
	local def = G.Stats[stat]
	if env.TrainLocked or not state or not def then return nil end
	local levels = state.Levels
	local level = levels[stat] or 0
	local max = Config.TrainMax(stat)
	local job
	for _, j in ipairs(state.Jobs) do if j.Stat == stat then job = j end end
	local unlocked = Config.TrainUnlocked(stat, levels)
	local lines = { string.format("<font size='14'><b>%s %s</b></font>  <font color='#ffd966'>Lv.%d / %d</font>", def.Icon, def.Name, level, max) }
	table.insert(lines, Config.FormatTrainEffect(stat, level) .. (level < max and ("  →  <font color='#78ff8c'>" .. Config.FormatTrainEffect(stat, level + 1) .. "</font>") or ""))
	local button
	if not unlocked then
		local need = {}
		for _, req in ipairs(def.Req or {}) do
			local ok = (levels[req.Stat] or 0) >= req.Level
			table.insert(need, string.format("<font color='#%s'>%s</font><font color='#%s'> Lv.%d</font>", ok and "78ff8c" or "ff8a8a", G.Stats[req.Stat].Name, ok and "78ff8c" or "ff8a8a", req.Level))
		end
		table.insert(lines, "🔒 Needs<font> </font>" .. table.concat(need, " + "))
	elseif job then
		table.insert(lines, string.format("<font color='#ffd966'>Training · Time left %s</font>", Config.FormatDuration(env.Remaining(job.EndAt))))
		button = { Text = "⏱ Use Time Skip", Color = state.TimeSkip > 0 and Color3.fromRGB(200, 130, 40) or env.GRAY, OnClick = function() env.Remotes.Growth:FireServer("Skip", "Train", stat) end }
	elseif level >= max then
		table.insert(lines, "<font color='#78ff8c'>Max level!</font>")
	else
		table.insert(lines, string.format("<font color='#bbbbcc'>Time needed %s · 💰 %s G</font>", Config.FormatDuration(Config.GetTrainTime(level, stat)), comma(Config.GetTrainGold(level, stat))))
		button = { Text = "Start Training", Color = env.GREEN, OnClick = function() env.Remotes.Growth:FireServer("Train", stat) end }
	end
	return TRAIN_COLORS[stat] or GOLD, table.concat(lines, "\n"), button
end

------------------------------------------------------------
-- 3) 펫 사슬 (오른쪽 칸, 한 줄에 4개씩 뱀처럼)
------------------------------------------------------------
local PET_PER_ROW = 2 -- (카드 한 줄에 둘, 다섯 줄: 셋이면 이름이 잘렸다)
local function petPos(i)
	local r = (i - 1) // PET_PER_ROW
	local c = (i - 1) % PET_PER_ROW
	return colX("Pet", (c + 0.5) / PET_PER_ROW), 52 + r * 44
end

local function petLevel(env)
	local pet = env.Meta and env.Meta.Pet
	return pet and pet.Unlocked and pet.Level or 0
end

local function drawPet(env, C)
	local P = env.Config.Pet
	local level = petLevel(env)
	local fns = P.Functions
	C.title("Pet", string.format("🐾 Pet<font size='11' color='#cfc8e8'>   Lv.%d / %d</font>", level, P.MaxLevel))
	local nextFn
	for _, fn in ipairs(fns) do
		if fn.Level > level then nextFn = fn break end
	end
	-- (펫 기능은 1 -> 2 -> 3 -> 5 ... 순서로 열려서 세로 선이 틀린 순서를 보여 줬다: 선 없이 줄마다 왼쪽 -> 오른쪽으로 읽는다)
	local upEnd = env.Player:GetAttribute("UpPet")
	for i, fn in ipairs(fns) do
		local x, y = petPos(i)
		local open = level >= fn.Level
		local nodeState = open and "done" or (nextFn == fn and (upEnd and "active" or "open") or "locked")
		C.node(x, y, fn.Icon, PET_COLOR, nodeState, open and 1 or 0, string.format("Lv.%d", fn.Level), fn.Name, isSel("Pet", fn.Level), (COLS.Pet[2] - COLS.Pet[1]) / PET_PER_ROW, pick(env, "Pet", fn.Level))
	end
end

local function petDetail(env, fnLevel)
	local Config, meta = env.Config, env.Meta
	local P = Config.Pet
	local pet = meta and meta.Pet
	local level = petLevel(env)
	local chosen
	for _, fn in ipairs(P.Functions) do if fn.Level == fnLevel then chosen = fn end end
	if not chosen then return nil end
	local gold = env.Player:GetAttribute("Gold") or 0
	local owned = env.Player:GetAttribute("TimeSkip") or 0
	local upEnd = env.Player:GetAttribute("UpPet")
	local button
	if not pet or not pet.Unlocked then
		button = { Text = string.format("🐾 Unlock Pet\n💰 %s G", comma(P.UnlockCost)), Color = gold >= P.UnlockCost and env.GREEN or Color3.fromRGB(95, 60, 62), OnClick = function() env.Remotes.Meta:FireServer("PetUnlock") end }
	elseif pet.Level < P.MaxLevel then
		if upEnd then
			button = { Text = string.format("⏱ Time Skip\n%s left", Config.FormatDuration(math.max(0, upEnd - workspace:GetServerTimeNow()))), Color = owned > 0 and Color3.fromRGB(200, 130, 40) or env.GRAY, OnClick = function() env.Remotes.Growth:FireServer("Skip", "Pet", "Pet") end }
		else
			local cost = Config.GetPetLevelCost(pet.Level)
			button = { Text = string.format("⬆ Level Up %s G\n⏱ %s", comma(cost), Config.FormatDuration(Config.GetPetLevelTime(pet.Level))), Color = gold >= cost and env.GREEN or Color3.fromRGB(95, 60, 62), OnClick = function() env.Remotes.Meta:FireServer("PetLevel") end }
		end
	end
	return PET_COLOR, string.format("<font size='14'><b>%s Lv.%d %s</b></font>  %s\n<font color='#bbbbcc'>%s</font>\n<font size='10' color='#9aa0b8'>🎨 Pet looks / colors: press P</font>",
		chosen.Icon, chosen.Level, chosen.Name, level >= chosen.Level and "<font color='#78ff8c'>✔ Unlocked</font>" or "<font color='#ff8a8a'>🔒 Locked</font>", chosen.Desc), button
end

-- env: { Config, Remotes, Player, Meta, Growth, Remaining(endAt), UpgradeRemaining(key), SkillDetail(key, level), TrainLocked, NewRow, MakeLabel, MakeButton, Create, GREEN, GRAY, Refresh }
------------------------------------------------------------
-- 특성 트리 (와우 방식): 다섯 줄, 줄마다 아이콘 타일. 위쪽 줄에 점수를 일정 이상 써야 아래 줄이 열린다
------------------------------------------------------------
local TALENT_COLOR = Color3.fromRGB(150, 200, 255)
local function talentState(env)
	local T = env.Config.Talents
	local talents = (env.Meta and env.Meta.Talents) or {}
	local spent = 0
	for _, key in ipairs(T.Order) do spent += talents[key] or 0 end
	local function nodeOpen(node) -- 같은 길 위쪽 줄에 점수를 충분히 썼나
		return env.Config.TalentPathSpent(talents, node.Path, node.Row) >= (T.RowNeed[node.Row] or 0)
	end
	local total = env.Config.TalentPoints(env.Player:GetAttribute("Level") or 1)
	return talents, spent, total, nodeOpen
end

-- 세 갈래 길: 길마다 세로 한 줄기 (위 -> 아래), 맨 아래가 그 길의 최종 특성
local function drawTalents(env, C)
	local Config = env.Config
	local T = Config.Talents
	if not T then return end
	local talents, spent, total, nodeOpen = talentState(env)
	C.title("Passive", string.format("✨ Talents<font size='11' color='#cfc8e8'>   %d point(s) left</font>", math.max(0, total - spent)))
	local create, label = env.Create, env.MakeLabel
	local GOLDLINE = Color3.fromRGB(255, 205, 110)
	local OFF = Color3.fromRGB(56, 52, 78)
	local function rowY(row) return 66 + (row - 1) * 52 end
	local function pathX(path) return colX("Passive", 0.18 + (path - 1) * 0.32) end
	-- 원형 소켓 (금속 테두리) + 랭크 배지
	local function socket(x, y, size, icon, rank, max, open, lit, chosen, tint, onClick)
		local back = create("Frame", { Size = UDim2.new(0, size, 0, size), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(x, 0, 0, y),
			BackgroundColor3 = not open and Color3.fromRGB(30, 28, 44) or (lit and tint:Lerp(DARK, 0.45) or Color3.fromRGB(40, 42, 66)), BorderSizePixel = 0, ZIndex = 5 }, C.Row)
		create("UICorner", { CornerRadius = UDim.new(1, 0) }, back)
		create("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(100, 92, 130)), Rotation = 45 }, back)
		local ring = create("UIStroke", { Thickness = chosen and 2.6 or 1.6, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = chosen and Color3.new(1, 1, 1) or (not open and DIM or (rank >= max and Color3.fromRGB(255, 214, 110) or (lit and tint or Color3.fromRGB(120, 116, 150)))) }, back)
		if open and lit then create("UIGradient", { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 250, 225)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(170, 130, 60)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 235, 170)) }), Rotation = 45 }, ring) end
		label({ Size = UDim2.new(1, 0, 1, 0), Text = open and icon or "🔒", TextSize = open and math.floor(size * 0.4) or 10, ZIndex = 6, TextTransparency = (open and not lit) and 0.4 or 0 }, back)
		if max > 1 then -- 랭크 배지 (와우처럼 오른쪽 아래 "3/5")
			local badge = label({ Size = UDim2.new(0, 22, 0, 12), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, 1, 1, -1), Text = string.format("%d/%d", rank, max), TextSize = 8, Font = Enum.Font.GothamBold, ZIndex = 9,
				BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(14, 12, 24), TextColor3 = rank >= max and Color3.fromRGB(255, 214, 110) or (rank > 0 and Color3.fromRGB(150, 255, 170) or Color3.fromRGB(170, 166, 195)) }, back)
			create("UICorner", { CornerRadius = UDim.new(1, 0) }, badge)
		end
		local hit = create("TextButton", { Size = UDim2.new(1, 8, 1, 8), Position = UDim2.new(0, -4, 0, -4), BackgroundTransparency = 1, Text = "", ZIndex = 8 }, back)
		hit.Activated:Connect(onClick)
	end
	-- 길 머리: 아이콘 + 이름 + 그 길에 쓴 점수
	for path, info in ipairs(T.Paths) do
		local used = Config.TalentPathSpent(talents, path, 99)
		label({ Size = UDim2.new(0, 80, 0, 14), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(pathX(path), 0, 0, 38),
			Text = string.format("%s %s <font color='#ffffff'>%d</font>", info.Icon, info.Name, used), RichText = true, TextSize = 10, Font = Enum.Font.GothamBold, ZIndex = 6,
			TextColor3 = used > 0 and info.Color or Color3.fromRGB(150, 146, 175) }, C.Row)
	end
	for _, key in ipairs(T.Order) do
		local node = T[key]
		local info = T.Paths[node.Path]
		local x, y = pathX(node.Path), rowY(node.Row)
		local open = nodeOpen(node)
		local rank = talents[key] or 0
		local onClick = pick(env, "Talent", key)
		if node.Row > 1 then -- 위 칸에서 내려오는 줄기 (열렸으면 금빛)
			C.line(x, rowY(node.Row - 1) + 17, x, y - (node.Choice and 12 or 17), open and GOLDLINE or OFF, open and 2 or 1)
		end
		if node.Choice then -- 선택 칸: 줄기가 Y 자로 둘로 갈라진다 (둘 중 하나)
			local side = talents[key .. "_S"]
			local gap = 0.024
			C.line(x - gap, y - 12, x + gap, y - 12, open and GOLDLINE or OFF, 2)
			label({ Size = UDim2.new(0, 22, 0, 12), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(x, 0, 0, y + 6), Text = "or", TextSize = 9, Font = Enum.Font.GothamBold, ZIndex = 6, TextColor3 = Color3.fromRGB(200, 190, 230) }, C.Row)
			for k, which in ipairs({ "A", "B" }) do
				local c = node.Choice[which]
				local cx = x + (k == 1 and -gap or gap)
				C.line(cx, y - 12, cx, y - 6, open and GOLDLINE or OFF, 2)
				socket(cx, y + 6, 26, c.Icon, side == which and 1 or 0, 1, open, side == which, isSel("Talent", key) and (side == nil or side == which), info.Color, onClick)
			end
		else
			socket(x, y, node.Row == #T.RowNeed and 36 or 32, node.Icon, rank, node.Max, open, rank > 0, isSel("Talent", key), info.Color, onClick)
		end
	end
end

local function talentDetail(env, key)
	local Config = env.Config
	local T = Config.Talents
	local node = T and T[key]
	if not node then return nil end
	local talents, spent, total, nodeOpen = talentState(env)
	local rank = talents[key] or 0
	local info = T.Paths[node.Path]
	local left = math.max(0, total - spent)
	local lines = { string.format("<font size='14'><b>%s %s</b></font>  <font color='#ffd966'>%d / %d</font>  <font color='#9ad7ff'>· %d point(s) left (1 every %d levels)</font>", node.Icon, node.Name, rank, node.Max, left, T.PointsPerLevels) }
	if node.Choice then
		for _, side in ipairs({ "A", "B" }) do
			local c = node.Choice[side]
			local mine = talents[key .. "_S"] == side
			table.insert(lines, string.format("%s %s <b>%s</b> — <font color='#c8cce0'>%s</font>", mine and "<font color='#78ff8c'>✔</font>" or "◇", c.Icon, c.Name, c.Desc))
		end
		table.insert(lines, "<font color='#9aa0b8'>Pick one of the two</font>")
	else
		table.insert(lines, "<font color='#c8cce0'>" .. node.Desc .. "</font>")
	end
	table.insert(lines, string.format("<font color='#9aa0b8'>%s %s</font> <font color='#9aa0b8'>· %d point(s) in this path</font>", info.Icon, info.Name, Config.TalentPathSpent(talents, node.Path, 99)))
	if not nodeOpen(node) then table.insert(lines, string.format("<font color='#ff9a8a'>🔒 Spend %d points higher up this path first</font>", T.RowNeed[node.Row])) end
	local can = nodeOpen(node) and left > 0 and rank < node.Max
	local buttons = {}
	local function spendButton(text, arg)
		table.insert(buttons, { Text = text, Color = can and env.GREEN or env.GRAY, OnClick = function() if can then env.Remotes.Meta:FireServer("Talent", arg) end end })
	end
	if node.Choice then
		if rank == 0 then
			spendButton(node.Choice.A.Icon .. " " .. node.Choice.A.Name, key .. "|A")
			spendButton(node.Choice.B.Icon .. " " .. node.Choice.B.Name, key .. "|B")
		end
	elseif rank < node.Max then
		spendButton("⬆ Spend 1 point", key)
	end
	if spent > 0 then
		local cost = Config.TalentResetCost(env.Player:GetAttribute("Level") or 1)
		table.insert(buttons, { Text = env.InTown == false and "🏘 Reset in town" or string.format("🔁 Reset all\n%s G", comma(cost)), Color = Color3.fromRGB(120, 80, 60),
			OnClick = function() if env.InTown ~= false then env.Remotes.Meta:FireServer("TalentReset") end end })
	end
	return TALENT_COLOR, table.concat(lines, "\n"), buttons
end

function M.BuildAll(env)
	if not selected.Key then selected.Kind, selected.Key = "Skill", env.Config.Skills.UpgradeOrder[1] end
	local okC, C = pcall(canvas, env)
	if not okC then warn("[TrainingTree] " .. tostring(C)) return end
	C.divider(COLS.Skill[2])
	C.divider(COLS.Train[2])
	C.divider(COLS.Passive[2])
	for _, part in ipairs({ drawSkills, drawTraining, drawTalents, drawPet }) do
		local ok, err = pcall(part, env, C)
		if not ok then warn("[TrainingTree] " .. tostring(err)) end
	end
	local detailFn = selected.Kind == "Train" and trainDetail or (selected.Kind == "Pet" and petDetail or (selected.Kind == "Talent" and talentDetail or skillDetail))
	local ok, color, text, button = pcall(detailFn, env, selected.Key)
	if not ok then
		warn("[TrainingTree] " .. tostring(color))
	elseif color then
		detailRow(env, color, text, button, selected.Kind == "Skill" and selected.Key or nil, selected.Kind == "Talent")
	end
end

return M
