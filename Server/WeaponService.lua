-- WeaponService (ServerScriptService > Modules 안의 ModuleScript, 이름: WeaponService)
-- 무기(총) 종류(권총 / 샷건 / 저격총) + 강화 + 무기 외형 생성.
-- 무기는 서버에서 만들어 캐릭터에 장착하기 때문에 로비의 모든 플레이어에게 그대로 보인다.
-- 강화 레벨(WeaponLevel)이 오를수록 색상 / 크기 / 재질 / 파티클 / 궤적 / 빛이 달라진다.

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Config"))
local SoundBank = require(game:GetService("ReplicatedStorage"):WaitForChild("SoundBank"))
local Effects = require(script.Parent:WaitForChild("Effects"))
local Quest = require(script.Parent:WaitForChild("QuestService"))
local Event = require(script.Parent:WaitForChild("EventService"))

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Weapon = {}

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 60)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 220, 60)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(80, 255, 100)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(60, 220, 255)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(90, 90, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 255)),
})

local function weld(part0, part1)
	local w = Instance.new("WeldConstraint")
	w.Part0 = part0
	w.Part1 = part1
	w.Parent = part0
end

local function newPart(name, size, color, material, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- 레벨에 맞는 무기(Tool, 총)를 만든다. 총구 방향은 손잡이의 -Z (팔을 뻗은 방향).
-- 무기는 100종 모두 모양이 다르다: 종류별 몸체 + 시대별 장식 + 무기 번호마다 달라지는 추가 장식(번호가 클수록 많아진다)
local V = Vector3.new
local STEEL = Enum.Material.Metal
local NEON = Enum.Material.Neon

local Bodies = {}   -- 종류별 몸체: Bodies[종류](c)
local EraDecor = {} -- 시대별 장식: EraDecor[시대](c)
local Flair = {}    -- 무기마다 뽑혀서 붙는 추가 장식 목록

------------------ 종류별 몸체 (부품 10개 안팎. 종류마다 실루엣이 확 다르다) ------------------
Bodies.Pistol = function(c) -- 라이플 (Pistol = 라이플): 긴 핸드가드 + 개머리판 + (조준경 / 홀로 조준기 중 번호로 선택)
	local k = c.k
	c.add("Receiver", V(0.5 * k, 0.6 * k, 1.8), CFrame.new(0, 0.2, 0.1), c.steel, c.bodyMat)
	c.add("Handguard", V(0.6 * k, 0.6 * k, c.bl * 0.8), CFrame.new(0, 0.05, -(0.8 + c.bl * 0.4)), c.dark, STEEL)
	c.add("TopRail", V(0.2, 0.08, 1.9), CFrame.new(0, 0.62 * k, -0.9), c.steel, STEEL)
	if c.holo then
		c.add("HoloFrame", V(0.34, 0.3, 0.45), CFrame.new(0, 0.82 * k, -0.3), c.dark, STEEL)
		c.add("HoloGlass", V(0.28, 0.26, 0.04), CFrame.new(0, 0.88 * k, -0.54), c.accent(), NEON, { Transparency = 0.45 })
	else
		c.cyl("ScopeTube", 1.1, 0.34, CFrame.new(0, 0.85 * k, -0.35), c.dark, STEEL)
		c.cyl("ScopeLens", 0.06, 0.3, CFrame.new(0, 0.85 * k, -0.93), c.accent(), NEON)
		c.add("ScopeMount", V(0.18, 0.24, 0.16), CFrame.new(0, 0.68 * k, -0.3), c.dark, STEEL)
	end
	c.add("Magazine", V(0.3, 1.1, 0.5), CFrame.new(0, -0.95, 0.05) * CFrame.Angles(math.rad(14), 0, 0), c.dark, STEEL)
	c.add("Stock", V(0.42, 0.75, 1.5), CFrame.new(0, -0.05, 1.55) * CFrame.Angles(math.rad(-6), 0, 0), c.stockColor, c.stockMat)
	c.add("ButtPad", V(0.46, 0.8, 0.14), CFrame.new(0, -0.05, 2.35), c.dark, STEEL)
end

Bodies.Smg = function(c) -- 저격총 (Smg = 저격총): 아주 긴 총열 + 큰 조준경 + 접힌 양각대
	local k = c.k
	c.add("Receiver", V(0.5 * k, 0.55 * k, 1.7), CFrame.new(0, 0.2, 0.2), c.steel, c.bodyMat)
	c.cyl("Suppressor", 1.1, 0.46 * k, CFrame.new(0, 0.05, c.muzzleZ + 0.1), c.dark, STEEL)
	c.cyl("SuppRing", 0.06, 0.5 * k, CFrame.new(0, 0.05, c.muzzleZ + 0.4), c.accent(), NEON)
	c.cyl("ScopeTube", 1.6, 0.46, CFrame.new(0, 0.95 * k, -0.2), c.dark, STEEL)
	c.cyl("ScopeLens", 0.06, 0.42, CFrame.new(0, 0.95 * k, -1.02), c.accent(), NEON)
	c.add("ScopeMount", V(0.2, 0.34, 0.2), CFrame.new(0, 0.7 * k, -0.3), c.dark, STEEL)
	for i = -1, 1, 2 do
		c.add("Bipod" .. i, V(0.08, 0.9, 0.08), CFrame.new(i * 0.28, -0.35, -(0.9 + c.bl * 0.5)) * CFrame.Angles(math.rad(-65), 0, math.rad(i * 12)), c.dark, STEEL)
	end
	c.add("BoltKnob", V(0.2, 0.2, 0.2), CFrame.new(0.5 * k, 0.28, 0.55), c.accent(), NEON, { Shape = Enum.PartType.Ball })
	c.add("Stock", V(0.46, 0.8, 1.7), CFrame.new(0, -0.05, 1.7) * CFrame.Angles(math.rad(-5), 0, 0), c.stockColor, c.stockMat)
end

Bodies.Revolver = function(c) -- 폭탄: 손에 쥔 둥근 쇠 폭탄 + 타는 퓨즈 + 시대색 띠 (Revolver = 폭탄)
	local k = c.k
	c.hideBarrel, c.hideGrip, c.noTrim = true, true, true
	c.add("Bomb", V(1.5 * k, 1.5 * k, 1.5 * k), CFrame.new(0, 0.3, -0.85), c.dark, STEEL, { Shape = Enum.PartType.Ball })
	c.cyl("Band", 0.18, 1.56 * k, CFrame.new(0, 0.3, -0.85), c.accent(), NEON)
	c.cyl("BandB", 0.14, 1.34 * k, CFrame.new(0, 0.3, -0.85) * CFrame.Angles(0, 0, math.rad(90)), c.steel, STEEL)
	c.add("Cap", V(0.4 * k, 0.3 * k, 0.4 * k), CFrame.new(0, 0.3 + 0.78 * k, -0.85), c.steel, STEEL)
	c.add("Fuse", V(0.08, 0.7, 0.08), CFrame.new(0.1, 0.3 + 1.2 * k, -0.85) * CFrame.Angles(0, 0, math.rad(-22)), Color3.fromRGB(190, 160, 110), Enum.Material.Fabric)
	c.add("Spark", V(0.26, 0.26, 0.26), CFrame.new(0.3, 0.3 + 1.55 * k, -0.85), Color3.fromRGB(255, 190, 80), NEON, { Shape = Enum.PartType.Ball })
	c.add("Strap", V(0.5, 0.1, 0.5), CFrame.new(0, -0.45, -0.1), c.stockColor, c.stockMat)
end

Bodies.Rifle = function(c) -- 활: 세로로 선 활 + 팽팽한 시위 + 시위에 걸린 화살 (Rifle = 활)
	local k = math.min(c.k, 1.3) -- (활 / 석궁은 날개가 넓어서 너무 커지지 않게 상한)
	c.hideGrip, c.noTrim = true, true
	local z = -1.5 * k
	c.add("Riser", V(0.3 * k, 1.0 * k, 0.34 * k), CFrame.new(0, 0.05, z), c.stockColor, c.stockMat)
	c.add("Wrap", V(0.34 * k, 0.4 * k, 0.38 * k), CFrame.new(0, 0.05, z), c.accent(), NEON)
	for side = -1, 1, 2 do
		local a, b, d = Vector3.new(0, side * 0.5 * k, z), Vector3.new(0, side * 1.5 * k, z + 0.35 * k), Vector3.new(0, side * 2.3 * k, z - 0.15 * k)
		c.add("LimbIn" .. side, V(0.2 * k, 0.2 * k, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), c.steel, c.bodyMat)
		c.add("LimbOut" .. side, V(0.16 * k, 0.16 * k, (d - b).Magnitude), CFrame.lookAt((b + d) / 2, d), c.steel, c.bodyMat)
		c.add("Tip" .. side, V(0.22 * k, 0.22 * k, 0.22 * k), CFrame.new(d), c.accent(), NEON, { Shape = Enum.PartType.Ball })
		local nock = Vector3.new(0, 0.05, -0.6)
		c.add("String" .. side, V(0.045, 0.045, (nock - d).Magnitude), CFrame.lookAt((nock + d) / 2, d), Color3.fromRGB(235, 235, 245), Enum.Material.Fabric)
	end
end

Bodies.Shotgun = function(c) -- 수리검: 손 앞에 떠 있는 네 갈래 별 + 가운데 빛나는 구슬 (Shotgun = 수리검)
	local k = c.k
	c.hideBarrel, c.hideGrip, c.noTrim = true, true, true
	local at = CFrame.new(0, 0.3, -0.85)
	for i = 0, 1 do
		c.add("Blade" .. i, V(2.1 * k, 0.12, 0.5 * k), at * CFrame.Angles(0, 0, math.rad(i * 90)) * CFrame.Angles(math.rad(90), 0, 0), c.steel, STEEL)
	end
	for i = 0, 3 do -- 끝이 뾰족한 날 끝
		local a = math.rad(i * 90)
		c.add("Point" .. i, V(0.3 * k, 0.12, 0.3 * k), at * CFrame.Angles(0, 0, a) * CFrame.new(0, 1.15 * k, 0) * CFrame.Angles(math.rad(90), math.rad(45), 0), c.accent(), NEON)
	end
	c.add("Hub", V(0.62 * k, 0.62 * k, 0.62 * k), at, c.dark, STEEL, { Shape = Enum.PartType.Ball })
	c.add("Core", V(0.36 * k, 0.36 * k, 0.36 * k), at, c.accent(), NEON, { Shape = Enum.PartType.Ball })
	c.add("Cord", V(0.06, 0.06, 1.0), CFrame.new(0, -0.1, -0.1), c.stockColor, Enum.Material.Fabric)
end

Bodies.Flamer = function(c) -- 마도서: 펼친 마법책 + 빛나는 룬 + 떠 있는 불꽃 구슬 (Flamer = 마도서)
	local k = c.k
	c.hideBarrel, c.hideGrip, c.noTrim = true, true, true
	local at = CFrame.new(0, 0.4, -0.85)
	for side = -1, 1, 2 do
		c.add("Cover" .. side, V(1.15 * k, 0.1, 1.5 * k), at * CFrame.new(side * 0.58 * k, 0, 0) * CFrame.Angles(0, 0, math.rad(side * -14)), c.stockColor, c.stockMat)
		c.add("Page" .. side, V(1.0 * k, 0.1, 1.35 * k), at * CFrame.new(side * 0.56 * k, 0.1, 0) * CFrame.Angles(0, 0, math.rad(side * -14)), Color3.fromRGB(235, 228, 205), Enum.Material.Fabric)
		c.add("Rune" .. side, V(0.6 * k, 0.04, 0.6 * k), at * CFrame.new(side * 0.56 * k, 0.17, 0) * CFrame.Angles(0, 0, math.rad(side * -14)), c.accent(), NEON, { Transparency = 0.2 })
	end
	c.add("Spine", V(0.18 * k, 0.2 * k, 1.5 * k), at * CFrame.new(0, -0.08, 0), c.dark, STEEL)
	c.add("Flame", V(0.5 * k, 0.5 * k, 0.5 * k), at * CFrame.new(0, 0.85 * k, 0), c.accent(), NEON, { Shape = Enum.PartType.Ball })
	c.add("FlameShell", V(0.8 * k, 0.8 * k, 0.8 * k), at * CFrame.new(0, 0.85 * k, 0), c.accent(), NEON, { Shape = Enum.PartType.Ball, Transparency = 0.65 })
	c.add("Clasp", V(0.3, 0.3, 0.12), at * CFrame.new(0, 0.0, 0.75 * k), c.steel, STEEL)
end

Bodies.Cannon = function(c) -- 박격포: 굵은 짧은 포신 + 바닥판 + 두 다리 + 시위색 띠 + 포구에 얹은 포탄 (Cannon = 박격포)
	local k = c.k
	c.noTrim = true
	c.cyl("Tube", c.bl * 0.9, 0.78 * k * c.thick, CFrame.new(0, 0.05, -(0.7 + c.bl * 0.45)), c.dark, STEEL)
	c.cyl("MuzzleBand", 0.22, 0.98 * k * c.thick, CFrame.new(0, 0.05, c.muzzleZ + 0.1), c.accent(), NEON)
	c.cyl("MidBand", 0.16, 0.9 * k * c.thick, CFrame.new(0, 0.05, -(0.7 + c.bl * 0.5)), c.steel, STEEL)
	c.add("Plate", V(1.3 * k, 0.16, 1.3 * k), CFrame.new(0, -0.55, 0.45), c.steel, STEEL)
	for side = -1, 1, 2 do
		c.add("Leg" .. side, V(0.12, 1.1, 0.12), CFrame.new(side * 0.42 * k, -0.35, -(0.9 + c.bl * 0.55)) * CFrame.Angles(math.rad(-40), 0, math.rad(side * 14)), c.dark, STEEL)
	end
	c.add("Shell", V(0.62 * k, 0.62 * k, 0.62 * k), CFrame.new(0, 0.05, c.muzzleZ - 0.05), c.accent(), NEON, { Shape = Enum.PartType.Ball })
	c.add("Sight", V(0.14, 0.44, 0.14), CFrame.new(0.5 * k, 0.65 * k, -0.9), c.dark, STEEL)
end

Bodies.Sniper = function(c) -- 석궁: 긴 나무 몸체 + 가로로 휜 활 날개 + 팽팽한 시위 + 놓인 볼트 (Sniper = 석궁)
	local k = math.min(c.k, 1.3) -- (활 / 석궁은 날개가 넓어서 너무 커지지 않게 상한)
	c.noTrim = true
	c.add("Stock", V(0.42 * k, 0.4 * k, 2.8 * k), CFrame.new(0, 0.1, -0.3 * k), c.stockColor, c.stockMat)
	c.add("Rail", V(0.16, 0.12, 2.6 * k), CFrame.new(0, 0.38 * k, -0.4 * k), c.steel, STEEL)
	local zProd = -1.7 * k
	c.add("ProdMount", V(0.5 * k, 0.4 * k, 0.4 * k), CFrame.new(0, 0.1, zProd), c.dark, STEEL)
	for side = -1, 1, 2 do
		local a, b, d = Vector3.new(side * 0.25 * k, 0.1, zProd), Vector3.new(side * 1.5 * k, 0.1, zProd + 0.25 * k), Vector3.new(side * 2.4 * k, 0.1, zProd + 0.75 * k)
		c.add("ProdIn" .. side, V(0.2 * k, 0.2 * k, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), c.steel, c.bodyMat)
		c.add("ProdOut" .. side, V(0.16 * k, 0.16 * k, (d - b).Magnitude), CFrame.lookAt((b + d) / 2, d), c.steel, c.bodyMat)
		c.add("ProdTip" .. side, V(0.22 * k, 0.22 * k, 0.22 * k), CFrame.new(d), c.accent(), NEON, { Shape = Enum.PartType.Ball })
		local nock = Vector3.new(0, 0.38 * k, -0.2 * k)
		c.add("String" .. side, V(0.045, 0.045, (nock - d).Magnitude), CFrame.lookAt((nock + d) / 2, d), Color3.fromRGB(235, 235, 245), Enum.Material.Fabric)
	end
	c.add("Stirrup", V(0.5 * k, 0.1, 0.1), CFrame.new(0, 0.15, zProd - 0.35 * k), c.dark, STEEL)
	c.add("Scope", V(0.18, 0.18, 0.9), CFrame.new(0, 0.7 * k, 0.1), c.dark, STEEL)
	c.add("Trigger", V(0.06, 0.24, 0.06), CFrame.new(0, -0.25, 0.3) * CFrame.Angles(math.rad(15), 0, 0), c.accent(), NEON)
end

Bodies.Rocket = function(c) -- 굵은 발사관 + 빛나는 탄두 + 어깨받침
	local k = c.k
	c.cyl("Tube", c.bl * 1.2, 1.0 * k, CFrame.new(0, 0.1, -(0.4 + c.bl * 0.4)), c.dark, STEEL)
	c.cyl("TubeStripe", 0.16, 1.06 * k, CFrame.new(0, 0.1, -(0.4 + c.bl * 0.15)), c.accent(), NEON)
	c.cyl("Venturi", 0.8, 1.3 * k, CFrame.new(0, 0.1, 0.85), c.steel, c.bodyMat)
	c.cyl("VenturiGlow", 0.1, 0.9 * k, CFrame.new(0, 0.1, 1.28), Color3.fromRGB(255, 150, 60), NEON)
	c.add("Warhead", V(1.0 * k, 1.0 * k, 1.4 * k), CFrame.new(0, 0.1, c.muzzleZ - 0.25), c.accent(), NEON, { Shape = Enum.PartType.Ball })
	for i = 0, 1 do -- 십자 꼬리날개
		c.add("WarFin" .. i, V(0.08, 1.4 * k, 0.6), CFrame.new(0, 0.1, c.muzzleZ + 0.35) * CFrame.Angles(0, 0, math.rad(i * 90)), c.steel, STEEL)
	end
	c.add("ShoulderPad", V(0.9 * k, 0.3, 1.0), CFrame.new(0, -0.55 * k, 0.5), Color3.fromRGB(75, 60, 50), Enum.Material.Leather)
	c.add("Handle0", V(0.12, 0.7, 0.12), CFrame.new(0, -0.7, -0.1), c.dark, STEEL)
	c.add("Sight", V(0.14, 0.4, 0.14), CFrame.new(0.55 * k, 0.65 * k, -0.4), c.dark, STEEL)
end

Bodies.Rail = function(c) -- 지팡이: 긴 지팡이 + 윗머리의 빛나는 수정 + 떠 있는 고리 (Rail = 지팡이)
	local k = c.k
	c.hideGrip, c.noTrim = true, true
	local top = -(0.7 + c.bl)
	c.cyl("Wrap", 0.5, 0.42, CFrame.new(0, 0.05, -0.6), c.accent(), NEON)
	c.add("Gem", V(0.8 * k, 0.8 * k, 0.8 * k), CFrame.new(0, 0.05, top - 0.15), c.accent(), NEON, { Shape = Enum.PartType.Ball })
	c.add("GemShell", V(1.15 * k, 1.15 * k, 1.15 * k), CFrame.new(0, 0.05, top - 0.15), Color3.fromRGB(215, 235, 255), Enum.Material.Glass, { Shape = Enum.PartType.Ball, Transparency = 0.6 })
	for i = 0, 3 do -- 수정을 감싼 네 개의 발톱
		local a = math.rad(i * 90 + 45)
		c.add("Claw" .. i, V(0.12, 0.12, 0.8 * k), CFrame.new(math.cos(a) * 0.38 * k, 0.05 + math.sin(a) * 0.38 * k, top + 0.1) * CFrame.Angles(math.rad(math.sin(a) * 14), math.rad(-math.cos(a) * 14), 0), c.steel, STEEL)
	end
	c.cyl("Halo", 0.08, 1.6 * k, CFrame.new(0, 0.05, top - 0.15) * CFrame.Angles(0, math.rad(90), 0), c.accent(), NEON, { Transparency = 0.35 })
	c.add("Butt", V(0.32, 0.32, 0.4), CFrame.new(0, 0.05, 0.55), c.steel, STEEL)
end

------------------ 시대별 장식 (가장 눈에 띄는 것부터. 부품 예산이 차면 뒤쪽은 생략된다) ------------------
EraDecor[1] = function(c) -- 녹슨: 테이프 + 녹 얼룩
	c.cyl("Tape", 0.2, 0.7, CFrame.new(0, 0.05, 0.3), Color3.fromRGB(60, 60, 60), Enum.Material.Fabric)
	for i = 1, 3 do
		c.add("Rust" .. i, V(0.12 + c.rng:NextNumber() * 0.2, 0.1, 0.2 + c.rng:NextNumber() * 0.3), CFrame.new((c.rng:NextNumber() - 0.5) * 0.5, 0.35 + c.rng:NextNumber() * 0.2, c.rng:NextNumber(-1.2, 0.8)), Color3.fromRGB(150, 80, 40), Enum.Material.CorrodedMetal)
	end
end
EraDecor[2] = function(c) -- 강철: 푸른 줄무늬 + 새긴 줄
	c.add("BlueStripe", V(0.56, 0.08, 1.4), CFrame.new(0, 0.48, -0.2), Color3.fromRGB(70, 130, 230), NEON)
	for i = 0, 1 do c.add("Engrave" .. i, V(0.58, 0.04, 0.05), CFrame.new(0, 0.2, -0.4 + i * 0.5), Color3.fromRGB(215, 225, 240), STEEL) end
end
EraDecor[3] = function(c) -- 마력: 룬 고리 + 떠 있는 마법석
	c.cyl("RuneRing", 0.08, 1.3, CFrame.new(0, 0.2, 0.0), c.accent(), NEON, { Transparency = 0.35 })
	for i = 1, 3 do
		local a = i / 3 * math.pi * 2
		c.add("Crystal" .. i, V(0.28, 0.4, 0.28), CFrame.new(math.cos(a) * 0.55, 0.9 + math.sin(a) * 0.15, -0.2 + math.sin(a) * 0.5) * CFrame.Angles(math.rad(35), math.rad(i * 40), math.rad(25)), c.accent(), NEON, { Transparency = 0.15 })
	end
end
EraDecor[4] = function(c) -- 황금: 금도금 + 보석 + 장식 소용돌이
	c.add("GoldPlate", V(0.6, 0.5, 1.2), CFrame.new(0, 0.1, 0.15), Color3.fromRGB(255, 205, 70), STEEL)
	c.add("Gem", V(0.28, 0.28, 0.28), CFrame.new(0, 0.62, 0.35), Color3.fromRGB(255, 70, 90), NEON, { Shape = Enum.PartType.Ball })
	for i = -1, 1, 2 do
		c.add("Scroll" .. i, V(0.08, 0.5, 0.5), CFrame.new(i * 0.34, 0.15, 0.0) * CFrame.Angles(math.rad(25), 0, 0), Color3.fromRGB(255, 225, 120), STEEL)
	end
end
EraDecor[5] = function(c) -- 불꽃: 불꽃 지느러미 + 타오르는 통풍구
	for i = 0, 2 do
		c.add("FlameFin" .. i, V(0.1, 0.5 + i * 0.12, 0.5), CFrame.new(0, 0.7, 0.5 - i * 0.55) * CFrame.Angles(math.rad(-20), 0, 0), Color3.fromRGB(255, 110, 40), NEON, { Transparency = 0.1 })
	end
	for i = -1, 1, 2 do c.add("Ember" .. i, V(0.12, 0.12, 0.8), CFrame.new(i * 0.32, 0.0, -0.6), Color3.fromRGB(255, 200, 80), NEON) end
end
EraDecor[6] = function(c) -- 빙결: 서리 껍데기 + 얼음 가시
	c.add("Frost", V(0.62, 0.4, 1.3), CFrame.new(0, 0.1, 0.1), Color3.fromRGB(215, 240, 255), Enum.Material.Ice, { Transparency = 0.55 })
	for i = 0, 2 do
		c.add("IceSpike" .. i, V(0.14, 0.14, 0.9 - i * 0.12), CFrame.new((i % 2 == 0 and 1 or -1) * 0.3, 0.3 + (i // 2) * 0.35, -0.2 - i * 0.35) * CFrame.Angles(math.rad(-15), math.rad((i % 2 == 0 and 1 or -1) * 12), math.rad((i % 2 == 0 and 1 or -1) * 25)), Color3.fromRGB(190, 235, 255), Enum.Material.Ice, { Transparency = 0.2 })
	end
end
EraDecor[7] = function(c) -- 번개: 코일 + 지그재그 번개
	c.cyl("Coil", 0.5, 0.8, CFrame.new(0, 0.05, 0.9), Color3.fromRGB(255, 240, 90), NEON, { Transparency = 0.3 })
	for i = 0, 2 do
		c.add("Bolt" .. i, V(0.08, 0.08, 0.5), CFrame.new((i % 2 == 0 and 0.3 or -0.3), 0.55, -0.9 + i * 0.5) * CFrame.Angles(0, math.rad(i % 2 == 0 and 35 or -35), 0), Color3.fromRGB(255, 245, 120), NEON)
	end
end
EraDecor[8] = function(c) -- 암흑: 허공 구슬 + 검은 촉수 + 떠다니는 조각
	c.add("VoidOrb", V(0.5, 0.5, 0.5), CFrame.new(0, 0.9, 0.2), Color3.fromRGB(20, 5, 40), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball })
	c.add("VoidGlow", V(0.7, 0.7, 0.7), CFrame.new(0, 0.9, 0.2), Color3.fromRGB(160, 70, 255), NEON, { Shape = Enum.PartType.Ball, Transparency = 0.7 })
	for i = 1, 2 do
		local a = i / 2 * math.pi * 2
		c.add("Tendril" .. i, V(0.1, 0.1, 0.9), CFrame.new(math.cos(a) * 0.4, 0.1 + math.sin(a) * 0.4, 0.9) * CFrame.Angles(math.rad(math.sin(a) * 40), math.rad(math.cos(a) * 40), 0), Color3.fromRGB(35, 12, 55), STEEL)
	end
	for i = 1, 2 do c.add("Shard" .. i, V(0.14, 0.34, 0.14), CFrame.new(c.rng:NextNumber(-0.7, 0.7), c.rng:NextNumber(0.6, 1.3), c.rng:NextNumber(-1, 0.8)) * CFrame.Angles(c.rng:NextNumber(0, 3), c.rng:NextNumber(0, 3), 0), Color3.fromRGB(150, 70, 230), NEON) end
end
EraDecor[9] = function(c) -- 용: 뿔 + 눈 보석 + 비늘
	for i = -1, 1, 2 do
		c.add("DragonHorn" .. i, V(0.14, 0.9, 0.14), CFrame.new(i * 0.28, 0.6, -0.3) * CFrame.Angles(math.rad(-35), 0, math.rad(i * -18)), Color3.fromRGB(235, 220, 195), Enum.Material.SmoothPlastic)
	end
	c.add("DragonEye", V(0.3, 0.3, 0.3), CFrame.new(0, 0.35, -0.5), Color3.fromRGB(255, 190, 60), NEON, { Shape = Enum.PartType.Ball })
	for i = 0, 3 do
		c.add("Scale" .. i, V(0.5, 0.1, 0.34), CFrame.new(0, 0.62, 0.9 - i * 0.5) * CFrame.Angles(math.rad(-12), 0, 0), Color3.fromRGB(170, 40, 30), STEEL)
	end
end
EraDecor[10] = function(c) -- 신화: 후광 + 날개 + 떠 있는 별 (전설)
	c.cyl("Halo", 0.08, 1.8, CFrame.new(0, 1.0, 0.1) * CFrame.Angles(math.rad(90), 0, 0), Color3.new(1, 1, 1), NEON, { Transparency = 0.2 })
	for i = -1, 1, 2 do
		for k = 0, 1 do
			c.add("Wing" .. i .. k, V(0.06, 0.2, 0.9 - k * 0.25), CFrame.new(i * (0.5 + k * 0.22), 0.5 + k * 0.12, 0.7) * CFrame.Angles(0, 0, math.rad(i * (-25 - k * 12))), c.accent(), NEON, { Transparency = 0.1 })
		end
	end
	for i = 1, 3 do
		local a = i / 3 * math.pi * 2
		c.add("Star" .. i, V(0.2, 0.2, 0.2), CFrame.new(math.cos(a) * 0.9, 1.0, 0.1 + math.sin(a) * 0.9), c.accent(), NEON, { Shape = Enum.PartType.Ball })
	end
end

------------------ 고급 무기 공통 장식 (시대 / 번호로 정해진다) ------------------
-- 에너지 셀(5시대~) / 쌍열 보조 총열(번호가 3의 배수, 3시대~) / 총열을 감싼 떠 있는 고리(7시대~) / 전설 무기(91번~)의 빛나는 심지
local function addTrim(c)
	local side = (c.index % 2 == 0) and 1 or -1
	if c.era >= 5 then
		c.add("EnergyCell", V(0.22, 0.32, 0.5), CFrame.new(side * 0.34, 0.0, 0.3), c.accent(), NEON)
	end
	if c.era >= 3 and c.index % 3 == 0 then
		c.add("TwinBarrel", V(0.14, 0.14, c.bl * 0.8), CFrame.new(-side * 0.3 * c.k, 0.32, -(0.7 + c.bl * 0.45)), c.dark, STEEL)
	end
	if c.era >= 7 then
		c.cyl("FloatRing", 0.06, 1.1 + (c.index % 3) * 0.2, CFrame.new(0, 0.05, -(0.7 + c.bl * (0.45 + (c.index % 4) * 0.1))), c.accent(), NEON, { Transparency = 0.4 })
	end
	if c.index >= 91 then
		c.add("LegendCore", V(0.3, 0.3, 0.3), CFrame.new(0, 0.05, -0.2), Color3.new(1, 1, 1), NEON, { Shape = Enum.PartType.Ball, Transparency = 0.2 })
	end
end

------------------ 무기마다 달라지는 추가 장식 (번호가 클수록 많이 붙는다. 부품 예산이 남을 때만) ------------------
Flair[1] = function(c) c.add("SideRailL", V(0.08, 0.14, 1.0), CFrame.new(-0.34, 0.25, -0.2), c.accent(), NEON) end
Flair[2] = function(c) c.add("SideRailR", V(0.08, 0.14, 1.0), CFrame.new(0.34, 0.25, -0.2), c.accent(), NEON) end
Flair[3] = function(c) c.cyl("BarrelBand", 0.18, 0.5 * c.k, CFrame.new(0, 0.05, -(0.7 + c.bl * 0.35)), c.accent(), NEON) end
Flair[4] = function(c)
	c.add("Blade", V(0.06, 0.2, 0.9), CFrame.new(0, -0.28, c.muzzleZ + 0.1), Color3.fromRGB(220, 230, 240), STEEL)
	c.add("BladeEdge", V(0.07, 0.06, 0.9), CFrame.new(0, -0.38, c.muzzleZ + 0.1), c.accent(), NEON)
end
Flair[5] = function(c)
	for i = -1, 1, 2 do c.add("Wing" .. i, V(0.06, 0.35, 0.7), CFrame.new(i * 0.4, 0.35, 0.3) * CFrame.Angles(0, 0, math.rad(i * -30)), c.steel, STEEL) end
end
Flair[6] = function(c) c.add("TopGem", V(0.2, 0.2, 0.2), CFrame.new(0, 0.8, c.rng:NextNumber(-0.6, 0.4)), c.accent(), NEON, { Shape = Enum.PartType.Ball }) end
Flair[7] = function(c)
	for i = 0, 2 do c.add("Vent" .. i, V(0.5, 0.05, 0.12), CFrame.new(0, 0.3, 0.9 - i * 0.2), c.accent(), NEON) end
end
Flair[8] = function(c) c.cyl("HeatSink", 0.9, 0.62 * c.k, CFrame.new(0, 0.05, -(0.8 + c.bl * 0.25)), c.dark, STEEL) end
Flair[9] = function(c)
	c.add("Tassel", V(0.06, 0.7, 0.06), CFrame.new(0.3, -0.5, 0.3), c.accent(), Enum.Material.Fabric)
	c.add("TasselKnot", V(0.14, 0.14, 0.14), CFrame.new(0.3, -0.18, 0.3), c.dark, STEEL, { Shape = Enum.PartType.Ball })
end
Flair[10] = function(c)
	c.cyl("StripeA", 0.1, 0.58 * c.k, CFrame.new(0, 0.05, -(0.7 + c.bl * 0.7)), c.steel, STEEL)
	c.cyl("StripeB", 0.1, 0.58 * c.k, CFrame.new(0, 0.05, -(0.7 + c.bl * 0.85)), c.accent(), NEON)
end

-- 시대별 외형표: steel(몸체 금속색, nil 이면 시대색을 섞음) / dark(어두운 부품) / mat(몸체 재질) / stock(개머리판 색, 재질)
local ERA_STYLE = {
	{ steel = Color3.fromRGB(135, 115, 105), dark = Color3.fromRGB(50, 40, 35), mat = Enum.Material.CorrodedMetal, stock = Color3.fromRGB(80, 55, 38), stockMat = Enum.Material.Wood },
	{ steel = Color3.fromRGB(190, 200, 215), dark = Color3.fromRGB(40, 45, 60), mat = STEEL, stock = Color3.fromRGB(70, 60, 55), stockMat = Enum.Material.Wood },
	{ dark = Color3.fromRGB(45, 30, 70), mat = STEEL, stock = Color3.fromRGB(60, 40, 90), stockMat = Enum.Material.SmoothPlastic },
	{ steel = Color3.fromRGB(255, 215, 100), dark = Color3.fromRGB(60, 45, 20), mat = STEEL, stock = Color3.fromRGB(120, 80, 30), stockMat = Enum.Material.Wood },
	{ steel = Color3.fromRGB(95, 60, 55), dark = Color3.fromRGB(40, 20, 15), mat = STEEL, stock = Color3.fromRGB(70, 35, 28), stockMat = Enum.Material.Metal },
	{ steel = Color3.fromRGB(215, 238, 255), dark = Color3.fromRGB(35, 60, 90), mat = Enum.Material.Ice, stock = Color3.fromRGB(150, 200, 235), stockMat = Enum.Material.Ice },
	{ steel = Color3.fromRGB(70, 70, 85), dark = Color3.fromRGB(25, 25, 35), mat = STEEL, stock = Color3.fromRGB(40, 40, 55), stockMat = STEEL },
	{ steel = Color3.fromRGB(50, 28, 75), dark = Color3.fromRGB(15, 8, 25), mat = Enum.Material.SmoothPlastic, stock = Color3.fromRGB(30, 15, 45), stockMat = Enum.Material.SmoothPlastic },
	{ steel = Color3.fromRGB(150, 45, 35), dark = Color3.fromRGB(40, 15, 12), mat = STEEL, stock = Color3.fromRGB(95, 30, 25), stockMat = STEEL },
	{ steel = Color3.fromRGB(245, 245, 255), dark = Color3.fromRGB(60, 50, 90), mat = STEEL, stock = Color3.fromRGB(230, 220, 255), stockMat = Enum.Material.SmoothPlastic },
}
local PART_BUDGET = 20 -- 손잡이 / 그립 / 총열 외에 붙이는 장식 부품 수의 상한 (가벼운 무기 모델 유지)

local function buildTool(level, typeKey)
	typeKey = Config.ResolveWeaponType(level, typeKey)
	local tier = Config.GetLookTier(level, typeKey) -- 고른 무기 형 + 지금 시대의 외모
	local scale = Config.GetWeaponScale(level)
	local weaponType = Config.WeaponTypes[typeKey] or Config.WeaponTypes.Pistol
	local thick = weaponType.BarrelThickness
	local barrelLength = 1.8 * scale * weaponType.BarrelLength
	local colorSeq = tier.Rainbow and RAINBOW or ColorSequence.new(tier.Color)
	-- 시대별 색 구성: 녹슨 -> 강철 -> 마력 -> 황금 -> 불꽃 -> 빙결 -> 번개 -> 암흑 -> 용 -> 신화
	local style = ERA_STYLE[tier.Era] or ERA_STYLE[2]
	local dark = style.dark

	local tool = Instance.new("Tool")
	tool.Name = "Weapon"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ToolTip = Config.FormatWeapon(level, typeKey)

	-- 몸체(손에 쥐는 부분) + 손잡이 그립
	local handle = newPart("Handle", V(0.4, 0.6, 1.4), dark, STEEL, tool)
	local grip = newPart("Grip", V(0.35, 0.9, 0.4), style.stock, style.stockMat, tool)
	grip.CFrame = handle.CFrame * CFrame.new(0, -0.7, 0.4) * CFrame.Angles(math.rad(-12), 0, 0)
	weld(handle, grip)

	-- 총열: 강화할수록 길어지고 색/재질이 변함 (빛나는 시대는 총열이 빛난다)
	local barrel = newPart("Barrel", V(0.3 * scale * thick, 0.3 * scale * thick, barrelLength), tier.Color, tier.Material, tool)
	barrel.CFrame = handle.CFrame * CFrame.new(0, 0.05, -(0.7 + barrelLength / 2))
	weld(handle, barrel)

	-- 장식을 붙이는 도구 모음
	local rng = Random.new(tier.Index * 7919 + 13)
	local c = {
		tool = tool, handle = handle, barrel = barrel, tier = tier, rng = rng, dark = dark, thick = thick, bl = barrelLength,
		k = math.min(scale, 1.7), muzzleZ = -(0.7 + barrelLength), index = tier.Index, era = tier.Era,
		steel = style.steel or tier.Color:Lerp(Color3.fromRGB(195, 200, 210), 0.6),
		bodyMat = style.mat, stockColor = style.stock, stockMat = style.stockMat,
		used = 0,
		holo = tier.Era >= 4 and tier.Index % 2 == 0, -- 홀로그램 조준기 / 일반 조준경 중 번호로 선택
	}
	function c.accent()
		if tier.Rainbow then return Color3.fromHSV(rng:NextNumber(), 0.75, 1) end
		return tier.Color
	end
	function c.add(name, size, offset, color, material, extra)
		if c.used >= PART_BUDGET then return nil end -- 예산이 차면 생략 (뒤쪽 장식이 먼저 사라진다)
		c.used += 1
		local part = newPart(name, size, color, material or STEEL, tool)
		if extra and extra.Shape then part.Shape = extra.Shape end
		if extra and extra.Transparency then part.Transparency = extra.Transparency end
		part.CFrame = handle.CFrame * offset
		weld(handle, part)
		return part
	end
	function c.cyl(name, length, diameter, offset, color, material, extra)
		local data = { Shape = Enum.PartType.Cylinder, Transparency = extra and extra.Transparency }
		return c.add(name, V(length, diameter, diameter), offset * CFrame.Angles(0, math.rad(90), 0), color, material, data)
	end

	local body = Bodies[typeKey] or Bodies.Pistol
	body(c)
	if c.hideGrip then grip.Transparency = 1 end -- (총 손잡이가 필요 없는 무기: 활 / 수리검 / 폭탄 / 마도서 / 지팡이)
	if c.hideBarrel then barrel.Transparency = 1 end
	-- 강화 단계가 오를수록 총열에 빛나는 링이 하나씩 늘어난다 (최대 3개, 부품 예산 안에서 먼저 확보)
	local stage = Config.GetWeaponStage(level)
	for i = 1, (c.hideBarrel and 0 or math.min(stage, 3)) do
		local ringPart = c.cyl("StageRing" .. i, 0.14, 0.62 * scale * thick, CFrame.new(0, 0.05, -(0.7 + barrelLength * (0.08 + 0.84 * i / 4))), tier.Color, NEON)
		if ringPart then ringPart.Name = "StageRing" .. i end
	end
	if EraDecor[tier.Era] then EraDecor[tier.Era](c) end
	if not c.noTrim then addTrim(c) end -- (에너지 셀 / 쌍열 총열은 총 전용)
	-- 무기 번호마다 다른 추가 장식: 번호로 고른 조합이라 100종이 전부 다르고, 번호가 클수록 장식이 많아진다
	local extras = math.min(2 + tier.Index // 12, 9)
	local chosen = {}
	for i = 1, extras do
		local pick = (tier.Index * (i * 3 + 1) + i * 5) % #Flair + 1
		if not chosen[pick] then
			chosen[pick] = true
			Flair[pick](c)
		end
	end

	local tip = Instance.new("Attachment")
	tip.Name = "Tip"
	tip.Position = Vector3.new(0, 0, -barrelLength / 2)
	tip.Parent = barrel

	local base = Instance.new("Attachment")
	base.Name = "Base"
	base.Position = Vector3.new(0, 0, barrelLength / 2)
	base.Parent = barrel

	-- 총구 화염 (발사할 때 Weapon.PlayShot 에서 잠깐 터짐)
	local muzzle = Instance.new("ParticleEmitter")
	muzzle.Name = "Muzzle"
	muzzle.Rate = 0
	muzzle.Lifetime = NumberRange.new(0.06, 0.12)
	muzzle.Speed = NumberRange.new(4, 10)
	muzzle.SpreadAngle = Vector2.new(25, 25)
	muzzle.EmissionDirection = Enum.NormalId.Front
	muzzle.LightEmission = 1
	muzzle.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9 * scale),
		NumberSequenceKeypoint.new(1, 0),
	})
	muzzle.Color = colorSeq
	muzzle.Parent = tip

	local flash = Instance.new("PointLight")
	flash.Name = "MuzzleLight"
	flash.Enabled = false
	flash.Range = 12
	flash.Brightness = 3
	flash.Color = tier.Rainbow and Color3.fromRGB(255, 255, 255) or tier.Color
	flash.Parent = tip

	if tier.Particles > 0 then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Sparkle"
		emitter.Rate = math.min(tier.Particles, 30)
		emitter.Lifetime = NumberRange.new(0.4, 0.9)
		emitter.Speed = NumberRange.new(0.5, 2)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Shape = Enum.ParticleEmitterShape.Box
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3 * scale),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.LightEmission = 1
		emitter.Color = colorSeq
		emitter.Parent = barrel
	end

	if tier.Trail then
		local trail = Instance.new("Trail")
		trail.Attachment0 = base
		trail.Attachment1 = tip
		trail.Lifetime = 0.4
		trail.Color = colorSeq
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.LightEmission = 1
		trail.FaceCamera = true
		trail.Parent = barrel
	end

	if tier.Light > 0 then
		local light = Instance.new("PointLight")
		light.Range = tier.Light
		light.Brightness = 1.5
		light.Color = tier.Rainbow and Color3.fromRGB(255, 255, 255) or tier.Color
		light.Parent = barrel
	end

	return tool
