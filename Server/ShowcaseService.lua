-- ShowcaseService (ServerScriptService > Modules 안의 ModuleScript, 이름: ShowcaseService)
-- 로비 "명예의 전당": 모든 서버를 합친 전투력 TOP 3 를 북쪽 성벽 전시대에 세워 보여준다 (접속해 있지 않은 사람도 선다).
--   아바타 모형 + 그 사람의 무기 모양(진화 단계) + 이름 / 전투력 / 무기 이름
--   -> 남의 강한 장비가 눈에 띄어야 "나도 저렇게 되고 싶다"가 생긴다.
--   저장: DataStore "HallOfFame_v1" 의 한 키(Top)에 { List = 상위 3명 정보, Banned = 지운 유저 } 를 둔다.
--         서버마다 60초에 한 번, 내 서버 유저가 3위 안에 들 만하면 UpdateAsync 로 합치고 아니면 읽기만 한다 (쓰기 부하가 작다).
--         DataStore 를 못 쓰면(Studio API 꺼짐) 지금 서버의 유저끼리로 대신한다.
--   동쪽 성벽에는 "이번 주 챔피언"(보스 러쉬 주간 1~3위) 전시대가 있다. 주간 순위는 RiftService 에서 읽는다.
--   칭호(TitleService)가 읽을 수 있게 HallRank / WeeklyRank 를 알려 준다. 운영자는 RemoveHall 로 이상한 기록을 지운다.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Showcase = {}

local slots = {}   -- [1..3] = { Pedestal, Label, Key, Model, Weapon }
local champSlots = {} -- 이번 주 챔피언 [1..3]
local folder
local buildChampStages -- 아래에서 만든다

local okHall, hallStore = pcall(function() return DataStoreService:GetDataStore("HallOfFame_v1") end)
if not okHall then hallStore = nil end
local HALL_KEY = "Top"
local HALL_EVERY = 60 -- 초: 저장소를 읽거나 쓰는 간격
local hallCache = nil -- { List = {...}, Banned = {...} }
local hallAt = -1e9
local hallRanks = {}   -- [userId] = 1..3 (전 서버 명예의 전당)
local weeklyRanks = {} -- [userId] = 1..3 (보스 러쉬 주간)

function Showcase.HallRank(userId) return hallRanks[userId] end
function Showcase.WeeklyRank(userId) return weeklyRanks[userId] end

local MEDAL = { "🥇", "🥈", "🥉" }
local MEDAL_COLORS = { Color3.fromRGB(255, 215, 60), Color3.fromRGB(205, 210, 220), Color3.fromRGB(205, 140, 80) }

local function makeLabel(parent, offsetY, maxDistance, width, height)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.Position = parent.Position + Vector3.new(0, offsetY, 0)
	part.Parent = folder
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, width or 260, 0, height or 84)
	gui.AlwaysOnTop = false
	gui.MaxDistance = maxDistance or 40
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.RichText = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	return label
end

-- 북쪽 성벽의 "명예의 전당": 던전 게이트들 바로 위, 성벽 안쪽 면에 순위별 벽감(받침대 + 뒷판)이 튀어나와 있고
-- 랭커 아바타가 광장 쪽을 보고 크게 서 있다. 게이트로 걸어가다 보면 자연스럽게 눈에 들어온다.
-- 이름 / 전투력 / 무기가 머리 위에 보인다. (성벽 높이는 LobbyService 에서 북쪽만 높게 만든다)
local WALL_FACE_Z = -127 -- 북쪽 성벽 안쪽 면

