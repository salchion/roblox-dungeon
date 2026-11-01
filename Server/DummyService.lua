-- DummyService (ServerScriptService > Modules 안의 ModuleScript, 이름: DummyService)
-- 로비 허수아비 훈련장: 대미지 숫자 / DPS 를 확인하는 연습용 (골드는 없다). 방치 수입은 따로 있는 휴식 구역(BuildRest).
-- 1번(x1)부터 10번(x30)까지 한 줄로 나열되고, 배수가 높을수록 크고 화려하고 강해 보인다.
-- 더미마다 이름 / 배율(Multiplier) / 방어력(RequiredPower: 필요 전투력)이 다르다 -> Config.Dummy.List

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Effects = require(script.Parent:WaitForChild("Effects"))
local Quest = require(script.Parent:WaitForChild("QuestService"))

local Dummy = {}

local dummies = {}   -- [Model] = { Multiplier, RequiredLevel, Parts..., BaseColor, Flashing }
local folder

local function newPart(props, parent)
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		part[key] = value
	end
	part.Parent = parent
	return part
end

-- 훈련장 장식 (맞지도 막지도 않는다): 충돌 / 질의 / 접촉 / 그림자 없음
local function deco(props, parent)
	props.CanCollide, props.CanQuery, props.CanTouch, props.CastShadow = false, false, false, false
	return newPart(props, parent)
end

local WOOD = Color3.fromRGB(110, 78, 50)
local WOOD_DARK = Color3.fromRGB(78, 56, 40)
local LEATHER = Color3.fromRGB(86, 58, 40)
local GOLD = Color3.fromRGB(232, 190, 80)
local STEEL = Color3.fromRGB(150, 156, 170)
local RED = Color3.fromRGB(176, 52, 56)
local STRAW = Color3.fromRGB(214, 184, 112)

