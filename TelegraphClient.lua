-- TelegraphClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: TelegraphClient)
-- 강공격 예고(위협 3단 티어)를 내 화면에서만 그린다 (11-24 종태 님 + 클로드 합의).
--   서버는 몬스터 부품에 속성만 붙인다: TeleFrom / TeleUntil / TeleTier / TeleShape / TeleSize / TeleDir / TeleLen / TeleWidth / TeleMult
--     * TeleUntil 은 workspace:GetServerTimeNow() 기준 "절대 시각" (남은 초로 받으면 늦게 도착한 만큼 어긋난다)
--     * 서버가 만들던 ShotCharge 부품은 없어졌다: 같은 자리(몸 앞)에 여기서 그린다 -> 서버 부품 복제가 사라져 오히려 가볍다
--   규칙
--     ① 몸 앞 구의 색 = 내 한 방 % (Config.Threat.HitTiers 15 / 35): 노랑(주의) / 빨강(위험). T1 은 작고 흐리게.
--     ② 바닥 도형 + 낮은 경고음 = 패턴 고정 티어가 3 이고 내 한 방 % 가 Demote(15%) 이상일 때만 (약한 구역에서 화면이 시끄러워지지 않게)
--     ③ 도형 = 옅은 채움 + 밝은 테두리 + 안쪽에서 차오르는 링. 마지막 25% 에서 채움이 한 번 번쩍 (완벽 회피 타이밍)
--   부품은 풀에서 돌려 쓰고, 동시에 도형 8개(가까운 순) / 구 10개만 그린다.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local SoundBank = require(ReplicatedStorage:WaitForChild("SoundBank"))
local Signal = require(ReplicatedStorage:WaitForChild("FieldSignal"))

local player = Players.LocalPlayer
local T = Config.Threat
local MAX_SHAPES, MAX_ORBS, RANGE = 8, 10, 300

local COLORS = {
	[1] = Color3.fromRGB(255, 226, 140), -- 일반: 옅은 노랑
	[2] = Color3.fromRGB(255, 186, 60),  -- 주의: 노랑
	[3] = Color3.fromRGB(255, 70, 45),   -- 위험: 빨강
}

local fxFolder = Instance.new("Folder")
fxFolder.Name = "TelegraphFx"
fxFolder.Parent = workspace

------------------------------------------------------------
-- 부품 풀
------------------------------------------------------------
local pools = { Orb = {}, Disc = {}, Strip = {} }
local function take(kind)
	local item = table.remove(pools[kind])
	if item then item.Parent = fxFolder return item end
	local part = Instance.new("Part")
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = true, false, false, false, false
	part.Material = Enum.Material.Neon
	part.Parent = fxFolder
	if kind == "Orb" then
		part.Shape = Enum.PartType.Ball
	elseif kind == "Disc" then
		part.Shape = Enum.PartType.Cylinder
	else
		part.Shape = Enum.PartType.Block
	end
	return part
