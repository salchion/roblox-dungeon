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
local NODE = 48
local TIER_Y = { 84, 184, 284 } -- 세 칸이 같은 높이의 층을 쓴다
local CANVAS_H = 352
local COLS = { Skill = { 0, 0.25 }, Train = { 0.25, 0.66 }, Pet = { 0.66, 1 } } -- 칸마다 가로 범위 (0~1)
local selected = { Kind = "Skill", Key = nil } -- 마지막으로 고른 노드 (메뉴를 다시 그려도 유지)

local TRAIN_COLORS = {
	Attack = Color3.fromRGB(255, 120, 80), Health = Color3.fromRGB(255, 90, 130), Crit = Color3.fromRGB(255, 210, 80), Speed = Color3.fromRGB(90, 210, 255),
	Double = Color3.fromRGB(255, 160, 90), Gold = Color3.fromRGB(255, 215, 90), CritDmg = Color3.fromRGB(255, 120, 60), AtkSpeed = Color3.fromRGB(140, 220, 255),
}
-- 훈련 노드 자리: { 칸 안의 x(0~1), 층 }
local TRAIN_POS = {
	Attack = { 0.125, 1 }, Health = { 0.375, 1 }, Crit = { 0.625, 1 }, Speed = { 0.875, 1 },
	Double = { 0.125, 2 }, Gold = { 0.375, 2 }, CritDmg = { 0.625, 2 }, AtkSpeed = { 0.375, 3 },
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
	function C.title(col, text)
		local range = COLS[col]
		label({ Size = UDim2.new(range[2] - range[1], -8, 0, 22), Position = UDim2.new(range[1], 4, 0, 8), Text = text, RichText = true, TextSize = 14, Font = Enum.Font.GothamBlack, TextColor3 = GOLD, ZIndex = 5 }, row)
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
	-- 노드: state = "done" (다 찍음) / "active" (찍는 중) / "open" (찍을 수 있음) / "locked"
	function C.node(x, y, icon, color, state, ratio, caption, sub, chosen, captionWidth, onClick)
		local fill = state == "locked" and Color3.fromRGB(32, 30, 48) or color:Lerp(DARK, state == "done" and 0.25 or 0.65)
		local n = create("Frame", { Size = UDim2.new(0, NODE, 0, NODE), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(x, 0, 0, y), BackgroundColor3 = fill, BorderSizePixel = 0, ZIndex = 4 }, row)
		create("UICorner", { CornerRadius = UDim.new(1, 0) }, n)
		create("UIStroke", { Color = chosen and Color3.new(1, 1, 1) or (state == "locked" and DIM or color), Thickness = chosen and 4 or (state == "done" and 3 or 2) }, n)
		label({ Size = UDim2.new(1, 0, 1, 0), Text = state == "locked" and "🔒" or icon, TextSize = state == "locked" and 18 or 23, ZIndex = 5, TextTransparency = state == "locked" and 0.2 or 0 }, n)
		local bar = create("Frame", { Size = UDim2.new(0, NODE + 8, 0, 4), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(x, 0, 0, y + NODE / 2 + 3), BackgroundColor3 = Color3.fromRGB(14, 12, 24), BorderSizePixel = 0, ZIndex = 4 }, row)
		create("UICorner", { CornerRadius = UDim.new(1, 0) }, bar)
		local barFill = create("Frame", { Size = UDim2.new(math.clamp(ratio or 0, 0, 1), 0, 1, 0), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 5 }, bar)
		create("UICorner", { CornerRadius = UDim.new(1, 0) }, barFill)
		label({ Size = UDim2.new(0, captionWidth, 0, 14), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(x, 0, 0, y + NODE / 2 + 9), Text = caption, RichText = true, TextSize = 10, TextScaled = false, TextTruncate = Enum.TextTruncate.AtEnd, Font = Enum.Font.GothamBold, ZIndex = 5, TextColor3 = state == "locked" and Color3.fromRGB(140, 136, 165) or Color3.new(1, 1, 1) }, row)
		if sub and sub ~= "" then
			label({ Size = UDim2.new(0, captionWidth, 0, 12), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(x, 0, 0, y + NODE / 2 + 23), Text = sub, RichText = true, TextSize = 9, ZIndex = 5, TextColor3 = state == "active" and Color3.fromRGB(255, 225, 120) or Color3.fromRGB(170, 166, 195) }, row)
		end
		if state == "active" then -- 찍는 중: 금빛 고리
			local ring = create("Frame", { Size = UDim2.new(0, NODE + 10, 0, NODE + 10), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(x, 0, 0, y), BackgroundTransparency = 1, ZIndex = 3 }, row)
			create("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
			create("UIStroke", { Color = Color3.fromRGB(255, 225, 120), Thickness = 2, Transparency = 0.2 }, ring)
		end
		local hit = create("TextButton", { Size = UDim2.new(0, math.max(NODE + 16, captionWidth), 0, NODE + 40), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(x, 0, 0, y - NODE / 2 - 4), BackgroundTransparency = 1, Text = "", ZIndex = 8 }, row)
		hit.Activated:Connect(onClick)
		return n
	end
	return C
end

-- 고른 노드의 설명 + 버튼 한 줄 (나무 바로 아래)
local function detailRow(env, color, text, button)
	local create, label = env.Create, env.MakeLabel
	local detail = env.NewRow(84, Color3.fromRGB(30, 28, 46))
	create("UIStroke", { Color = color, Thickness = 1.5, Transparency = 0.3 }, detail)
	label({ Size = UDim2.new(1, -210, 1, -12), Position = UDim2.new(0, 14, 0, 6), RichText = true, TextSize = 12, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center, Text = text }, detail)
	if button then
		env.MakeButton({ Size = UDim2.new(0, 180, 0, 44), Position = UDim2.new(1, -192, 0.5, -22), Text = button.Text, TextSize = 12, BackgroundColor3 = button.Color }, detail, button.OnClick)
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
	for i, key in ipairs(Config.Skills.UpgradeOrder) do
		local cfg = Config.Skills[key]
		local level = meta and meta.Skills and meta.Skills[key] or 1
		local remaining = env.UpgradeRemaining(key)
		local state = level >= U.MaxLevel and "done" or (remaining and "active" or "open")
		local x = colX("Skill", ((i - 1) % 2 == 0) and 0.28 or 0.72)
		local y = TIER_Y[math.floor((i - 1) / 2) + 1]
		C.node(x, y, cfg.Icon, skillColor(key), state, level / U.MaxLevel, string.format("[%s] <b>%s</b>", cfg.Key or "", cfg.Name),
			remaining and ("⏳ " .. Config.FormatDuration(remaining)) or string.format("Lv.%d / %d", level, U.MaxLevel), isSel("Skill", key), 104, pick(env, "Skill", key))
	end
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
		cfg.Key or "", cfg.Icon, cfg.Name, level, U.MaxLevel, maxed and "  <font color='#78ff8c'>MAX</font>" or "", cfg.Desc or "") .. (env.SkillDetail and ("\n<font color='#9ad7ff'>" .. env.SkillDetail(key, level) .. "</font>") or ""), button
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
	for _, stat in ipairs(G.Stats.Order) do -- 선 먼저 (노드 아래에 깔리게)
		local def, pos = G.Stats[stat], TRAIN_POS[stat]
		if pos then
			for _, req in ipairs(def.Req or {}) do
				local from = TRAIN_POS[req.Stat]
				if from then
					local met = (levels[req.Stat] or 0) >= req.Level
					C.elbow(colX("Train", from[1]), TIER_Y[from[2]] + NODE / 2 + 36, colX("Train", pos[1]), TIER_Y[pos[2]] - NODE / 2, met and (TRAIN_COLORS[stat] or GOLD) or DIM, met and 3 or 2)
				end
			end
		end
	end
	for _, stat in ipairs(G.Stats.Order) do
		local def, pos = G.Stats[stat], TRAIN_POS[stat]
		if pos then
			local level = levels[stat] or 0
			local max = Config.TrainMax(stat)
			local unlocked = Config.TrainUnlocked(stat, levels)
			local nodeState = not unlocked and "locked" or (jobs[stat] and "active" or (level >= max and "done" or "open"))
			local sub = jobs[stat] and ("⏳ " .. Config.FormatDuration(env.Remaining(jobs[stat].EndAt))) or string.format("Lv.%d / %d", level, max)
			C.node(colX("Train", pos[1]), TIER_Y[pos[2]], def.Icon, TRAIN_COLORS[stat] or GOLD, nodeState, level / max, def.Name, sub, isSel("Train", stat), 92, pick(env, "Train", stat))
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
		table.insert(lines, string.format("<font color='#bbbbcc'>Time needed %s · 💰 %s G</font>", Config.FormatDuration(Config.GetTrainTime(level)), comma(Config.GetTrainGold(level))))
		button = { Text = "Start Training", Color = env.GREEN, OnClick = function() env.Remotes.Growth:FireServer("Train", stat) end }
	end
	return TRAIN_COLORS[stat] or GOLD, table.concat(lines, "\n"), button
end

------------------------------------------------------------
-- 3) 펫 사슬 (오른쪽 칸, 한 줄에 4개씩 뱀처럼)
------------------------------------------------------------
local PET_PER_ROW = 4
local function petPos(i)
	local r = (i - 1) // PET_PER_ROW
	local c = (i - 1) % PET_PER_ROW
	if r % 2 == 1 then c = PET_PER_ROW - 1 - c end
	return colX("Pet", (c + 0.5) / PET_PER_ROW), TIER_Y[math.min(r + 1, #TIER_Y)]
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
	for i = 2, #fns do
		local x0, y0 = petPos(i - 1)
		local x1, y1 = petPos(i)
		local lit = level >= fns[i].Level
		C.line(x0, y0, y0 == y1 and x1 or x0, y1, lit and PET_COLOR or DIM, lit and 3 or 2)
	end
	local upEnd = env.Player:GetAttribute("UpPet")
	for i, fn in ipairs(fns) do
		local x, y = petPos(i)
		local open = level >= fn.Level
		local nodeState = open and "done" or (nextFn == fn and (upEnd and "active" or "open") or "locked")
		C.node(x, y, fn.Icon, PET_COLOR, nodeState, open and 1 or 0, string.format("Lv.%d", fn.Level), fn.Name, isSel("Pet", fn.Level), 74, pick(env, "Pet", fn.Level))
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
function M.BuildAll(env)
	if not selected.Key then selected.Kind, selected.Key = "Skill", env.Config.Skills.UpgradeOrder[1] end
	local okC, C = pcall(canvas, env)
	if not okC then warn("[TrainingTree] " .. tostring(C)) return end
	C.divider(COLS.Skill[2])
	C.divider(COLS.Train[2])
	for _, part in ipairs({ drawSkills, drawTraining, drawPet }) do
		local ok, err = pcall(part, env, C)
		if not ok then warn("[TrainingTree] " .. tostring(err)) end
	end
	local detailFn = selected.Kind == "Train" and trainDetail or (selected.Kind == "Pet" and petDetail or skillDetail)
	local ok, color, text, button = pcall(detailFn, env, selected.Key)
	if not ok then
		warn("[TrainingTree] " .. tostring(color))
	elseif color then
		detailRow(env, color, text, button)
	end
end

return M
