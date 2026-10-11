-- LordShadowClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: LordShadowClient)
-- 필드 동쪽 끝(8구역 너머)에 서 있는 "최후의 군주"의 거대한 그림자. 설명 없이 목표가 보이게 한다.
--   · 1구역 입구에서는 안개 속의 희미한 윤곽 -> 동쪽으로 갈수록(또는 더 먼 구역을 열수록) 또렷해지고
--   · 중반부터 눈이 은은하게 붉게 깜빡이고, 후반에는 머리 뒤로 둥근 빛이 떠오른다.
-- 내 화면에만 있는 장식이다 (충돌 / 총알 판정 / 그림자 없음). 필드에 있을 때만 그려서 다른 곳에서는 비용이 없다.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local player = Players.LocalPlayer
local F = Config.Field

local TOP = 0.05
-- 군주가 실제로 서 있는 자리(마지막 구역 끝에서 더 동쪽). 너무 멀면 안개(Atmosphere)에 묻히거나 그려지지 않을 수 있어서,
-- 실제 부품은 "카메라 앞 REAL_R 거리"에 두고 진짜 거리에 비례해 작게 그린다 (멀리 있는 산을 하늘에 붙이는 방식). 가까이 갈수록 커지고 또렷해진다.
local ORIGIN = Vector3.new(F.ZoneEnd(F.ZoneCount) + 1100, TOP - 40, 0)
local REAL_R = 900
local BODY_COLOR = Color3.fromRGB(16, 14, 28)
local EYE_COLOR = Color3.fromRGB(190, 48, 56) -- 눈이 아프지 않게 짙은 붉은색

local folder = Instance.new("Folder")
folder.Name = "LordShadow"

local pieces = {} -- { Part, Size, Offset, Rotation }
local bodyParts, eyes, halo = {}, {}, nil

local function part(name, shape, size, offset, color, material, rotation)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Color = color
	p.Material = material
	p.Transparency = 1
	p.Parent = folder
	table.insert(pieces, { Part = p, Size = size, Offset = offset, Rotation = rotation or CFrame.new() })
	return p
end

do
	local B = Enum.PartType.Block
	local function body(name, shape, size, offset, rotation)
		table.insert(bodyParts, part(name, shape, size, offset, BODY_COLOR, Enum.Material.SmoothPlastic, rotation))
	end
	body("LegL", B, Vector3.new(120, 420, 150), Vector3.new(0, 210, -110))
	body("LegR", B, Vector3.new(120, 420, 150), Vector3.new(0, 210, 110))
	body("Robe", B, Vector3.new(210, 170, 430), Vector3.new(0, 480, 0))
	body("Torso", B, Vector3.new(190, 380, 340), Vector3.new(0, 750, 0))
	body("Shoulders", B, Vector3.new(220, 90, 660), Vector3.new(0, 930, 0))
	body("ArmL", B, Vector3.new(90, 470, 90), Vector3.new(0, 690, -350), CFrame.Angles(math.rad(8), 0, 0))
	body("ArmR", B, Vector3.new(90, 470, 90), Vector3.new(0, 690, 350), CFrame.Angles(math.rad(-8), 0, 0))
	body("SpikeL", B, Vector3.new(60, 200, 60), Vector3.new(0, 1020, -300), CFrame.Angles(math.rad(-18), 0, 0))
	body("SpikeR", B, Vector3.new(60, 200, 60), Vector3.new(0, 1020, 300), CFrame.Angles(math.rad(18), 0, 0))
	body("Head", Enum.PartType.Ball, Vector3.new(160, 160, 160), Vector3.new(0, 1070, 0))
	body("HornL", B, Vector3.new(34, 240, 34), Vector3.new(0, 1230, -80), CFrame.Angles(math.rad(-24), 0, 0))
	body("HornR", B, Vector3.new(34, 240, 34), Vector3.new(0, 1230, 80), CFrame.Angles(math.rad(24), 0, 0))
	for _, z in ipairs({ -38, 38 }) do -- 눈: 플레이어가 오는 서쪽(-X)을 향한다
		table.insert(eyes, part("Eye", B, Vector3.new(14, 18, 46), Vector3.new(-76, 1085, z), EYE_COLOR, Enum.Material.Neon))
	end
	halo = part("Halo", Enum.PartType.Cylinder, Vector3.new(6, 380, 380), Vector3.new(60, 1070, 0), EYE_COLOR, Enum.Material.Neon)
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local shown = false
local clock = 0
local lastScale = 0

-- 매 프레임: 카메라 앞에 놓고 진짜 거리에 맞춰 크기를 조절한다 (카메라가 움직여도 흔들리지 않게 렌더 단계에서)
RunService.RenderStepped:Connect(function(dt)
	clock += dt
	local inField = player:GetAttribute("Zone") == "Field" and not player:GetAttribute("InDoomArena")
	local camera = workspace.CurrentCamera
	if not inField or not camera then
		if shown then
			shown = false
			folder.Parent = nil
		end
		return
	end
	if not shown then
		shown = true
		lastScale = 0
		folder.Parent = workspace
	end
	local cam = camera.CFrame.Position
	local trueDistance = math.max(ORIGIN.X - cam.X, 300)
	local radius = math.min(REAL_R, trueDistance)
	local scale = radius / trueDistance
	local origin = cam + Vector3.new(radius, (ORIGIN.Y - cam.Y) * scale, (ORIGIN.Z - cam.Z) * scale)
	local resize = math.abs(scale - lastScale) > 0.003
	lastScale = resize and scale or lastScale
	for _, piece in ipairs(pieces) do
		if resize then piece.Part.Size = piece.Size * scale end
		piece.Part.CFrame = CFrame.new(origin + piece.Offset * scale) * piece.Rotation
	end
	-- 가까울수록 또렷하다: 지금 서 있는 위치 / 지금까지 열어 둔 가장 먼 구역 중 더 앞선 쪽
	local reach = (cam.X - F.StartX) / (F.ZoneEnd(F.ZoneCount) - F.StartX)
	local opened = (player:GetAttribute("MaxZone") or 0) / F.ZoneCount * 0.6
	local p = math.clamp(math.max(reach, opened), 0, 1)
	local bodyT = lerp(0.55, 0.1, p ^ 0.7) -- 처음부터 눈에 띄게 (멀리서도 윤곽이 보이도록 처음 투명도를 낮췄다)
	for _, b in ipairs(bodyParts) do
		b.Transparency = bodyT
	end
	local eyeStrength = math.clamp((p - 0.12) / 0.45, 0, 1)
	local eyeT = 1 - eyeStrength * (0.85 + 0.06 * math.sin(clock * 1.7))
	for _, e in ipairs(eyes) do
		e.Transparency = eyeT
	end
	halo.Transparency = 1 - math.clamp((p - 0.45) / 0.5, 0, 1) * 0.55
end)