-- 허수아비 한 마리. variant: "Knight" (투구 + 방패) / "Mage" (마법사 모자 + 구슬) / "Brute" (뿔 + 가시 어깨). s: 크기 배율.
-- 맞는 곳(몸통 / 머리 / 장비)은 FlashParts 에 모아서 맞을 때 번쩍인다. 바닥 문양 / 끈 같은 장식은 맞지 않는다.
local function buildDummy(info, position, s, variant, nameIndex)
	local model = Instance.new("Model")
	model.Name = "Dummy" .. nameIndex
	local V = function(x, y, z) return Vector3.new(x * s, y * s, z * s) end
	local O = function(x, y, z) return position + Vector3.new(x * s, y * s, z * s) end
	local function disc(name, diameter, thickness, pos, color, material, faceZ, extra)
		local cf = CFrame.new(pos) * (faceZ and CFrame.Angles(0, math.rad(90), 0) or CFrame.Angles(0, 0, math.rad(90)))
		local props = { Name = name, Shape = Enum.PartType.Cylinder, Size = Vector3.new(thickness, diameter, diameter), CFrame = cf, Color = color, Material = material }
		for key, value in pairs(extra or {}) do props[key] = value end
		return deco(props, model)
	end

	-- 받침: 돌 단 + 금빛 룬 고리 (바닥에 은은하게)
	newPart({ Name = "Base", Shape = Enum.PartType.Cylinder, Size = V(0.8, 5.4, 5.4), CFrame = CFrame.new(O(0, 0.4, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(96, 92, 90), Material = Enum.Material.Cobblestone }, model)
	disc("RuneRing", 6.6 * s, 0.1, position + Vector3.new(0, 0.06, 0), GOLD, Enum.Material.Neon, false, { Transparency = 0.45 })
	disc("RuneRingInner", 4.2 * s, 0.12, position + Vector3.new(0, 0.07, 0), GOLD, Enum.Material.Neon, false, { Transparency = 0.7 })

	-- 기둥 + 팔 (밧줄로 묶음)
	newPart({ Name = "Post", Size = V(0.9, 7, 0.9), Position = O(0, 3.9, 0), Color = WOOD, Material = Enum.Material.Wood }, model)
	newPart({ Name = "Arms", Size = V(6.6, 0.8, 0.8), Position = O(0, 5.9, 0), Color = WOOD, Material = Enum.Material.Wood }, model)
	for _, x in ipairs({ -3, 3 }) do
		deco({ Name = "Rope", Size = V(0.5, 1, 1), Position = O(x, 5.9, 0), Color = Color3.fromRGB(196, 176, 130), Material = Enum.Material.Fabric }, model)
	end

	-- 몸통 / 머리
	local body = newPart({ Name = "Body", Size = V(3.2, 3.8, 2.2), Position = O(0, 5, 0), Color = STRAW, Material = Enum.Material.Fabric }, model)
	local head = newPart({ Name = "Head", Shape = Enum.PartType.Ball, Size = V(2.4, 2.4, 2.4), Position = O(0, 7.8, 0), Color = Color3.fromRGB(226, 198, 130), Material = Enum.Material.Fabric }, model)
	model.PrimaryPart = body
	local flash = { body, head }
	-- 가죽 끈 (X 자) + 허리띠 + 금 버클
	for _, side in ipairs({ -1, 1 }) do
		deco({ Name = "Strap", Size = V(0.45, 4.2, 0.2), CFrame = CFrame.new(O(0, 5, 1.12)) * CFrame.Angles(0, 0, math.rad(side * 32)), Color = LEATHER, Material = Enum.Material.Leather }, model)
	end
	deco({ Name = "Belt", Size = V(3.4, 0.5, 2.4), Position = O(0, 3.55, 0), Color = LEATHER, Material = Enum.Material.Leather }, model)
	deco({ Name = "Buckle", Size = V(0.7, 0.5, 0.2), Position = O(0, 3.55, 1.25), Color = GOLD, Material = Enum.Material.Metal }, model)
	-- 가슴 과녁: 빨강 / 흰색 / 빨강 동심원
	disc("TargetOuter", 2.5 * s, 0.06, O(0, 5.2, 1.13), RED, Enum.Material.SmoothPlastic, true)
	disc("TargetMid", 1.7 * s, 0.07, O(0, 5.2, 1.15), Color3.fromRGB(240, 236, 226), Enum.Material.SmoothPlastic, true)
	disc("TargetCore", 0.9 * s, 0.08, O(0, 5.2, 1.17), RED, Enum.Material.SmoothPlastic, true)
	-- 꿰맨 얼굴: X 눈 + 입
	for _, ex in ipairs({ -0.55, 0.55 }) do
		for _, angle in ipairs({ 45, -45 }) do
			deco({ Name = "FaceStitch", Size = V(0.5, 0.1, 0.1), CFrame = CFrame.new(O(ex, 8, 1.16)) * CFrame.Angles(0, 0, math.rad(angle)), Color = Color3.fromRGB(60, 42, 34), Material = Enum.Material.Fabric }, model)
		end
	end
	deco({ Name = "FaceMouth", Size = V(1.1, 0.1, 0.1), Position = O(0, 7.35, 1.15), Color = Color3.fromRGB(60, 42, 34), Material = Enum.Material.Fabric }, model)

	-- 뒤쪽 찢어진 붉은 망토
	deco({ Name = "Cape", Size = V(3.4, 4.4, 0.18), Position = O(0, 4.6, -1.35), Color = Color3.fromRGB(150, 42, 50), Material = Enum.Material.Fabric }, model)
	for i = -1, 1 do
		deco({ Name = "CapeTatter", Size = V(0.9, 1 + (i % 2) * 0.5, 0.16), Position = O(i * 1.15, 2.1 - (i % 2) * 0.25, -1.35), Color = Color3.fromRGB(150, 42, 50), Material = Enum.Material.Fabric }, model)
	end

	-- 모양별 장비
	if variant == "Knight" then
		local helm = newPart({ Name = "Helm", Size = V(2.7, 1.5, 2.7), Position = O(0, 8.55, 0), Color = STEEL, Material = Enum.Material.Metal }, model)
		table.insert(flash, helm)
		deco({ Name = "Crest", Size = V(0.4, 1.1, 2.2), Position = O(0, 9.5, 0), Color = RED, Material = Enum.Material.Fabric }, model)
		for _, side in ipairs({ -1, 1 }) do
			table.insert(flash, newPart({ Name = "Shoulder", Size = V(1.6, 1, 1.9), Position = O(side * 2.5, 6.6, 0), Color = STEEL, Material = Enum.Material.Metal }, model))
		end
		local shield = newPart({ Name = "Shield", Shape = Enum.PartType.Cylinder, Size = V(0.4, 3, 3), CFrame = CFrame.new(O(-3.6, 5.2, 0.7)) * CFrame.Angles(0, math.rad(90), 0), Color = WOOD, Material = Enum.Material.WoodPlanks }, model)
		table.insert(flash, shield)
		disc("ShieldRim", 3.2 * s, 0.3, O(-3.6, 5.2, 0.62), STEEL, Enum.Material.Metal, true)
		disc("ShieldBoss", 0.9 * s, 0.25, O(-3.6, 5.2, 0.95), GOLD, Enum.Material.Metal, true)
	elseif variant == "Mage" then
		local brim = newPart({ Name = "HatBrim", Shape = Enum.PartType.Cylinder, Size = V(0.3, 3.8, 3.8), CFrame = CFrame.new(O(0, 8.9, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(60, 56, 120), Material = Enum.Material.Fabric }, model)
		table.insert(flash, brim)
		for i, d in ipairs({ 2.5, 1.8, 1.1, 0.5 }) do
			table.insert(flash, newPart({ Name = "HatCone", Shape = Enum.PartType.Cylinder, Size = V(0.9, d, d), CFrame = CFrame.new(O(0, 9.3 + (i - 1) * 0.85, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(70, 66, 140), Material = Enum.Material.Fabric }, model))
		end
		deco({ Name = "HatBand", Shape = Enum.PartType.Cylinder, Size = V(0.3, 2.6, 2.6), CFrame = CFrame.new(O(0, 9.1, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = GOLD, Material = Enum.Material.Metal }, model)
		-- 오른손의 빛나는 구슬 (살짝 위아래로 떠 있는 느낌의 고정 구슬 + 은은한 빛)
		deco({ Name = "StaffPole", Size = V(0.35, 5, 0.35), Position = O(3.8, 4.1, 0.6), Color = WOOD_DARK, Material = Enum.Material.Wood }, model)
		local orb = deco({ Name = "Orb", Shape = Enum.PartType.Ball, Size = V(1.2, 1.2, 1.2), Position = O(3.8, 7, 0.6), Color = Color3.fromRGB(120, 200, 255), Material = Enum.Material.Neon }, model)
		local light = Instance.new("PointLight")
		light.Color, light.Range, light.Brightness, light.Shadows = Color3.fromRGB(120, 200, 255), 10, 0.5, false
		light.Parent = orb
	else -- Brute
		for _, side in ipairs({ -1, 1 }) do
			table.insert(flash, newPart({ Name = "Horn", Size = V(0.5, 2.3, 0.5), CFrame = CFrame.new(O(side * 1.3, 9.2, 0)) * CFrame.Angles(0, 0, math.rad(-side * 25)), Color = Color3.fromRGB(236, 226, 202), Material = Enum.Material.SmoothPlastic }, model))
			table.insert(flash, newPart({ Name = "Pauldron", Size = V(1.8, 1.1, 2), Position = O(side * 2.6, 6.6, 0), Color = Color3.fromRGB(80, 74, 80), Material = Enum.Material.Metal }, model))
			for k = 0, 2 do
				deco({ Name = "Spike", Size = V(0.35, 1.1, 0.35), CFrame = CFrame.new(O(side * (2.2 + k * 0.4), 7.4, (k - 1) * 0.6)) * CFrame.Angles(0, 0, math.rad(-side * 20)), Color = Color3.fromRGB(226, 218, 196), Material = Enum.Material.SmoothPlastic }, model)
			end
		end
		local brow = newPart({ Name = "Brow", Size = V(2.6, 0.5, 1), Position = O(0, 8.55, 0.95), Color = Color3.fromRGB(80, 74, 80), Material = Enum.Material.Metal }, model)
		table.insert(flash, brow)
	end

	model.Parent = folder
	local baseColors = {}
	for _, part in ipairs(flash) do baseColors[part] = part.Color end
	dummies[model] = { Multiplier = info.Multiplier, RequiredPower = info.RequiredPower, Name = info.Name, FlashParts = flash, BaseColors = baseColors, Flashing = false }
	return model
end

-- 모델을 자기 받침 위치를 축으로 돌린다 (앞면(+Z)이 yaw 방향을 보게)
local function faceModel(model, position, yaw)
	local turn = CFrame.new(position) * CFrame.Angles(0, yaw, 0) * CFrame.new(-position)
	model:PivotTo(turn * model:GetPivot())
end

-- start: 훈련장 중심. facing: 훈련장 앞(플레이어가 오는 쪽) 방향. 허수아비 5마리가 호를 그리며 서 있고 (세트 효과 / 스킬이 여러 마리에 터지는 걸 볼 수 있게),
-- 둘레는 흙바닥 + 울타리 + 깃발 + 무기 걸이 + 간판으로 꾸민다.
function Dummy.Build(start, facing)
	folder = Instance.new("Folder")
	folder.Name = "Dummies"
	folder.Parent = workspace

	local fwd = facing and Vector3.new(facing.X, 0, facing.Z) or Vector3.new(0, 0, 1)
	fwd = fwd.Magnitude > 0.01 and fwd.Unit or Vector3.new(0, 0, 1)
	local yaw = math.atan2(fwd.X, fwd.Z)
	local turn = CFrame.Angles(0, yaw, 0)

	-- 장식: 앞(+Z)이 플레이어 쪽이 되게 만든 뒤 통째로 돌린다
	local yard = Instance.new("Model")
	yard.Name = "TrainingYard"
	local function at(x, z, y) return start + Vector3.new(x, y or 0, z) end
	deco({ Name = "TrainingGround", Size = Vector3.new(70, 0.3, 48), Position = at(0, 0, 0.15), Color = Color3.fromRGB(104, 92, 80), Material = Enum.Material.Cobblestone }, yard)
	deco({ Name = "TrainingDirt", Size = Vector3.new(62, 0.34, 40), Position = at(0, 0, 0.17), Color = Color3.fromRGB(142, 116, 86), Material = Enum.Material.Ground }, yard)
	-- 울타리: 뒤쪽 + 양옆 (앞은 열어 둔다)
	local function fenceRun(x1, z1, x2, z2)
		local a, b = at(x1, z1), at(x2, z2)
		local length = (b - a).Magnitude
		local steps = math.max(1, math.floor(length / 6))
		for i = 0, steps do
			local p = a:Lerp(b, i / steps)
			deco({ Name = "FencePost", Size = Vector3.new(0.8, 4, 0.8), Position = p + Vector3.new(0, 2, 0), Color = WOOD_DARK, Material = Enum.Material.Wood }, yard)
		end
		local mid = (a + b) / 2
		for _, h in ipairs({ 1.4, 3 }) do
			deco({ Name = "FenceRail", Size = Vector3.new(0.35, 0.4, length), CFrame = CFrame.lookAt(mid + Vector3.new(0, h, 0), b + Vector3.new(0, h, 0)), Color = WOOD, Material = Enum.Material.WoodPlanks }, yard)
		end
	end
	fenceRun(-33, -22, 33, -22)
	fenceRun(-33, -22, -33, 12)
	fenceRun(33, -22, 33, 12)
	-- 앞쪽 모서리 깃발 두 개
	for _, x in ipairs({ -33, 33 }) do
		deco({ Name = "BannerPole", Size = Vector3.new(0.5, 11, 0.5), Position = at(x, 20, 5.5), Color = WOOD_DARK, Material = Enum.Material.Wood }, yard)
		deco({ Name = "Banner", Size = Vector3.new(3.4, 5.6, 0.2), Position = at(x + (x > 0 and -1.9 or 1.9), 20, 7.6), Color = RED, Material = Enum.Material.Fabric }, yard)
		deco({ Name = "BannerEmblem", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.22, 1.8, 1.8), CFrame = CFrame.new(at(x + (x > 0 and -1.9 or 1.9), 20, 8.2)) * CFrame.Angles(0, math.rad(90), 0), Color = GOLD, Material = Enum.Material.Metal }, yard)
	end
	-- 무기 걸이 (오른쪽 뒤): 가로대 + 창 / 검 세 자루
	do
		local rx, rz = 27, -17
		deco({ Name = "RackBeam", Size = Vector3.new(8, 0.5, 0.6), Position = at(rx, rz, 3.6), Color = WOOD_DARK, Material = Enum.Material.Wood }, yard)
		for _, side in ipairs({ -1, 1 }) do
			deco({ Name = "RackLeg", Size = Vector3.new(0.6, 3.8, 0.6), Position = at(rx + side * 3.6, rz, 1.9), Color = WOOD_DARK, Material = Enum.Material.Wood }, yard)
		end
		for i = -1, 1 do
			deco({ Name = "RackSpear", Size = Vector3.new(0.25, 5.2, 0.25), CFrame = CFrame.new(at(rx + i * 2.2, rz, 3)) * CFrame.Angles(0, 0, math.rad(i * 6)), Color = WOOD, Material = Enum.Material.Wood }, yard)
			deco({ Name = "RackTip", Size = Vector3.new(0.5, 0.9, 0.2), CFrame = CFrame.new(at(rx + i * 2.2 - i * 0.27, rz, 5.7)) * CFrame.Angles(0, 0, math.rad(i * 6)), Color = STEEL, Material = Enum.Material.Metal }, yard)
		end
	end
	-- 건초 더미 / 통 / 화살 꽂힌 과녁 판
	for _, p in ipairs({ { -27, -17 }, { -30, -14 } }) do
		deco({ Name = "HayBale", Size = Vector3.new(3.2, 2, 2.2), Position = at(p[1], p[2], 1), Color = Color3.fromRGB(206, 178, 104), Material = Enum.Material.Fabric }, yard)
	end
	deco({ Name = "YardBarrel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.8, 2.4, 2.4), CFrame = CFrame.new(at(-24, -18, 1.4)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(116, 82, 54), Material = Enum.Material.Wood }, yard)
	-- 간판: 나무 판 + 나무 기둥 두 개 (플레이어 쪽 모서리)
	do
		local sx, sz = -22, 19
		for _, side in ipairs({ -1, 1 }) do
			deco({ Name = "SignPost", Size = Vector3.new(0.6, 5.6, 0.6), Position = at(sx + side * 3.4, sz, 2.8), Color = WOOD_DARK, Material = Enum.Material.Wood }, yard)
		end
		local board = deco({ Name = "YardSign", Size = Vector3.new(8, 2.8, 0.4), Position = at(sx, sz, 5), Color = Color3.fromRGB(150, 108, 70), Material = Enum.Material.WoodPlanks }, yard)
		local face = Instance.new("SurfaceGui")
		face.Face = Enum.NormalId.Back -- (+Z 쪽: 플레이어가 오는 쪽)
		face.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		face.PixelsPerStud = 40
		face.LightInfluence = 0
		face.Parent = board
		local text = Instance.new("TextLabel")
		text.Size = UDim2.new(1, 0, 1, 0)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.GothamBlack
		text.TextScaled = true
		text.TextColor3 = Color3.fromRGB(255, 240, 200)
		text.TextStrokeTransparency = 0.3
		text.Text = "🎯 Training Yard"
		text.Parent = face
	end
	yard.Parent = folder
	yard:PivotTo(CFrame.new(start) * turn * CFrame.new(-start) * yard:GetPivot())

	-- 허수아비 5마리: 가운데 큰 기사, 양옆 마법사 / 괴수, 뒤쪽 양끝 기사 / 마법사 (호 모양)
	local info = Config.Dummy.List[1]
	local layout = {
		{ 0, 0, 1.5, "Knight" },
		{ -13, -3, 1.2, "Mage" },
		{ 13, -3, 1.2, "Brute" },
		{ -24, -9, 1.0, "Brute" },
		{ 24, -9, 1.0, "Mage" },
	}
	for index, entry in ipairs(layout) do
		local world = start + turn:VectorToWorldSpace(Vector3.new(entry[1], 0, entry[2]))
		local model = buildDummy(info, world, entry[3], entry[4], index)
		faceModel(model, world, yaw)
	end
end

local restFire, restCenter = nil, Vector3.zero -- 휴식 구역 모닥불 (IdleHit 가 타오르게 한다)

local function flash(data)
	if data.Flashing then return end
	data.Flashing = true
	for _, part in ipairs(data.FlashParts) do
		part.Color = Color3.new(1, 1, 1)
	end
	task.delay(0.08, function()
		for _, part in ipairs(data.FlashParts) do
			part.Color = data.BaseColors[part]
		end
		data.Flashing = false
	end)
end

-- 로비에서 쏜 탄이 허수아비에 맞았는지 판정하고 골드를 지급. 반환: 탄이 끝나는 지점 (아무것도 안 맞으면 nil)
-- 방치 모드: 허수아비가 맞는 것처럼 번쩍인다 (훈련장 원 안에 서 있는 동안 IdleService 가 1초마다 부른다)
function Dummy.IdleHit(player)
	if restFire and restFire.Parent then -- 휴식 구역: 모닥불이 한 번 확 타오른다
		restFire.Size = 14
		task.delay(0.25, function()
			if restFire and restFire.Parent then restFire.Size = 8 end
		end)
		Effects.Burst(restCenter + Vector3.new(0, 3, 0), Color3.fromRGB(255, 222, 100), 12) -- 골드가 들어올 때마다 금빛이 튄다
	end
end

-- 허수아비 머리 위 DPS 표시: 최근 5초 동안 쏜 피해의 평균 + 지금까지의 최고 기록 (쏘는 사람마다 따로 계산, 마지막으로 쏜 사람 기준으로 보여 준다)
local dpsLog = setmetatable({}, { __mode = "k" })  -- [player] = { Hits = { { t, amount } }, Best = 0 }
local function showDps(model, data, player, damage)
	local now = os.clock()
	local log = dpsLog[player]
	if not log then
		log = { Hits = {}, Best = 0 }
		dpsLog[player] = log
	end
	table.insert(log.Hits, { now, damage })
	local total, first = 0, now
	for i = #log.Hits, 1, -1 do
		local hit = log.Hits[i]
		if now - hit[1] > 5 then
			table.remove(log.Hits, i)
		else
			total += hit[2]
			first = math.min(first, hit[1])
		end
	end
	local dps = total / math.max(1.5, now - first)
	if dps > log.Best then log.Best = dps end
	-- 머리 위 글자 대신 쏘는 사람 화면의 작은 패널(DpsPanelClient)이 이 값을 읽어 보여 준다
	player:SetAttribute("DummyDps", math.floor(dps))
	player:SetAttribute("DummyBest", math.floor(log.Best))
	player:SetAttribute("DummyHit", damage)
	player:SetAttribute("DummyTick", (player:GetAttribute("DummyTick") or 0) + 1)
end

local goldRemainder = setmetatable({}, { __mode = "k" }) -- [player] = 아직 지급하지 못한 소수점 골드

-- 세트 효과 시험: 허수아비를 쏘는 동안 내 세트 효과(미사일 / 번개 / 메테오 / 칼날 / 충격파 / 점화 / 펫 표식)가 허수아비에게도 터진다.
-- 던전 / 필드와 같은 효과 코드(DungeonService)를 "허수아비만 있는 작은 판"으로 돌린다. 허수아비는 쓰러지지 않으므로
-- 처치 효과(처치 폭발 / 처형 폭발)는 10발마다 "쓰러진 셈"으로 한 번 보여 준다. 최근 6초 안에 허수아비를 쏜 사람에게만 작동한다.
local Players = game:GetService("Players")
local augRun = nil
local lastDummyHit = setmetatable({}, { __mode = "k" })
local hitCount = setmetatable({}, { __mode = "k" })
local function ensureAugRun(Dungeon)
	if augRun or not folder then return augRun end
	local monsters = {}
	local partToModel = {}
	for model, data in pairs(dummies) do
		local body = model.PrimaryPart
		if body then
			monsters[body] = { Health = 1e12, MaxHealth = 1e12, Kind = "Dummy", Stats = { Size = body.Size.Y } }
			partToModel[body] = model
		end
	end
	augRun = {
		Monsters = monsters, Folder = folder, Phase = "Wave", Destroyed = false, Members = {},
		MembersFn = function()
			local list = {}
			for _, player in ipairs(Players:GetPlayers()) do
				if player:GetAttribute("Zone") == "Lobby" and os.clock() - (lastDummyHit[player] or -100) < 6 then table.insert(list, player) end
			end
			return list
		end,
		HitFn = function(player, entry, amount, quiet)
			local model = partToModel[entry.Part]
			local data = model and dummies[model]
			if not data or (player:GetAttribute("Power") or 0) < data.RequiredPower then return end
			entry.Data.Health = entry.Data.MaxHealth -- (쓰러지지 않는다)
			amount = math.max(1, math.floor(amount))
			if not quiet then Effects.DamageNumber(entry.Part.Position, amount, false) end
			showDps(model, data, player, amount) -- DPS 패널에 세트 효과 피해도 더해진다
		end,
	}
	Dungeon.StartAugLoop(augRun)
	return augRun
end

function Dummy.Shoot(player, origin, direction)
	if not folder or player:GetAttribute("Zone") ~= "Lobby" then return nil end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }

	local weaponType = Config.GetPlayerWeapon(player)
	local result = workspace:Raycast(origin, direction * Config.GetRange(player, weaponType), params)
	if not result then return nil end

	local model = result.Instance:FindFirstAncestorOfClass("Model")
	local data = model and dummies[model]
	if not data then return result.Position end

	flash(data)

	-- (방어력이 있는 허수아비가 남아 있을 때만) 내 전투력이 모자라면 공격이 튕겨 나간다
	local power = player:GetAttribute("Power") or 0
	if power < data.RequiredPower then
		Effects.FloatText(result.Position, string.format("🛡 Knocked back! Power %d required (you: %d)", data.RequiredPower, power), Color3.fromRGB(255, 130, 120))
		Effects.Burst(result.Position, Color3.fromRGB(190, 195, 210), 6)
		return result.Position
	end

	-- 직접 쏴서는 골드를 받지 않는다 (골드는 방치 수입 / 필드 / 던전에서): 허수아비는 대미지 / DPS 를 확인하는 연습용이다
	Quest.Add(player, "DummyHits", 1)
	local okDungeon, Dungeon = pcall(function() return require(script.Parent:WaitForChild("DungeonService")) end)
	if okDungeon then
		local damage, isCrit = Dungeon.ComputeDamage(player)
		Effects.DamageNumber(result.Position, damage, isCrit)
		showDps(model, data, player, damage)
		require(script.Parent:WaitForChild("DamageMeter")).Add(player, "Gun", damage)
		-- 세트 효과 시험
		local run = ensureAugRun(Dungeon)
		local body = model.PrimaryPart
		if run and body and run.Monsters[body] then
			lastDummyHit[player] = os.clock()
			Dungeon.AugOnHit(run, player, body, run.Monsters[body], damage, isCrit)
			hitCount[player] = (hitCount[player] or 0) + 1
			if hitCount[player] % 10 == 0 then Dungeon.AugOnKill(run, player, body.Position) end -- 처치 효과 보여 주기
		end
	end
	return result.Position
end

-- 휴식 구역: 훈련장과 따로 떨어진 아늑한 쉼터. 모닥불 + 통나무 의자 + 등불 + 푸른 원. 원 안에 서 있으면 방치 수입이 쌓이고, 접속을 꺼도 쌓인다.
function Dummy.BuildRest(position)
	restCenter = position
	local pad = newPart({
		Name = "RestGround", Size = Vector3.new(36, 0.3, 36), Position = position + Vector3.new(0, 0.15, 0),
		Color = Color3.fromRGB(80, 110, 85), Material = Enum.Material.Grass, CanCollide = false,
	}, folder)
	local ring = newPart({
		Name = "RestRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 30, 30),
		CFrame = CFrame.new(position + Vector3.new(0, 0.35, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(120, 210, 230), Material = Enum.Material.Neon, CanCollide = false, CanQuery = false, Transparency = 1,
	}, folder)

	-- 아늑한 캠프: 전부 고정 부품 (충돌 / 질의 / 접촉 없음, 그림자 없음). 모닥불 하나 + 은은한 등불 2개만 빛난다.
	local gy = position + Vector3.new(0, 0.3, 0)
	local function deco(name, size, cf, color, material, extra)
		local data = { Name = name, Size = size, CFrame = cf, Color = color, Material = material, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
		for key, value in pairs(extra or {}) do data[key] = value end
		return newPart(data, folder)
	end
	local function box(name, size, pos, color, material, yaw)
		return deco(name, size, CFrame.new(pos) * CFrame.Angles(0, yaw or 0, 0), color, material)
	end
	local function ball(name, diameter, pos, color, material, sizeY)
		return deco(name, Vector3.new(diameter, sizeY or diameter, diameter), CFrame.new(pos), color, material, { Shape = Enum.PartType.Ball })
	end
	local function pole(name, height, diameter, basePos, color, material)
		return deco(name, Vector3.new(height, diameter, diameter), CFrame.new(basePos + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, material, { Shape = Enum.PartType.Cylinder })
	end
	local wood, darkWood = Color3.fromRGB(120, 84, 54), Color3.fromRGB(84, 60, 42)
	local function around(radius, angle) return gy + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius) end

	-- 모닥불 자리: 흙 바닥 + 돌 고리 + 장작 + 불 + 삼각 걸이 냄비
	pole("CampDirt", 0.1, 15, gy, Color3.fromRGB(112, 90, 66), Enum.Material.Ground)
	for i = 1, 10 do
		local angle = i / 10 * math.pi * 2
		ball("FireStone", 1.5, position + Vector3.new(math.cos(angle) * 2.8, 0.65, math.sin(angle) * 2.8), Color3.fromRGB(116, 112, 106), Enum.Material.Slate, 1.1)
	end
	for i = 1, 3 do
		deco("Log", Vector3.new(0.7, 0.7, 3.6), CFrame.new(position + Vector3.new(0, 0.9, 0)) * CFrame.Angles(math.rad(14), math.rad(i * 60), 0), Color3.fromRGB(95, 62, 38), Enum.Material.Wood)
	end
	local flameBase = newPart({ Name = "RestFlame", Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 1.4, 1.4), Position = position + Vector3.new(0, 1.6, 0), Transparency = 1, CanCollide = false, CanQuery = false }, folder)
	restFire = Instance.new("Fire")
	restFire.Size = 8
	restFire.Heat = 6
	restFire.Parent = flameBase
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 170, 90)
	glow.Range = 22
	glow.Brightness = 1
	glow.Shadows = false
	glow.Parent = flameBase
	for i = 0, 2 do -- 삼각 걸이 + 냄비
		local angle = i / 3 * math.pi * 2 + 0.5
		deco("TripodLeg", Vector3.new(0.25, 4.6, 0.25), CFrame.lookAt(position + Vector3.new(math.cos(angle) * 1.3, 2.4, math.sin(angle) * 1.3), position + Vector3.new(0, 4.6, 0)) * CFrame.Angles(math.rad(90), 0, 0), darkWood, Enum.Material.Wood)
	end
	ball("CampPot", 1.5, position + Vector3.new(0, 3.1, 0), Color3.fromRGB(46, 44, 48), Enum.Material.Metal, 1.2)

	-- 통나무 의자 4개 (불을 둘러싼다) + 바닥 담요
	local blanketColors = { Color3.fromRGB(176, 88, 76), Color3.fromRGB(86, 120, 150), Color3.fromRGB(204, 164, 84), Color3.fromRGB(110, 140, 96) }
	for i = 1, 4 do
		local angle = i / 4 * math.pi * 2 + 0.4
		local seat = position + Vector3.new(math.cos(angle) * 7.5, 0.9, math.sin(angle) * 7.5)
		newPart({ Name = "LogSeat", Size = Vector3.new(4.4, 1.4, 1.6), CFrame = CFrame.lookAt(seat, position + Vector3.new(0, 0.9, 0)), Color = Color3.fromRGB(120, 82, 52), Material = Enum.Material.Wood, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }, folder)
		local blanketPos = around(10.6, angle + math.pi / 4) + Vector3.new(0, 0.05, 0)
		deco("Blanket", Vector3.new(3.2, 0.08, 2.2), CFrame.lookAt(blanketPos, position + Vector3.new(0, blanketPos.Y - position.Y, 0)), blanketColors[i], Enum.Material.Fabric)
	end

	-- 텐트 2개 (A자): 불 쪽으로 입구가 열려 있다
	for _, angle in ipairs({ math.rad(205), math.rad(250) }) do
		local tentPos = around(14.5, angle)
		local base = CFrame.lookAt(tentPos, Vector3.new(position.X, tentPos.Y, position.Z))
		local cloth = angle < math.rad(220) and Color3.fromRGB(196, 170, 120) or Color3.fromRGB(150, 98, 84)
		for _, side in ipairs({ -1, 1 }) do
			deco("TentPanel", Vector3.new(5, 0.2, 7), base * CFrame.new(side * 1.6, 1.9, 0) * CFrame.Angles(0, 0, -side * math.rad(50)), cloth, Enum.Material.Fabric)
		end
		deco("TentRidge", Vector3.new(0.3, 0.3, 7.6), base * CFrame.new(0, 3.85, 0), darkWood, Enum.Material.Wood)
		deco("TentBack", Vector3.new(3.4, 3.2, 0.2), base * CFrame.new(0, 1.6, 3.4), cloth:Lerp(Color3.fromRGB(60, 50, 44), 0.35), Enum.Material.Fabric)
		deco("TentDoor", Vector3.new(2.6, 3, 0.2), base * CFrame.new(0, 1.5, -3.4), Color3.fromRGB(46, 38, 36), Enum.Material.Fabric)
		for _, side in ipairs({ -1, 1 }) do
			deco("TentPole", Vector3.new(0.3, 4, 0.3), base * CFrame.new(side * 0.9, 2, -3.7) * CFrame.Angles(0, 0, side * math.rad(-10)), darkWood, Enum.Material.Wood)
		end
	end

	-- 비스듬한 처마 (기대어 세운 지붕) + 탁자
	do
		local leanPos = around(14.5, math.rad(120))
		local base = CFrame.lookAt(leanPos, Vector3.new(position.X, leanPos.Y, position.Z))
		for _, side in ipairs({ -1, 1 }) do
			pole("LeanPost", 5, 0.4, base:PointToWorldSpace(Vector3.new(side * 3.4, 0, -2.4)), wood, Enum.Material.Wood)
			pole("LeanPost", 3.4, 0.4, base:PointToWorldSpace(Vector3.new(side * 3.4, 0, 2.4)), wood, Enum.Material.Wood)
		end
		deco("LeanRoof", Vector3.new(8.4, 0.25, 6.6), base * CFrame.new(0, 4.5, 0) * CFrame.Angles(math.rad(-15), 0, 0), Color3.fromRGB(176, 88, 76), Enum.Material.Fabric)
		deco("LeanTable", Vector3.new(4.4, 0.4, 1.8), base * CFrame.new(0, 1.8, 0.4), wood, Enum.Material.WoodPlanks)
		for _, side in ipairs({ -1, 1 }) do
			deco("LeanTableLeg", Vector3.new(0.3, 1.6, 1.4), base * CFrame.new(side * 1.9, 1, 0.4), darkWood, Enum.Material.Wood)
		end
		ball("CampCup", 0.6, base:PointToWorldSpace(Vector3.new(-1, 2.3, 0.4)), Color3.fromRGB(220, 200, 170), Enum.Material.SmoothPlastic)
	end

	-- 해먹: 나무 두 그루 사이
	do
		local treeA, treeB = around(15.5, math.rad(300)), around(15.5, math.rad(335))
		for _, treePos in ipairs({ treeA, treeB }) do
			pole("CampTrunk", 8, 1.6, treePos, Color3.fromRGB(96, 68, 44), Enum.Material.Wood)
			ball("CampLeaves", 8, treePos + Vector3.new(0, 9, 0), Color3.fromRGB(88, 130, 82), Enum.Material.Grass, 6.5)
		end
		local mid = (treeA + treeB) / 2
		local span = (treeB - treeA)
		local yaw = math.atan2(-span.Z, span.X)
		deco("Hammock", Vector3.new(span.Magnitude * 0.5, 0.15, 2.2), CFrame.new(mid + Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, yaw, 0), Color3.fromRGB(190, 150, 96), Enum.Material.Fabric)
		for _, t in ipairs({ -1, 1 }) do
			deco("HammockRope", Vector3.new(span.Magnitude * 0.3, 0.1, 0.1), CFrame.new(mid + span.Unit * (t * span.Magnitude * 0.34) + Vector3.new(0, 3.2, 0)) * CFrame.Angles(0, yaw, t * math.rad(-20)), Color3.fromRGB(200, 188, 150), Enum.Material.Fabric)
		end
	end

	-- 등불 기둥 3개: 나무 기둥 + 종이등. 가로등이 아니라 낮은 캠프 등불이고, 둘만 아주 은은하게 빛난다.
	for i = 1, 3 do
		local lampPos = around(12.2, i / 3 * math.pi * 2 + 1.1)
		pole("CampPost", 3.6, 0.35, lampPos, darkWood, Enum.Material.Wood)
		box("CampArm", Vector3.new(0.9, 0.2, 0.2), lampPos + Vector3.new(0.4, 3.5, 0), darkWood, Enum.Material.Wood)
		local lantern = box("CampLantern", Vector3.new(0.9, 1.1, 0.9), lampPos + Vector3.new(0.8, 2.9, 0), Color3.fromRGB(236, 200, 140), Enum.Material.SmoothPlastic)
		if i <= 2 then
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 200, 130)
			light.Range = 12
			light.Brightness = 0.45
			light.Shadows = false
			light.Parent = lantern
		end
	end

	-- 상자 / 통 / 자루 / 돌 화덕 옆 장작 더미
	do
		local cratePos = around(14.5, math.rad(40))
		box("CampCrate", Vector3.new(2.4, 2.4, 2.4), cratePos + Vector3.new(0, 1.2, 0), wood, Enum.Material.Wood, 0.3)
		box("CampCrate", Vector3.new(2, 2, 2), cratePos + Vector3.new(2.8, 1, 0.4), darkWood, Enum.Material.Wood, -0.2)
		box("CampCrate", Vector3.new(1.8, 1.8, 1.8), cratePos + Vector3.new(0.4, 3.3, 0), darkWood, Enum.Material.Wood, 0.6)
		pole("CampBarrel", 2.6, 2.2, cratePos + Vector3.new(-2.8, 0, 0.6), Color3.fromRGB(122, 88, 58), Enum.Material.Wood)
		pole("CampBarrel", 2.6, 2.2, cratePos + Vector3.new(-1.4, 0, 3), Color3.fromRGB(110, 78, 52), Enum.Material.Wood)
		ball("CampSack", 2, cratePos + Vector3.new(3, 0.9, 2.8), Color3.fromRGB(196, 176, 134), Enum.Material.Fabric, 1.8)
		for k = 0, 2 do -- 장작 더미
			box("CampFirewood", Vector3.new(0.6, 0.6, 2.6), around(11.8, math.rad(85)) + Vector3.new(k * 0.7 - 0.7, 0.3, 0), Color3.fromRGB(100, 70, 44), Enum.Material.Wood, 1.57)
		end
	end

	-- 가장자리 덤불 / 꽃 / 모서리 나무
	for i = 0, 15 do
		if i % 4 ~= 1 then -- (입구 쪽 몇 군데는 비워 둔다)
			local angle = i / 16 * math.pi * 2 + 0.2
			ball("CampBush", 2.8 + (i % 3) * 0.5, around(17 + (i % 2) * 0.8, angle) + Vector3.new(0, 1, 0), Color3.fromRGB(80 + (i % 3) * 10, 124 + (i % 4) * 6, 78), Enum.Material.Grass, 2.2)
		end
	end
	local flowerColors = { Color3.fromRGB(230, 150, 160), Color3.fromRGB(240, 200, 110), Color3.fromRGB(200, 130, 180), Color3.fromRGB(236, 232, 220) }
	for i = 0, 7 do
		ball("CampFlower", 0.8, around(9 + (i % 3) * 1.8, i / 8 * math.pi * 2 + 0.9) + Vector3.new(0, 0.5, 0), flowerColors[i % 4 + 1], Enum.Material.SmoothPlastic)
	end
	for _, corner in ipairs({ Vector3.new(-16, 0, -16), Vector3.new(16, 0, -16), Vector3.new(-17, 0, 16) }) do
		pole("CampTrunk", 7, 1.6, gy + corner, Color3.fromRGB(96, 68, 44), Enum.Material.Wood)
		ball("CampLeaves", 8.5, gy + corner + Vector3.new(0, 8, 0), Color3.fromRGB(92, 136, 84), Enum.Material.Grass, 7)
	end

	-- 작은 나무 팻말 (오는 길인 남서쪽(마을 중앙 쪽)을 향한다)
	do
		local signPos = around(17.5, math.rad(139))
		pole("CampSignPost", 3.4, 0.5, signPos, darkWood, Enum.Material.Wood)
		local outward = Vector3.new(math.cos(math.rad(139)), 0, math.sin(math.rad(139)))
		local boardPos = signPos + Vector3.new(0, 3.6, 0)
		local board = deco("CampSignBoard", Vector3.new(5.2, 2.4, 0.3), CFrame.lookAt(boardPos, boardPos + outward), Color3.fromRGB(150, 108, 70), Enum.Material.WoodPlanks)
		local face = Instance.new("SurfaceGui")
		face.Face = Enum.NormalId.Front
		face.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		face.PixelsPerStud = 40
		face.LightInfluence = 0
		face.Parent = board
		local faceText = Instance.new("TextLabel")
		faceText.Size = UDim2.new(1, 0, 1, 0)
		faceText.BackgroundTransparency = 1
		faceText.Font = Enum.Font.GothamBlack
		faceText.TextScaled = true
		faceText.TextColor3 = Color3.fromRGB(255, 244, 214)
		faceText.TextStrokeTransparency = 0.3
		faceText.Text = "💤 Rest Zone"
		faceText.Parent = face
	end

	-- 안내판
	local signGui = Instance.new("BillboardGui")
	signGui.Size = UDim2.new(0, 340, 0, 92)
	signGui.StudsOffset = Vector3.new(0, 20, 0)
	signGui.MaxDistance = 140 -- 멀리서도 보인다 (예전엔 50: 가까이 가야 보여서 휴식 구역을 놓치기 쉬웠다)
	signGui.Parent = ring
	-- 멀리서 눈에 띄는 은은한 하늘색 빛기둥 (게이트 빛기둥과 같은 방식)
	local beam = newPart({
		Name = "RestBeam", Shape = Enum.PartType.Cylinder, Size = Vector3.new(70, 4, 4), CFrame = CFrame.new(position + Vector3.new(0, 35, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(120, 215, 235), Material = Enum.Material.Neon, Transparency = 0.86, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
	}, folder)
	beam.Name = "RestBeam"
	local signLabel = Instance.new("TextLabel")
	signLabel.Size = UDim2.new(1, 0, 0.62, 0)
	signLabel.BackgroundTransparency = 1
	signLabel.Font = Enum.Font.GothamBlack
	signLabel.TextScaled = true
	signLabel.TextColor3 = Color3.fromRGB(190, 240, 255)
	signLabel.TextStrokeTransparency = 0
	signLabel.Text = "💤 Rest Zone"
	signLabel.Parent = signGui
	local signSub = Instance.new("TextLabel")
	signSub.Size = UDim2.new(1, 0, 0.38, 0)
	signSub.Position = UDim2.new(0, 0, 0.62, 0)
	signSub.BackgroundTransparency = 1
	signSub.Font = Enum.Font.GothamBold
	signSub.TextScaled = true
	signSub.TextColor3 = Color3.fromRGB(255, 226, 120)
	signSub.TextStrokeTransparency = 0.2
	signSub.Text = "Stand here to earn gold"
	signSub.Parent = signGui
end

return Dummy
