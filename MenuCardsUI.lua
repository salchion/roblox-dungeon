-- MenuCardsUI (StarterPlayer > StarterPlayerScripts 안의 ModuleScript, 이름: MenuCardsUI)
-- 메뉴(B) > 퀘스트 / 업적 / 랭킹 탭을 "게임 카드" 모양으로 그린다 (예전: 글자 줄 + 회색 버튼 = 엑셀 표 느낌).
--   퀘스트 한 줄 = 퀘스트 색 알약 띠 + 메달 아이콘 + 진행 막대 + 보상 칩 + 둥근 받기 버튼 (받은 것은 "완료" 도장)
--   랭킹 = 1~3등 시상대(메달 + 높이가 다른 받침) + 4등부터 알약 줄 (내 줄은 금색)
-- PlayerClient 가 Studio 스크립트 한도(200KB)에 가까워서 따로 뺐다. 필요한 것은 Init(env) 로 넘겨 받는다.
--   env: player, newRow(높이) , GREEN, sectionTitle(글자)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Kit = require(ReplicatedStorage:WaitForChild("ClientKit"))

local create, makeLabel = Kit.create, Kit.makeLabel
local MenuCards = {}

-- 퀘스트 / 업적 종류(Stat)마다 아이콘과 색 (없는 것은 기본)
local STAT_LOOK = {
	DummyHits = { "🎯", Color3.fromRGB(255, 170, 90) },
	Kills = { "⚔", Color3.fromRGB(255, 120, 90) },
	FieldKills = { "⚔", Color3.fromRGB(255, 140, 90) },
	EliteKills = { "👑", Color3.fromRGB(90, 200, 255) },
	BossKills = { "💀", Color3.fromRGB(235, 90, 110) },
	GoblinKills = { "💰", Color3.fromRGB(255, 205, 80) },
	DungeonClears = { "🏯", Color3.fromRGB(160, 130, 255) },
	DungeonWaves = { "🌊", Color3.fromRGB(120, 150, 255) },
	FeverRuns = { "🔥", Color3.fromRGB(255, 110, 80) },
	Enhances = { "🔨", Color3.fromRGB(230, 170, 90) },
	WeaponLevel = { "🗡", Color3.fromRGB(230, 170, 90) },
	Rolls = { "🎲", Color3.fromRGB(200, 130, 255) },
	BestRarity = { "💎", Color3.fromRGB(200, 130, 255) },
	SkillUses = { "✨", Color3.fromRGB(120, 210, 255) },
	RiftRuns = { "🌀", Color3.fromRGB(150, 110, 255) },
	RiftBoss = { "🌀", Color3.fromRGB(150, 110, 255) },
	RiftTime = { "⏱", Color3.fromRGB(150, 110, 255) },
	Level = { "⭐", Color3.fromRGB(255, 215, 100) },
	Power = { "⚡", Color3.fromRGB(255, 215, 100) },
	MaxZone = { "🗺", Color3.fromRGB(110, 220, 150) },
	FieldDeaths = { "🪦", Color3.fromRGB(170, 170, 200) },
	Trains = { "🏋", Color3.fromRGB(110, 220, 150) },
	StatPoints = { "📊", Color3.fromRGB(110, 220, 150) },
	PetPeek = { "🐾", Color3.fromRGB(255, 160, 200) },
}
local DEFAULT_LOOK = { "📜", Color3.fromRGB(150, 160, 210) }

local statById = {}
for _, q in ipairs(Config.Quests.Pool) do statById[q.Id] = q.Stat end
for _, a in ipairs(Config.Achievements) do statById[a.Id] = a.Stat end

local DARK = Color3.fromRGB(20, 18, 40)
local MINT = Color3.fromRGB(120, 255, 140)
local GOLD_TEXT = Color3.fromRGB(255, 217, 102)

local function corner(inst, r)
	create("UICorner", { CornerRadius = r and UDim.new(0, r) or UDim.new(1, 0) }, inst)
end