end

------------------------------------------------------------
-- 머리 위 이름표: 이름 + 무기 강화 레벨 (다른 플레이어에게 과시)
------------------------------------------------------------
local function updateNameplate(player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then return end

	local gui = head:FindFirstChild("Nameplate")
	if not gui then
		gui = Instance.new("BillboardGui")
		gui.Name = "Nameplate"
		gui.Size = UDim2.new(0, 190, 0, 42)
		gui.StudsOffset = Vector3.new(0, 4.4, 0) -- 머리 위로 높이 (총 / 조준점과 겹치지 않게)
		gui.MaxDistance = 70
		gui.Parent = head

		local function addLabel(name, y, height, font)
			local label = Instance.new("TextLabel")
			label.Name = name
			label.Size = UDim2.new(1, 0, height, 0)
			label.Position = UDim2.new(0, 0, y, 0)
			label.BackgroundTransparency = 1
			label.Font = font
			label.TextScaled = true
			label.TextColor3 = Color3.new(1, 1, 1)
			label.TextStrokeTransparency = 0.3
			label.Parent = gui
		end
		-- 머리 위에는 이름과 전투력만 (무기 / 구역 기록은 메뉴에서 본다)
		addLabel("PlayerName", 0, 0.45, Enum.Font.GothamBold)
		addLabel("Power", 0.45, 0.55, Enum.Font.GothamBlack)
	end

	local inParty = (player:GetAttribute("PartyId") or 0) ~= 0

	local title = player:GetAttribute("Title") or ""
	gui.PlayerName.Text = (inParty and "[Party] " or "") .. (title ~= "" and ("『" .. title .. "』 ") or "") .. player.DisplayName
	gui.Power.Text = string.format("⚡ Power %d", player:GetAttribute("Power") or 0)
	gui.Power.TextColor3 = Color3.fromRGB(255, 225, 110)
end

Weapon.UpdateNameplate = updateNameplate

------------------------------------------------------------
-- 진화 미리보기: 종류 x 단계별 총 모델을 ReplicatedStorage.WeaponPreviews 에 만들어 둔다
-- (클라이언트가 복제해서 강화창 / 무기 탭의 3D 미리보기에 쓴다. 이름: <종류>_<단계번호>)
------------------------------------------------------------
function Weapon.BuildPreviews()
	local rs = game:GetService("ReplicatedStorage")
	local old = rs:FindFirstChild("WeaponPreviews")
	if old then old:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = "WeaponPreviews"
	do
		for index, tier in ipairs(Config.Weapon.Tiers) do
			local tool = buildTool(Config.Weapon.Tiers[(tier.Era - 1) * #Config.WeaponTypes.Order + 1].MinLevel, tier.Class) -- 그 시대가 시작되는 단계 (그 시대의 외모)
			local model = Instance.new("Model")
			model.Name = "W" .. index
			for _, child in ipairs(tool:GetChildren()) do
				child.Parent = model
			end
			model.PrimaryPart = model:FindFirstChild("Handle")
			tool:Destroy()
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = true
				elseif d:IsA("PointLight") then
					d:Destroy()
				end
			end
			model.Parent = folder
		end
	end
	folder.Parent = rs
end

------------------------------------------------------------
-- 장착 / 갱신
------------------------------------------------------------
function Weapon.Attach(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local old = character:FindFirstChild("Weapon")
	if old then
		old:Destroy()
	end

	local tool = buildTool(player:GetAttribute("WeaponLevel") or 0, player:GetAttribute("WeaponType") or "Pistol")
	humanoid:EquipTool(tool)
end

function Weapon.Refresh(player)
	Weapon.Attach(player)
	updateNameplate(player)
end

function Weapon.GetTipPosition(player)
	local character = player.Character
	local tool = character and character:FindFirstChild("Weapon")
	local barrel = tool and tool:FindFirstChild("Barrel")
	local tip = barrel and barrel:FindFirstChild("Tip")
	return tip and tip.WorldPosition or nil
end

-- 사운드 재생 (ID가 0이면 아무것도 안 함)
local function playSoundAt(parent, soundId, volume, pitch, name)
	if not soundId or soundId == 0 then return end
	local sound = Instance.new("Sound")
	sound.Name = name or "Sfx" -- 총소리는 "GunShot": 클라이언트가 이 이름을 보고 내 설정 볼륨을 적용한다
	sound.SoundId = "rbxassetid://" .. soundId
	sound.Volume = volume
	sound.PlaybackSpeed = pitch or 1
	sound.RollOffMaxDistance = 90
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, 3)
end

local lastPitchIndex = setmetatable({}, { __mode = "k" })
local shotCount, lastShotSound = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" }) -- 발사음 변주용
local SHOT_PITCH_PATTERN = { 1.0, 1.25, 0.84, 1.5, 0.75, 1.12, 0.94, 1.34, 0.7, 1.18, 1.42, 0.88, 1.06, 1.3, 0.78, 1.5 } -- 여덟 박자: 높고 낮음이 확실히 오르내린다

-- 발사 연출: 칼 휘두르기 대신 총구 화염 + 반동(총이 뒤로 살짝 밀림) + 발사음.
-- 팔은 기본 애니메이션의 "무기를 앞으로 든 자세"를 그대로 유지한다.
function Weapon.PlayShot(player)
	local character = player.Character
	local tool = character and character:FindFirstChild("Weapon")
	local barrel = tool and tool:FindFirstChild("Barrel")
	local tip = barrel and barrel:FindFirstChild("Tip")
	if not tip then return end

	local muzzle = tip:FindFirstChild("Muzzle")
	if muzzle then
		muzzle:Emit(6)
	end
	local light = tip:FindFirstChild("MuzzleLight")
	if light then
		light.Enabled = true
		task.delay(0.05, function()
			if light.Parent then
				light.Enabled = false
			end
		end)
	end

	-- 반동: 손과 총을 잇는 RightGrip의 위치를 잠깐 뒤로 밀었다가 되돌림
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	local grip = hand and hand:FindFirstChild("RightGrip")
	if grip then
		local rest = grip:GetAttribute("RestC1")
		if not rest then
			rest = grip.C1
			grip:SetAttribute("RestC1", rest)
		end
		local kick = TweenService:Create(grip, TweenInfo.new(0.04), { C1 = rest * CFrame.Angles(math.rad(6), 0, 0) * CFrame.new(0, 0, -0.35) })
		kick.Completed:Connect(function()
			if grip.Parent then
				TweenService:Create(grip, TweenInfo.new(0.1), { C1 = rest }):Play()
			end
		end)
		kick:Play()
	end

	-- 무기가 강할수록 낮고 묵직한 소리
	-- 무기 종류마다 다른 소리 (SoundBank: 같은 기본 소리를 피치 / 잔향 / 왜곡 / 겹치기로 가공). 세대가 높을수록 살짝 낮고 묵직하게
	local level = player:GetAttribute("WeaponLevel") or 0
	local tier = Config.GetLookTier(level, Config.ResolveWeaponType(level, player:GetAttribute("WeaponType")))
	local eraFactor = math.max(0.8, 1.08 - 0.03 * (tier.Era - 1))
	-- 똑같은 소리가 "탕탕탕탕" 반복되지 않게: 쏠 때마다 높낮이 / 크기가 조금씩 달라지고(네 박자 패턴 + 무작위),
	-- 아주 빠르게 연사할 때는 일부 발사음을 건너뛰거나 작게 해서 소리가 뭉개지지 않고 리듬이 생긴다
	local now = os.clock()
	local count = (shotCount[player] or 0) + 1
	shotCount[player] = count
	local gap = now - (lastShotSound[player] or 0)
	if gap < 0.06 and count % 2 == 0 then return end -- 아주 빠른 연사(0.06초 미만)만 두 발에 한 발 (예전 0.1초: 기관단총 소리가 절반 빠져 묻혔다)
	lastShotSound[player] = now
	-- 박자가 일정하면 지루하므로: 높낮이를 무작위로 고르되 바로 앞과 같은 음은 피하고, 가끔 아주 낮은 "쿵" / 높은 "탕" 강조음을 섞는다
	local index = math.random(#SHOT_PITCH_PATTERN)
	if index == lastPitchIndex[player] then index = index % #SHOT_PITCH_PATTERN + 1 end
	lastPitchIndex[player] = index
	local pitch = eraFactor * SHOT_PITCH_PATTERN[index] * (0.9 + math.random() * 0.2)
	local volume = 0.85 + math.random() * 0.3 -- (예전 0.65~1.25 x 연사 0.85: 작게 나는 발사음이 많아 묻혔다)
	if math.random() < 0.14 then
		pitch *= (math.random() < 0.5) and 0.72 or 1.38
		volume *= 1.2
	end
	Effects.GunSound(barrel.Position, tier.Class, pitch, volume, tier.Era) -- 소리는 근처 플레이어 화면에서 재생 (서버가 소리 부품을 만들지 않는다)
end

------------------------------------------------------------
-- 강화: 골드를 내고 확률적으로 +1. 실패해도 레벨은 내려가지 않음.
-- 반환: ok(성공 여부), message
------------------------------------------------------------
function Weapon.Enhance(player)
	if player:GetAttribute("Zone") ~= "Lobby" then
		return false, "Weapons can only be upgraded in the lobby.", true
	end

	local level = player:GetAttribute("WeaponLevel") or 0
	if level >= Config.Weapon.MaxLevel then
		return false, "You maxed out the final weapon!", true
	end

	-- 튜토리얼 미션 중에는 +3까지 무료 + 100% 성공
	if player:GetAttribute("TutorialFree") == true and level >= 3 then -- 무료 강화는 딱 3번: 미션이 넘어가는 짧은 사이에 광클해서 골드로 한 번 더 강화되지 않게 막는다
		return false, "✨ Free upgrades end here! Check your next mission", true
	end
	local free = player:GetAttribute("TutorialFree") == true and level < 3
	local cost = free and 0 or Config.GetEnhanceCost(level)
	local sure = free
	local tutorialCost = player:GetAttribute("TutorialEnhanceCost")
	if tutorialCost and not free then -- 진화 미션: 비용을 낮추고 100% 성공
		cost = math.min(cost, tutorialCost)
		sure = true
	end
	local gold = player:GetAttribute("Gold") or 0
	if gold < cost then
		return false, string.format("💰 Not enough gold. (%d needed) Earn gold at the dummy yard, field hunting, dungeons, or the Boss Rush", cost), true
	end

	player:SetAttribute("Gold", gold - cost)

	if sure or math.random() < Config.GetEnhanceChance(level) then
		-- 단계가 오르면 GameServer 가 무기 종류를 맞추고 모델도 갱신한다. 마지막 단계를 넘으면 다음 무기로 진화한다.
		player:SetAttribute("WeaponLevel", level + 1)
		Quest.Add(player, "Enhances", 1)
		local before, after = Config.GetWeaponTier(level), Config.GetWeaponTier(level + 1)
		local unlockedBefore, unlockedAfter = Config.GetUnlockedCount(level), Config.GetUnlockedCount(level + 1)
		local newForm = unlockedAfter > unlockedBefore and Config.WeaponTypes.Order[unlockedAfter] or nil
		local newEra = after.Era > before.Era
		local evolved = newForm ~= nil or newEra -- 새 무기 형이 해금되거나 시대가 바뀔 때만 큰 연출
		if newEra and after.Index >= 4 then
			Event.Announce(string.format("📢 %s's weapon evolved into [%s]!", player.DisplayName, Config.GetEraName(after.Era)))
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			Effects.Burst(root.Position, after.Color, evolved and 120 or 30)
			if evolved then
				Effects.FloatText(root.Position + Vector3.new(0, 5, 0), "⭐ " .. (newForm and Config.WeaponTypes[newForm].Name or Config.GetEraName(after.Era)), after.Color)
			end
		end
		if newForm then
			local info = Config.WeaponTypes[newForm]
			return true, string.format("🔓 %s unlocked! (%s) Pick it in the Weapons tab", info.Name, info.Trait), false, true, cost
		elseif newEra then
			local perkText = after.Perk and string.format(" · New era 『%s %s』!", after.Perk.Icon, after.Perk.Name) or ""
			return true, string.format("🎉 Evolved to %s! Your weapon look and bullet color changed%s", Config.GetEraName(after.Era), perkText), false, true, cost
		end
		return true, string.format("Upgrade success! +%d", level + 1), false, false, cost
	end
	return false, "Upgrade failed... (only the gold was lost)", false, false, cost
end

-- 해금한 무기 형 중에서 싸울 무기를 고른다
function Weapon.Equip(player, typeKey)
	local info = Config.WeaponTypes[typeKey]
	if typeKey == "Order" or typeof(info) ~= "table" then
		return false, "Unknown weapon."
	end
	local level = player:GetAttribute("WeaponLevel") or 0
	if not Config.IsWeaponUnlocked(level, typeKey) then
		return false, string.format("%s unlocks at +%d.", info.Name, Config.GetUnlockLevel(typeKey))
	end
	if player:GetAttribute("WeaponType") == typeKey then
		return true, string.format("You are already holding %s.", info.Name)
	end
	player:SetAttribute("WeaponType", typeKey)
	return true, string.format("%s equipped! (%s)", info.Name, info.Trait)
end

function Weapon.Buy()
	return false, "Weapon types unlock through upgrade levels! Pick one in the Weapons tab."
end

return Weapon