end
local function give(kind, part)
	if not part then return end
	part.Parent = nil
	local list = pools[kind]
	if #list < 20 then
		list[#list + 1] = part
	else
		part:Destroy()
	end
end

------------------------------------------------------------
-- 감시: 몬스터 부품의 TeleUntil 속성이 바뀌면 예고 하나를 등록한다
------------------------------------------------------------
local active = {} -- [part] = { From, Until, Tier, Shape, Size, Dir, Len, Width, Mult, Orb, Edge, Fill, SoundAt }
local watched = setmetatable({}, { __mode = "k" })

local function releaseShape(entry)
	if not entry.Edge then return end
	local kind = entry.EdgeKind == "Strip" and "Strip" or "Disc"
	give(kind, entry.Edge)
	give(kind, entry.Fill)
	entry.Edge, entry.Fill, entry.EdgeKind = nil, nil, nil
end

local function clear(part)
	local entry = active[part]
	if not entry then return end
	active[part] = nil
	give("Orb", entry.Orb)
	releaseShape(entry)
end

local function refresh(part)
	local untilAt = part:GetAttribute("TeleUntil")
	if typeof(untilAt) ~= "number" or untilAt <= workspace:GetServerTimeNow() then
		clear(part)
		return
	end
	local entry = active[part]
	if not entry then
		entry = {}
		active[part] = entry
	end
	entry.From = part:GetAttribute("TeleFrom") or workspace:GetServerTimeNow()
	entry.Until = untilAt
	entry.Tier = part:GetAttribute("TeleTier") or 1
	entry.Shape = part:GetAttribute("TeleShape") or "None"
	entry.Size = part:GetAttribute("TeleSize") or 0
	entry.Dir = part:GetAttribute("TeleDir")
	entry.Len = part:GetAttribute("TeleLen") or 0
	entry.Width = part:GetAttribute("TeleWidth") or 0
	entry.Mult = part:GetAttribute("TeleMult") or 1
end

local function watch(part)
	if watched[part] then return end
	watched[part] = true
	part:GetAttributeChangedSignal("TeleUntil"):Connect(function()
		if part.Parent then refresh(part) else clear(part) end
	end)
	part.AncestryChanged:Connect(function()
		if not part.Parent then clear(part) end
	end)
	refresh(part)
end

local function watchFolder(folder)
	if not folder or folder:GetAttribute("TelegraphWatched") then return end
	folder:SetAttribute("TelegraphWatched", true)
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") then watch(child) end
	end
	folder.ChildAdded:Connect(function(child)
		if child:IsA("BasePart") then watch(child) end
	end)
end

-- 필드 몬스터 폴더 / 던전 몬스터 폴더를 1초에 한 번 찾아서 붙는다 (새 판이 열려도 따라간다)
task.spawn(function()
	while true do
		watchFolder(workspace:FindFirstChild("FieldMonsters"))
		for _, child in ipairs(workspace:GetChildren()) do
			if string.sub(child.Name, 1, 8) == "Dungeon_" then
				local folder = child:FindFirstChild("Monsters")
				if folder then watchFolder(folder) end
			end
		end
		task.wait(1)
	end
end)

------------------------------------------------------------
-- 내 한 방 % (받는 피해 배율 반영) -> 구 색 / 도형 여부
------------------------------------------------------------
local function hitPct(part, mult)
	local shot = part:GetAttribute("MobShot")
	if not shot then return nil end
	return Signal.HitPctFor(shot * (mult or 1))
end
local function tierOfPct(pct)
	if not pct then return nil end
	local tiers = T.HitTiers
	if pct < tiers[1] then return 1 elseif pct < tiers[2] then return 2 end
	return 3
end

------------------------------------------------------------
-- 경고음: 동시 2개, 같은 몹은 1.5초에 한 번만 (100마리 필드에서 계속 울리지 않게)
------------------------------------------------------------
local sounding, soundCount = setmetatable({}, { __mode = "k" }), 0
local function warnSound(part)
	local now = os.clock()
	if soundCount >= 2 then return end
	if now - (sounding[part] or -9) < 1.5 then return end
	sounding[part] = now
	soundCount += 1
	local ok = pcall(function() SoundBank.Play(part, "Lord_Charge", { Volume = 0.5, Pitch = 0.25 }) end)
	task.delay(0.9, function() soundCount = math.max(0, soundCount - 1) end)
	if not ok then soundCount = math.max(0, soundCount - 1) end
end

------------------------------------------------------------
-- 매 프레임: 가까운 예고부터 구 / 도형을 그린다
------------------------------------------------------------
local camera = workspace.CurrentCamera
local pctCache = setmetatable({}, { __mode = "k" }) -- [part] = { At, Value } (한 프레임에 한 번만 잰다)
local function cachedPct(part, mult)
	local hit = pctCache[part]
	local now = os.clock()
	if hit and now - hit.At < 0.25 then return hit.Value end
	local value = hitPct(part, mult)
	pctCache[part] = { At = now, Value = value }
	return value
end

RunService.RenderStepped:Connect(function()
	if workspace:GetAttribute("PhotoFreeze") then return end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local eye = root and root.Position or (camera and camera.CFrame.Position)
	local now = workspace:GetServerTimeNow()
	local list = {}
	for part, entry in pairs(active) do
		if not part.Parent or now >= entry.Until then
			clear(part)
		elseif eye then
			local d = (part.Position - eye).Magnitude
			if d <= RANGE then
				list[#list + 1] = { Part = part, Entry = entry, D = d }
			else -- 멀리 있는 예고의 부품은 돌려놓는다 (그 자리에 얼어붙은 도형이 남지 않게)
				if entry.Orb then give("Orb", entry.Orb) entry.Orb = nil end
				releaseShape(entry)
			end
		end
	end
	table.sort(list, function(a, b) return a.D < b.D end)

	local shapes = 0
	for index, item in ipairs(list) do
		local part, entry = item.Part, item.Entry
		local span = math.max(0.05, entry.Until - entry.From)
		local p = math.clamp((now - entry.From) / span, 0, 1)
		local pct = cachedPct(part, entry.Mult)
		local visual = tierOfPct(pct) or entry.Tier -- 구 색: 내 체력 기준 (던전처럼 한 방 % 를 모르면 패턴 티어)
		local color = COLORS[visual]

		-- ① 몸 앞 구
		if index <= MAX_ORBS then
			local orb = entry.Orb
			if not orb then orb = take("Orb") entry.Orb = orb end
			local base = math.clamp(part.Size.X * 0.32, 0.8, 5)
			local grow = 0.3 + 0.7 * (p * p)
			orb.Size = Vector3.new(base * grow, base * grow, base * grow) * (visual >= 3 and 1.25 or 1)
			orb.Color = color
			orb.Transparency = 0.3 - 0.2 * p
			orb.Position = part.CFrame:PointToWorldSpace(Vector3.new(0, part.Size.Y * 0.15, -part.Size.Z * 0.55))
			orb.Parent = fxFolder
		elseif entry.Orb then
			give("Orb", entry.Orb)
			entry.Orb = nil
		end

		-- ② 바닥 도형 (패턴 고정 티어 3 + 내 한 방 % >= Demote 일 때만)
		local wantShape = (entry.Tier >= 3 and entry.Shape ~= "None" and shapes < MAX_SHAPES) and (pct == nil or pct >= T.Demote)
		if wantShape then
			shapes += 1
			local pulse = p > 0.75 and (0.5 + 0.5 * math.sin(now * 40)) or 0
			if entry.Shape == "Strip" and entry.Dir then
				local edge, fill = entry.Edge, entry.Fill
				if not edge or entry.EdgeKind ~= "Strip" then
					if edge then give("Disc", edge) end
					if fill then give("Disc", fill) end
					edge, fill = take("Strip"), take("Strip")
					entry.Edge, entry.Fill, entry.EdgeKind = edge, fill, "Strip"
				end
				local length, width = math.max(8, entry.Len), math.max(6, entry.Width)
				local base = Vector3.new(part.Position.X, part.Position.Y - part.Size.Y / 2 + 0.3, part.Position.Z) -- 발밑 높이에 그린다
				local mid = base + entry.Dir * (length / 2)				edge.Size = Vector3.new(width, 0.22, length)
				edge.CFrame = CFrame.lookAt(mid, mid + entry.Dir)
				edge.Color, edge.Transparency = color, 0.5
				local front = base + entry.Dir * (length * p / 2)
				fill.Size = Vector3.new(math.max(2, width - 3), 0.24, math.max(0.5, length * p))
				fill.CFrame = CFrame.lookAt(front, front + entry.Dir)
				fill.Color, fill.Transparency = color, 0.82 - 0.25 * pulse
			elseif entry.Shape == "Disc" then
				local edge, fill = entry.Edge, entry.Fill
				if not edge or entry.EdgeKind == "Strip" then
					if edge then give("Strip", edge) end
					if fill then give("Strip", fill) end
					edge, fill = take("Disc"), take("Disc")
					entry.Edge, entry.Fill, entry.EdgeKind = edge, fill, "Disc"
				end
				local radius = math.max(4, entry.Size)
				local center = Vector3.new(part.Position.X, part.Position.Y - part.Size.Y / 2 + 0.3, part.Position.Z)
				local flat = CFrame.new(center + Vector3.new(0, 0.32, 0)) * CFrame.Angles(0, 0, math.rad(90))
				edge.Size = Vector3.new(0.22, radius * 2, radius * 2)
				edge.CFrame = flat
				edge.Color, edge.Transparency = color, 0.5
				local d = math.max(0.4, (radius - 1.5) * 2 * p) -- (테두리 1.5칸은 채움 없이 남겨 밝은 띄로 보이게)
				fill.Size = Vector3.new(0.24, d, d)
				fill.CFrame = flat
				fill.Color, fill.Transparency = color, 0.82 - 0.25 * pulse
			end
			warnSound(part)
		else
			releaseShape(entry)
		end
	end
end)