local function groupDigits(n)
	return (tostring(math.floor(n or 0)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

-- 둥근 알약 버튼 (부드러운 빛 테두리)
local function pillButton(parent, props, color, glow, onClick)
	local button = Kit.makeButton(props, parent, onClick)
	button.BackgroundColor3 = color
	local round = button:FindFirstChildOfClass("UICorner")
	if round then round.CornerRadius = UDim.new(1, 0) end
	create("UIStroke", { Color = DARK, Thickness = 2.4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, button)
	if glow then -- 받을 수 있는 것만 은은한 빛 (눈부시지 않게)
		local halo = create("Frame", { Size = UDim2.new(1, 10, 1, 10), Position = UDim2.new(0, -5, 0, -5), BackgroundColor3 = color, BackgroundTransparency = 0.78, BorderSizePixel = 0, ZIndex = math.max(1, button.ZIndex - 1), Active = false }, parent)
		corner(halo)
		halo.Position = UDim2.new(button.Position.X.Scale, button.Position.X.Offset - 5, button.Position.Y.Scale, button.Position.Y.Offset - 5)
		halo.Size = UDim2.new(button.Size.X.Scale, button.Size.X.Offset + 10, button.Size.Y.Scale, button.Size.Y.Offset + 10)
		halo.AnchorPoint = button.AnchorPoint
	end
	return button
end

function MenuCards.Init(env)
	local player, newRow, GREEN, sectionTitle = env.player, env.newRow, env.GREEN, env.sectionTitle

	-- 투명한 줄 (안에 카드를 직접 그린다)
	local function bareRow(height)
		local row = newRow(height)
		row.BackgroundTransparency = 1
		for _, child in ipairs(row:GetChildren()) do
			if child:IsA("UIStroke") or child:IsA("UIGradient") then child:Destroy() end
		end
		return row
	end

	local function emptyLine(text)
		local row = bareRow(36)
		makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = text, TextColor3 = Color3.fromRGB(136, 136, 136), TextSize = 14 }, row)
	end

	local function questCard(entry, remoteAction, showTitle)
		local done = entry.Progress >= entry.Goal
		local claimable = done and not entry.Claimed
		local look = STAT_LOOK[statById[entry.Id] or ""] or DEFAULT_LOOK
		local color = look[2]
		local muted = entry.Claimed
		local row = bareRow(64)

		-- 퀘스트 색 알약 띠 (왼쪽이 진하고 오른쪽으로 사라진다)
		local strip = create("Frame", { Size = UDim2.new(1, -4, 0, 56), Position = UDim2.new(0, 2, 0, 4), BackgroundColor3 = color, BackgroundTransparency = muted and 0.88 or 0.78, BorderSizePixel = 0 }, row)
		corner(strip)
		create("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.75, 0.85), NumberSequenceKeypoint.new(1, 0.9) }) }, strip)
		create("UIStroke", { Color = color, Thickness = 1.5, Transparency = claimable and 0.25 or (muted and 0.8 or 0.6), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, strip)

		Kit.medal(row, { Size = 52, Position = UDim2.new(0, 6, 0, 6), Color = color, Icon = look[1], TextSize = 22, Muted = muted, ZIndex = 2 })

		local textTr = muted and 0.45 or 0
		local nameText = "<b>" .. entry.Name .. "</b>"
		if showTitle and entry.Title then
			nameText ..= string.format("  <font color='#9ad7ff' size='11'>Title 『%s』</font>", entry.Title)
		end
		makeLabel({ Size = UDim2.new(1, -250, 0, 18), Position = UDim2.new(0, 68, 0, 8), Text = nameText, RichText = true, TextSize = 14, Font = Enum.Font.GothamBlack,
			TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextTransparency = textTr, ZIndex = 3 }, row)
		makeLabel({ Size = UDim2.new(1, -160, 0, 15), Position = UDim2.new(0, 68, 0, 26), Text = entry.Desc, TextSize = 12, TextColor3 = Color3.fromRGB(184, 188, 214),
			TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextTransparency = textTr, ZIndex = 3 }, row)

		-- 진행 막대 + 숫자
		local ratio = math.clamp(entry.Progress / math.max(1, entry.Goal), 0, 1)
		local track = create("Frame", { Size = UDim2.new(1, -250, 0, 8), Position = UDim2.new(0, 68, 0, 45), BackgroundColor3 = Color3.fromRGB(42, 42, 62), BorderSizePixel = 0, ZIndex = 3 }, row)
		corner(track)
		if ratio > 0 then
			local fill = create("Frame", { Size = UDim2.new(ratio, 0, 1, 0), BackgroundColor3 = done and MINT or color, BackgroundTransparency = muted and 0.4 or 0, BorderSizePixel = 0, ZIndex = 4 }, track)
			corner(fill)
		end
		makeLabel({ Size = UDim2.new(0, 70, 0, 14), Position = UDim2.new(1, -176, 0, 42), Text = string.format("%s/%s", groupDigits(entry.Progress), groupDigits(entry.Goal)),
			TextSize = 12, Font = Enum.Font.GothamBold, TextColor3 = done and MINT or Color3.fromRGB(230, 232, 245), TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = false, TextTransparency = textTr, ZIndex = 3 }, row)

		-- 보상 칩 (오른쪽 위, 받기 버튼 바로 왼쪽)
		local chip = create("Frame", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 0, 20), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -86, 0, 8),
			BackgroundColor3 = Color3.fromRGB(90, 70, 40), BackgroundTransparency = muted and 0.6 or 0.3, BorderSizePixel = 0, ZIndex = 3 }, row)
		corner(chip)
		create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, chip)
		create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, chip)
		-- 보상은 "💰 300 + 🎫 1 + ⏱ 10 min" 처럼 오므로 조각마다 따로 (조각별로 번역된다)
		local parts = string.split(tostring(entry.Reward), " + ")
		for i, part in ipairs(parts) do
			local gold = string.match(part, "^(%d+) G$")
			if gold then parts[i] = "💰 " .. groupDigits(tonumber(gold)) end
		end
		table.insert(parts, 1, "🎁")
		for i, part in ipairs(parts) do
			makeLabel({ AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), Text = part, TextSize = 12, Font = Enum.Font.GothamBold, LayoutOrder = i,
				TextColor3 = GOLD_TEXT, TextWrapped = false, TextTransparency = textTr, ZIndex = 4 }, chip)
		end

		-- 오른쪽: 받기 버튼 / 진행 중 % / 완료 도장
		if claimable then
			pillButton(row, { Size = UDim2.new(0, 70, 0, 40), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Text = "Claim",
				TextSize = 15, Font = Enum.Font.GothamBlack, ZIndex = 3 }, GREEN, true, function()
				Remotes.Quest:FireServer(remoteAction, entry.Id)
			end)
		elseif entry.Claimed then
			local stamp = create("Frame", { Size = UDim2.new(0, 70, 0, 34), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), BackgroundTransparency = 1, Rotation = -8, ZIndex = 3 }, row)
			corner(stamp, 14)
			create("UIStroke", { Color = Color3.fromRGB(90, 200, 120), Thickness = 2.4, Transparency = 0.15, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, stamp)
			makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = "✔ Done", TextSize = 14, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(110, 220, 140), TextWrapped = false, ZIndex = 4 }, stamp)
		else
			makeLabel({ Size = UDim2.new(0, 78, 0, 16), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 18), Text = "In progress", TextSize = 12, Font = Enum.Font.GothamBold,
				TextColor3 = Color3.fromRGB(150, 154, 180), TextWrapped = false, ZIndex = 3 }, row)
			makeLabel({ Size = UDim2.new(0, 78, 0, 16), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 34), Text = string.format("%d%%", math.floor(ratio * 100)), TextSize = 13, Font = Enum.Font.GothamBlack,
				TextColor3 = color, TextWrapped = false, ZIndex = 3 }, row)
		end
	end

	local function buildProgressRows(entries, remoteAction, showTitle)
		if not entries then
			emptyLine("Loading...")
			return
		end
		-- 받을 수 있는 것 -> 진행 중 -> 받은 것 순서 (업적이 많아도 받을 것부터 보인다)
		local function rank(entry) return entry.Claimed and 3 or (entry.Progress >= entry.Goal and 1 or 2) end
		local sorted = table.clone(entries)
		local order = {}
		for i, entry in ipairs(sorted) do order[entry] = i end
		table.sort(sorted, function(a, b)
			if rank(a) ~= rank(b) then return rank(a) < rank(b) end
			return order[a] < order[b]
		end)
		local claimable = 0
		for _, entry in ipairs(sorted) do
			if not entry.Claimed and entry.Progress >= entry.Goal then claimable += 1 end
		end
		if claimable > 0 then
			local allRow = bareRow(50)
			pillButton(allRow, { Size = UDim2.new(0, 220, 0, 38), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
				Text = string.format("🎁 Claim All (%d)", claimable), TextSize = 15, Font = Enum.Font.GothamBlack, ZIndex = 2 }, GREEN, true, function()
				Remotes.Quest:FireServer("ClaimAll")
			end)
		end
		for _, entry in ipairs(sorted) do
			questCard(entry, remoteAction, showTitle)
		end
	end

	local PODIUM = {
		{ Color = Color3.fromRGB(255, 200, 80), Icon = "🥇", Bar = 76, X = 0.5, Medal = 56 },
		{ Color = Color3.fromRGB(190, 200, 225), Icon = "🥈", Bar = 54, X = 0.18, Medal = 50 },
		{ Color = Color3.fromRGB(215, 140, 90), Icon = "🥉", Bar = 42, X = 0.82, Medal = 50 },
	}

	local function buildRankTab(rankList)
		sectionTitle("🏆 Power Ranking TOP 10 (same as the small ranking on the right of the screen)")
		if #rankList == 0 then
			emptyLine("Tallying...")
			return
		end
		local me = player.DisplayName
		-- 1~3등 시상대
		local stage = bareRow(196)
		for index = 1, math.min(3, #rankList) do
			local entry, look = rankList[index], PODIUM[index]
			local isMe = entry.Name == me
			local col = create("Frame", { Size = UDim2.new(0.3, 0, 1, 0), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(look.X, 0, 0, 0), BackgroundTransparency = 1 }, stage)
			local bar = create("Frame", { Size = UDim2.new(0.86, 0, 0, look.Bar), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -2), BackgroundColor3 = look.Color, BorderSizePixel = 0 }, col)
			corner(bar, 8)
			create("UIGradient", { Rotation = 90, Color = ColorSequence.new(look.Color:Lerp(DARK, 0.35), look.Color:Lerp(DARK, 0.8)) }, bar)
			create("UIStroke", { Color = isMe and GOLD_TEXT or look.Color, Thickness = isMe and 2.4 or 1.6, Transparency = isMe and 0 or 0.3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, bar)
			makeLabel({ Size = UDim2.new(1, 0, 0, 30), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6), Text = tostring(index), TextSize = 24, Font = Enum.Font.GothamBlack,
				TextColor3 = look.Color, TextTransparency = 0.35, TextWrapped = false }, bar)
			local top = 196 - 2 - look.Bar
			makeLabel({ Size = UDim2.new(1, 8, 0, 16), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, top - 4), Text = "⚡ " .. groupDigits(entry.Power), TextSize = 13, Font = Enum.Font.GothamBold,
				TextColor3 = GOLD_TEXT, TextWrapped = false }, col)
			makeLabel({ Size = UDim2.new(1, 8, 0, 18), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, top - 20), Text = entry.Name, TextSize = 14, Font = Enum.Font.GothamBlack,
				TextColor3 = isMe and GOLD_TEXT or Color3.fromRGB(240, 242, 250), TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd }, col)
			Kit.medal(col, { Size = look.Medal, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, top - 40), Color = look.Color, Icon = look.Icon, TextSize = math.floor(look.Medal * 0.46), Tier = index == 1 and 4 or 3 })
		end
		-- 4등부터 알약 줄
		for index = 4, #rankList do
			local entry = rankList[index]
			local isMe = entry.Name == me
			local row = bareRow(32)
			local pill = create("Frame", { Size = UDim2.new(1, -4, 1, -2), Position = UDim2.new(0, 2, 0, 1), BackgroundColor3 = isMe and Color3.fromRGB(110, 90, 36) or Color3.fromRGB(34, 34, 52), BackgroundTransparency = isMe and 0.2 or 0.15, BorderSizePixel = 0 }, row)
			corner(pill)
			if isMe then
				create("UIStroke", { Color = GOLD_TEXT, Thickness = 1.6, Transparency = 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, pill)
			end
			makeLabel({ Size = UDim2.new(0, 36, 1, 0), Position = UDim2.new(0, 6, 0, 0), Text = tostring(index), TextSize = 14, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(150, 154, 180), TextWrapped = false }, pill)
			makeLabel({ Size = UDim2.new(1, -170, 1, 0), Position = UDim2.new(0, 46, 0, 0), Text = entry.Name, TextSize = 14, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = isMe and GOLD_TEXT or Color3.fromRGB(240, 242, 250), TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd }, pill)
			makeLabel({ Size = UDim2.new(0, 120, 1, 0), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 0), Text = "⚡ " .. groupDigits(entry.Power), TextSize = 14, Font = Enum.Font.GothamBold,
				TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = GOLD_TEXT, TextWrapped = false }, pill)
		end
	end

	return { Progress = buildProgressRows, Rank = buildRankTab }
end

return MenuCards