function Showcase.Init(_boardCFrame)
	folder = Instance.new("Folder")
	folder.Name = "Showcase"
	folder.Parent = workspace:FindFirstChild("Lobby") or workspace

	local look = Vector3.new(0, 0, 1) -- 광장(남쪽)을 바라본다
	-- 가운데가 1등(가장 높음), 좌우가 2등(왼쪽) / 3등(오른쪽)
	local spots = {
		Vector3.new(0, 52, WALL_FACE_Z + 5), -- 게이트 위 장식(높이 약 40)과 겹치지 않게 높이 올렸다 (뒷판 아래 끝이 49 / 43)
		Vector3.new(-42, 46, WALL_FACE_Z + 5),
		Vector3.new(42, 46, WALL_FACE_Z + 5),
	}
	for rank = 1, 3 do
		local spot = spots[rank]
		local color = MEDAL_COLORS[rank]

		-- 벽에 붙은 뒷판 (어두운 판 + 순위 색 테두리)
		local backdrop = Instance.new("Part")
		backdrop.Name = "Backdrop" .. rank
		backdrop.Anchored = true
		backdrop.Size = Vector3.new(26, 30, 1)
		backdrop.Position = Vector3.new(spot.X, spot.Y + 12, WALL_FACE_Z + 0.5)
		backdrop.Color = Color3.fromRGB(26, 24, 40)
		backdrop.Material = Enum.Material.Slate
		backdrop.Parent = folder
		for _, edge in ipairs({
			{ Vector3.new(26.6, 0.8, 1.4), Vector3.new(0, 15, 0) },
			{ Vector3.new(26.6, 0.8, 1.4), Vector3.new(0, -15, 0) },
			{ Vector3.new(0.8, 30, 1.4), Vector3.new(-13, 0, 0) },
			{ Vector3.new(0.8, 30, 1.4), Vector3.new(13, 0, 0) },
		}) do
			local trim = Instance.new("Part")
			trim.Anchored = true
			trim.CanCollide = false
			trim.Size = edge[1]
			trim.Position = backdrop.Position + edge[2]
			trim.Color = color
			trim.Material = Enum.Material.Neon
			trim.Parent = folder
		end

		-- 장식: 양옆 돌기둥(순위 색 머리) + 위쪽 박공 + 아래로 늘어진 깃발 -> 신전 벽감 느낌
		for _, side in ipairs({ -1, 1 }) do
			local pillar = Instance.new("Part")
			pillar.Anchored = true
			pillar.CanCollide = false
			pillar.Size = Vector3.new(2.2, 32, 2.2)
			pillar.Position = backdrop.Position + Vector3.new(side * 14.6, 0, 1.2)
			pillar.Color = Color3.fromRGB(78, 74, 92)
			pillar.Material = Enum.Material.Granite
			pillar.Parent = folder
			local cap = Instance.new("Part")
			cap.Anchored = true
			cap.CanCollide = false
			cap.Size = Vector3.new(3.2, 1.2, 3.2)
			cap.Position = pillar.Position + Vector3.new(0, 16.6, 0)
			cap.Color = color
			cap.Material = Enum.Material.Metal
			cap.Parent = folder
			local banner = Instance.new("Part")
			banner.Anchored = true
			banner.CanCollide = false
			banner.Size = Vector3.new(3, 10, 0.3)
			banner.Position = pillar.Position + Vector3.new(side * 0.2, -9, 1.6)
			banner.Color = color:Lerp(Color3.fromRGB(40, 20, 50), 0.55)
			banner.Material = Enum.Material.Fabric
			banner.Parent = folder
		end
		local cornice = Instance.new("Part") -- 뒷판 위쪽 돌 처마 (순위 색 줄 포함)
		cornice.Anchored = true
		cornice.CanCollide = false
		cornice.Size = Vector3.new(31, 1.6, 2.4)
		cornice.Position = backdrop.Position + Vector3.new(0, 16.4, 0.5)
		cornice.Color = Color3.fromRGB(78, 74, 92)
		cornice.Material = Enum.Material.Granite
		cornice.Parent = folder

		-- 아바타가 서는 받침대 (벽에서 튀어나온 돌 선반)
		local platform = Instance.new("Part")
		platform.Name = "Ledge" .. rank
		platform.Anchored = true
		platform.Size = Vector3.new(18, 2, 10)
		platform.Position = Vector3.new(spot.X, spot.Y - 1, WALL_FACE_Z + 5)
		platform.Color = Color3.fromRGB(70, 66, 84)
		platform.Material = Enum.Material.Granite
		platform.Parent = folder
		local lip = Instance.new("Part")
		lip.Anchored = true
		lip.CanCollide = false
		lip.Size = Vector3.new(18.4, 0.4, 0.5)
		lip.Position = platform.Position + Vector3.new(0, 0.9, 5)
		lip.Color = color
		lip.Material = Enum.Material.Neon
		lip.Parent = folder
		-- 스포트라이트: 받침대 위로 쏟아지는 은은한 빛기둥 + 반짝이는 금가루 ("저 자리에 서고 싶다")
		local beam = Instance.new("Part")
		beam.Name = "Spotlight" .. rank
		beam.Anchored = true
		beam.CanCollide = false
		beam.CanQuery = false
		beam.CanTouch = false
		beam.CastShadow = false
		beam.Material = Enum.Material.Neon
		beam.Color = color
		beam.Transparency = 0.9
		beam.Size = Vector3.new(15, 36, 9)
		beam.Position = platform.Position + Vector3.new(0, 18 + 1, 0)
		beam.Parent = folder
		local halo = Instance.new("Part") -- 받침대 바닥 후광 (납작한 원판)
		halo.Anchored = true
		halo.CanCollide = false
		halo.CanQuery = false
		halo.CastShadow = false
		halo.Shape = Enum.PartType.Cylinder
		halo.Material = Enum.Material.Neon
		halo.Color = color
		halo.Transparency = 0.55
		halo.Size = Vector3.new(0.2, 15, 15)
		halo.CFrame = CFrame.new(platform.Position + Vector3.new(0, 1.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
		halo.Parent = folder
		local dust = Instance.new("ParticleEmitter")
		dust.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		dust.Rate = rank == 1 and 14 or 8
		dust.Lifetime = NumberRange.new(2.5, 4)
		dust.Speed = NumberRange.new(1.5, 3.5)
		dust.EmissionDirection = Enum.NormalId.Top
		dust.SpreadAngle = Vector2.new(25, 25)
		dust.LightEmission = 0.8
		dust.Color = ColorSequence.new(color)
		dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
		dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
		dust.Parent = halo
		local glow = Instance.new("PointLight")
		glow.Range = 45
		glow.Brightness = 2
		glow.Color = color
		glow.Parent = backdrop

		slots[rank] = {
			Platform = platform, Top = spot, Scale = 2.8, Look = look, Key = nil, Model = nil, Weapon = nil,
			Label = makeLabel(platform, 27, 150, 230, 100), -- 이름이 멀리서도 보이게 (75 -> 150 스터드, 라벨 약간 크게). 세 라벨이 멀리서 서로 겹치지 않을 정도로만 키웠다
		}
		slots[rank].Label.Text = MEDAL[rank] .. " Who will take this spot?\n<font size='14'>Raise your power to claim it!</font>"
	end

	local header = makeLabel(slots[1].Platform, 34, 300, 320, 96) -- 1등 뒷판 위의 큰 머리글
	header.Text = "🏆 Hall of Fame 🏆"
	header.TextColor3 = Color3.fromRGB(255, 226, 120)

	if buildChampStages then buildChampStages() end

	task.spawn(function()
		task.wait(8)
		while true do
			Showcase.Refresh()
			task.wait(20)
		end
	end)
end

local function clearSlot(slot)
	if slot.Model then
		slot.Model:Destroy()
		slot.Model = nil
	end
	if slot.Weapon then
		slot.Weapon:Destroy()
		slot.Weapon = nil
	end
	slot.Key = nil
end

-- 아바타 모형 (유저 번호로 불러온다: 접속하지 않은 사람도 된다. 실패하면 무기 / 글자만 보여준다)
local function spawnAvatar(slot, userId, expectedKey)
	task.spawn(function()
		local ok, model = pcall(function()
			return Players:CreateHumanoidModelFromUserId(userId)
		end)
		if not ok or not model or slot.Key ~= expectedKey then
			if model then model:Destroy() end
			return
		end
		for _, descendant in ipairs(model:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
			end
		end
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
		model.Name = "ShowcaseAvatar"
		model.Parent = folder
		model:ScaleTo(slot.Scale)
		local standAt = slot.Top + Vector3.new(0, 3.2 * slot.Scale, 0) + slot.Look * 1
		model:PivotTo(CFrame.lookAt(standAt, standAt + slot.Look))
		slot.Model = model
	end)
end

-- entry: { UserId, Name, Power, Level, WT (무기 종류), WL (무기 단계) }
local function buildSlot(rank, entry)
	local slot = slots[rank]
	clearSlot(slot)
	local typeKey = entry.WT or "Pistol"
	local level = entry.WL or 0
	local power = entry.Power or 0
	slot.Key = string.format("%d_%d_%s_%d", entry.UserId, power // 25, typeKey, level)
	local key = slot.Key

	slot.Label.Text = string.format("%s %s\n<font color='#ffe16e'>⚡ %d</font> Lv.%d\n<font color='#9ad7ff'>%s</font>",
		MEDAL[rank], entry.Name or "?", power, entry.Level or 1, Config.FormatWeapon(level, typeKey))

	local top = slot.Top

	-- 무기 모형 (진화 단계 미리보기 모델 복제)
	local previews = ReplicatedStorage:FindFirstChild("WeaponPreviews")
	local source = previews and previews:FindFirstChild("W" .. Config.GetLookTier(level, Config.ResolveWeaponType(level, typeKey)).Index)
	if source then
		local weapon = source:Clone()
		weapon:ScaleTo(slot.Scale)
		local weaponSpot = top + Vector3.new(0, 9, 0) + Vector3.new(11, 0, 0) -- 아바타 옆에 크게 떠 있다
		weapon:PivotTo(CFrame.lookAt(weaponSpot, weaponSpot + slot.Look) * CFrame.Angles(0, math.rad(90), 0))
		for _, descendant in ipairs(weapon:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
			end
		end
		weapon.Parent = folder
		slot.Weapon = weapon
	end

	spawnAvatar(slot, entry.UserId, key)
end

local function emptyText(rank)
	return MEDAL[rank] .. " Who will take this spot?\n<font size='14'>Raise your power to claim it!</font>"
end

------------------------------------------------------------
-- 전 서버 명예의 전당 데이터
------------------------------------------------------------
local function snapshotOf(player)
	return {
		UserId = player.UserId, Name = player.DisplayName, Power = player:GetAttribute("Power") or 0,
		Level = player:GetAttribute("Level") or 1, WT = player:GetAttribute("WeaponType") or "Pistol", WL = player:GetAttribute("WeaponLevel") or 0,
	}
end

local function validEntry(e)
	return typeof(e) == "table" and typeof(e.UserId) == "number" and typeof(e.Power) == "number" and typeof(e.Name) == "string"
end

local function cleanData(value)
	local data = { List = {}, Banned = {} }
	if typeof(value) == "table" then
		if typeof(value.Banned) == "table" then
			for key, flag in pairs(value.Banned) do
				if flag == true then data.Banned[tostring(key)] = true end
			end
		end
		if typeof(value.List) == "table" then
			for _, e in ipairs(value.List) do
				if validEntry(e) and not data.Banned[tostring(e.UserId)] then
					table.insert(data.List, { UserId = e.UserId, Name = string.sub(e.Name, 1, 40), Power = e.Power, Level = tonumber(e.Level) or 1, WT = typeof(e.WT) == "string" and e.WT or "Pistol", WL = tonumber(e.WL) or 0 })
				end
			end
		end
	end
	table.sort(data.List, function(a, b) return a.Power > b.Power end)
	while #data.List > 3 do table.remove(data.List) end
	return data
end

-- 저장소에서 읽거나 (필요하면) 내 서버 유저를 합쳐서 쓴다. 성공하면 hallCache 를 갱신한다.
local function syncHall()
	if not hallStore then return false end
	local candidates = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local snap = snapshotOf(player)
		if snap.Power > 0 then table.insert(candidates, snap) end
	end
	table.sort(candidates, function(a, b) return a.Power > b.Power end)
	while #candidates > 3 do table.remove(candidates) end

	local cached = hallCache or { List = {}, Banned = {} }
	local need = false
	for _, c in ipairs(candidates) do
		if not cached.Banned[tostring(c.UserId)] then
			local known = nil
			for _, e in ipairs(cached.List) do
				if e.UserId == c.UserId then known = e end
			end
			if known then
				if c.Power > known.Power then need = true end
			elseif #cached.List < 3 or c.Power > cached.List[#cached.List].Power then
				need = true
			end
		end
	end

	local ok, result = pcall(function()
		if need then
			return hallStore:UpdateAsync(HALL_KEY, function(old)
				local data = cleanData(old)
				local byId = {}
				for _, e in ipairs(data.List) do byId[e.UserId] = e end
				for _, c in ipairs(candidates) do
					if not data.Banned[tostring(c.UserId)] then
						local e = byId[c.UserId]
						if not e or c.Power >= e.Power then byId[c.UserId] = c end
					end
				end
				local list = {}
				for _, e in pairs(byId) do table.insert(list, e) end
				table.sort(list, function(a, b) return a.Power > b.Power end)
				while #list > 3 do table.remove(list) end
				return { List = list, Banned = data.Banned }
			end)
		end
		return hallStore:GetAsync(HALL_KEY)
	end)
	if not ok then
		warn("[HallOfFame] DataStore error: " .. tostring(result))
		return false
	end
	hallCache = cleanData(result)
	return true
end

-- 운영자: 명예의 전당 rank 번째 기록을 지우고 그 유저가 다시 올라오지 못하게 막는다
function Showcase.RemoveHall(rank)
	if not hallStore or typeof(rank) ~= "number" then return false, "unavailable" end
	rank = math.floor(rank)
	local removedName = nil
	local ok, result = pcall(function()
		return hallStore:UpdateAsync(HALL_KEY, function(old)
			local data = cleanData(old)
			local entry = data.List[rank]
			if not entry then return nil end
			removedName = entry.Name
			data.Banned[tostring(entry.UserId)] = true
			table.remove(data.List, rank)
			return { List = data.List, Banned = data.Banned }
		end)
	end)
	if not ok then return false, tostring(result) end
	if not removedName then return false, "no entry" end
	hallCache = cleanData(result)
	hallAt = -1e9
	task.spawn(function() Showcase.Refresh() end)
	return true, removedName
end

local function onlineEntries()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local snap = snapshotOf(player)
		if snap.Power > 0 then table.insert(list, snap) end
	end
	table.sort(list, function(a, b) return a.Power > b.Power end)
	return list
end

function Showcase.Refresh()
	local list
	if hallStore then
		if os.clock() - hallAt >= HALL_EVERY then
			if syncHall() then hallAt = os.clock() else hallAt = os.clock() - HALL_EVERY + 15 end -- 실패하면 15초 뒤에 다시
		end
		list = hallCache and hallCache.List
	end
	if not list or #list == 0 then list = onlineEntries() end

	table.clear(hallRanks)
	for rank = 1, 3 do
		local entry = list[rank]
		local slot = slots[rank]
		if entry and entry.Power > 0 then
			hallRanks[entry.UserId] = rank
			local key = string.format("%d_%d_%s_%d", entry.UserId, entry.Power // 25, entry.WT or "Pistol", entry.WL or 0)
			if slot.Key ~= key then
				buildSlot(rank, entry)
			end
		elseif slot.Key ~= nil then
			clearSlot(slot)
			slot.Label.Text = emptyText(rank)
		end
	end

	Showcase.RefreshChampions()
end

------------------------------------------------------------
-- 이번 주 챔피언 (보스 러쉬 주간 1~3위): 동쪽 성벽 안쪽, 필드 입구 남쪽
------------------------------------------------------------
local CHAMP_FACE_X = 127 -- 동쪽 성벽 안쪽 면
local CHAMP_Z = { -70, -40, -100 } -- 1등 가운데, 2등 / 3등 양옆 (북동쪽 벽: 남동쪽에는 보스 러쉬 포탈 / 나무가 앞을 가렸다)
local CHAMP_LOOK = Vector3.new(-1, 0, 0) -- 광장(서쪽)을 바라본다

local function compact(n)
	if n >= 1e9 then return string.format("%.2fB", n / 1e9) end
	if n >= 1e6 then return string.format("%.2fM", n / 1e6) end
	if n >= 1e3 then return string.format("%.1fK", n / 1e3) end
	return tostring(math.floor(n))
end

buildChampStages = function()
	for rank = 1, 3 do
		local color = MEDAL_COLORS[rank]
		local z = CHAMP_Z[rank]
		local backdrop = Instance.new("Part")
		backdrop.Name = "ChampBackdrop" .. rank
		backdrop.Anchored = true
		backdrop.Size = Vector3.new(1, 24, 18)
		backdrop.Position = Vector3.new(CHAMP_FACE_X - 0.5, 12.5, z)
		backdrop.Color = Color3.fromRGB(26, 24, 40)
		backdrop.Material = Enum.Material.Slate
		backdrop.Parent = folder
		for _, edge in ipairs({
			{ Vector3.new(1.4, 0.7, 18.6), Vector3.new(0, 12, 0) },
			{ Vector3.new(1.4, 0.7, 18.6), Vector3.new(0, -12, 0) },
			{ Vector3.new(1.4, 24, 0.7), Vector3.new(0, 0, -9) },
			{ Vector3.new(1.4, 24, 0.7), Vector3.new(0, 0, 9) },
		}) do
			local trim = Instance.new("Part")
			trim.Anchored = true
			trim.CanCollide = false
			trim.Size = edge[1]
			trim.Position = backdrop.Position + edge[2]
			trim.Color = color
			trim.Material = Enum.Material.Neon
			trim.Parent = folder
		end
		local platform = Instance.new("Part")
		platform.Name = "ChampLedge" .. rank
		platform.Anchored = true
		platform.Size = Vector3.new(10, 1.4, 14)
		platform.Position = Vector3.new(CHAMP_FACE_X - 6, 0.75, z)
		platform.Color = Color3.fromRGB(70, 66, 84)
		platform.Material = Enum.Material.Granite
		platform.Parent = folder
		local halo = Instance.new("Part")
		halo.Anchored = true
		halo.CanCollide = false
		halo.CanQuery = false
		halo.CastShadow = false
		halo.Shape = Enum.PartType.Cylinder
		halo.Material = Enum.Material.Neon
		halo.Color = color
		halo.Transparency = 0.55
		halo.Size = Vector3.new(0.2, 11, 11)
		halo.CFrame = CFrame.new(platform.Position + Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, 0, math.rad(90))
		halo.Parent = folder
		local glow = Instance.new("PointLight")
		glow.Range = 30
		glow.Brightness = 1.6
		glow.Color = color
		glow.Parent = backdrop
		champSlots[rank] = {
			Platform = platform, Top = Vector3.new(platform.Position.X, 1.45, z), Scale = 2.2, Look = CHAMP_LOOK, Key = nil, Model = nil, Weapon = nil,
			Label = makeLabel(platform, 18, 110, 230, 90),
		}
		champSlots[rank].Label.Text = MEDAL[rank] .. " Boss Rush champion\n<font size='14'>Resets every week</font>"
	end
	local header = makeLabel(champSlots[1].Platform, 28, 220, 330, 80)
	header.Text = "👑 This Week's Champions 👑"
	header.TextColor3 = Color3.fromRGB(255, 226, 120)
end

function Showcase.RefreshChampions()
	if #champSlots == 0 then return end
	local okRift, Rift = pcall(function() return require(script.Parent:FindFirstChild("RiftService")) end)
	local top = {}
	if okRift and Rift and Rift.WeeklyTop then
		local okTop, result = pcall(Rift.WeeklyTop, 3)
		if okTop and typeof(result) == "table" then top = result end
	end
	table.clear(weeklyRanks)
	for rank = 1, 3 do
		local entry = top[rank]
		local slot = champSlots[rank]
		if entry then
			weeklyRanks[entry.UserId] = rank
			local key = string.format("%d_%d", entry.UserId, math.floor(entry.Score))
			if slot.Key ~= key then
				clearSlot(slot)
				slot.Key = key
				slot.Label.Text = string.format("%s %s\n<font color='#ffe16e'>⚔ %s</font>\n<font color='#9ad7ff'>Boss Rush score</font>", MEDAL[rank], entry.Name or "?", compact(entry.Score))
				spawnAvatar(slot, entry.UserId, key)
			end
		elseif slot.Key ~= nil then
			clearSlot(slot)
			slot.Label.Text = MEDAL[rank] .. " Boss Rush champion\n<font size='14'>Resets every week</font>"
		end
	end
end

return Showcase
