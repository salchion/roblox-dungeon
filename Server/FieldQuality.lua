-- FieldQuality (ServerScriptService > Modules 안의 ModuleScript, 이름: FieldQuality)
-- 필드 8구역 화질 올리기. FieldDecor 가 만든 장식 위에 구역 테마별 "무대 꾸미기"를 더한다:
--   * 양옆 절벽: 상자 같던 절벽 앞에 튀어나온 바위 + 덮개(이끼 / 모래 / 눈 / 재 / 결정) + 늘어진 것(덩굴 / 고드름 / 용암 방울 / 결정)
--   * 가장자리 큰 나무(구역마다 다른 모양): 둥근 나무 / 고사목 / 야자 / 눈 덮인 침엽수 / 불탄 나무 / 뒤틀린 나무 / 결정 첨탑
--   * 절벽 너머 먼 산 능선 두 겹 (안개에 흐려져 거리감)
--   * 공중 연출: 꽃잎 / 나뭇잎 / 먼지 / 모래 / 눈 / 불씨 / 보랏빛 연기 / 분홍 빛 알갱이 (+ 숲의 옅은 햇살 기둥)
--   * 바닥 디테일: 풀 포기 / 잔해 / 모래 물결 / 눈 더미 / 식은 용암 금 / 가시 덤불 / 결정 조각
--   * 캠프: 천막 / 상자 / 통 / 모닥불 / 통나무 의자 / 구역색 깃발
-- 모든 부품은 앵커 + 충돌 / 질의 / 접촉 없음. 고정 시드라 매번 같은 모양. 실패해도 게임은 계속된다 (FieldService 가 pcall 로 부른다).
-- 예산: 구역당 최대 600 부품 (먼 산 -> 큰 나무 -> 공중 연출 -> 절벽 -> 바닥 순서로 채운다), 파티클 구역당 3개, 불빛 없음 (눈부시지 않게 / 성능).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local F = Config.Field

local Q = {}

local BUDGET = 720 -- (600 + 아래 7번 바닥 얼룩 / 바위 무리 / 랜드마크 몫)
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
local M = Enum.Material

-- 구역 테마
local THEMES = {
	{ -- 1 초원
		Rock = rgb(128, 124, 116), Cap = { rgb(96, 158, 82), M.Grass }, Hang = { "vine", rgb(80, 130, 64) },
		Tree = "round", Leaf = rgb(96, 158, 82), Bark = rgb(110, 80, 56), RidgeNear = rgb(90, 120, 84), RidgeFar = rgb(150, 172, 196),
		Air = { rgb(255, 214, 226), 1.5, 0.35, Vector3.new(1.5, -2, 0.5) }, Ground = "grass",
	},
	{ -- 2 숲
		Rock = rgb(96, 104, 92), Cap = { rgb(60, 112, 64), M.LeafyGrass }, Hang = { "vine", rgb(46, 92, 52) },
		Tree = "round", Leaf = rgb(52, 104, 62), Bark = rgb(80, 60, 44), RidgeNear = rgb(56, 86, 62), RidgeFar = rgb(120, 150, 150),
		Air = { rgb(120, 160, 70), 2, 0.6, Vector3.new(1.5, -2, 0.5) }, Ground = "grass", Shafts = true,
	},
	{ -- 3 황무지 / 폐허
		Rock = rgb(150, 132, 112), Cap = { rgb(112, 120, 74), M.Grass }, Hang = { "vine", rgb(96, 100, 60) },
		Tree = "dead", Leaf = rgb(110, 110, 70), Bark = rgb(96, 82, 70), RidgeNear = rgb(140, 116, 92), RidgeFar = rgb(196, 176, 156),
		Air = { rgb(210, 190, 160), 2, 0.4, Vector3.new(3, -0.3, 0.5) }, Ground = "rubble",
	},
	{ -- 4 사막
		Rock = rgb(196, 160, 110), Cap = { rgb(222, 196, 140), M.Sand }, Hang = nil,
		Tree = "palm", Leaf = rgb(110, 150, 70), Bark = rgb(150, 116, 76), RidgeNear = rgb(200, 160, 110), RidgeFar = rgb(232, 206, 170),
		Air = { rgb(236, 210, 160), 3, 0.3, Vector3.new(5, -0.2, 0) }, Ground = "ripple",
	},
	{ -- 5 설원
		Rock = rgb(126, 138, 156), Cap = { rgb(236, 244, 252), M.Snow }, Hang = { "icicle", rgb(190, 225, 250) },
		Tree = "pine", Leaf = rgb(52, 92, 80), Bark = rgb(90, 70, 56), RidgeNear = rgb(150, 166, 190), RidgeFar = rgb(210, 222, 238),
		Air = { rgb(250, 252, 255), 4, 0.4, Vector3.new(0.8, -3, 0.3) }, Ground = "drift",
	},
	{ -- 6 화산
		Rock = rgb(70, 52, 50), Cap = { rgb(96, 88, 84), M.Basalt }, Hang = { "ember", rgb(200, 80, 40) },
		Tree = "charred", Leaf = rgb(60, 50, 46), Bark = rgb(44, 36, 34), RidgeNear = rgb(80, 50, 44), RidgeFar = rgb(150, 90, 70),
		Air = { rgb(255, 140, 60), 3, 0.25, Vector3.new(0.5, 3, 0) }, Ground = "crack",
	},
	{ -- 7 암흑 지대
		Rock = rgb(62, 56, 82), Cap = { rgb(90, 70, 120), M.Slate }, Hang = { "crystal", rgb(160, 110, 230) },
		Tree = "twisted", Leaf = rgb(80, 56, 110), Bark = rgb(46, 40, 56), RidgeNear = rgb(70, 56, 100), RidgeFar = rgb(130, 110, 170),
		Air = { rgb(170, 130, 240), 2, 0.6, Vector3.new(0, 0.6, 0) }, Ground = "thorn",
	},
	{ -- 8 심연
		Rock = rgb(48, 40, 62), Cap = { rgb(120, 60, 110), M.Slate }, Hang = { "crystal", rgb(230, 100, 170) },
		Tree = "spire", Leaf = rgb(200, 90, 160), Bark = rgb(40, 34, 52), RidgeNear = rgb(70, 40, 80), RidgeFar = rgb(150, 80, 140),
		Air = { rgb(255, 130, 200), 2, 0.35, Vector3.new(0, 1, 0) }, Ground = "shard",
	},
}

function Q.Build(parentFolder, helpers)
	local folder = Instance.new("Folder")
	folder.Name = "FieldQuality"
	folder.Parent = parentFolder
	local floorAt, zoneBounds = helpers.FloorAt, helpers.ZoneBounds
	local half = (helpers.Width or F.Width) / 2
	local baffles = helpers.Baffles or {}

	for zone = 1, F.ZoneCount do
		local T = THEMES[zone] or THEMES[1]
		local rng = Random.new(9100 + zone * 31)
		local parts = 0
		local function R(a, b) return rng:NextNumber(a, b) end
		local function tint(c, amount)
			if amount >= 0 then return c:Lerp(Color3.new(1, 1, 1), amount) end
			return c:Lerp(Color3.new(0, 0, 0), -amount)
		end
		local function add(name, size, cf, color, material, shape, transparency, shadow)
			if parts >= BUDGET then return nil end
			parts += 1
			local p = Instance.new("Part")
			p.Name = name
			p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
			p.CastShadow = shadow == true
			p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
			if shape then p.Shape = shape end
			p.Size, p.CFrame, p.Color, p.Material = size, cf, color, material
			p.Transparency = transparency or 0
			p.Parent = folder
			return p
		end
		local function ball(name, size, pos, color, material, shadow)
			return add(name, size, CFrame.new(pos) * CFrame.Angles(0, math.rad(R(0, 360)), 0), color, material, Enum.PartType.Ball, nil, shadow)
		end
		local function cyl(name, a, b, d, color, material, shadow) -- a -> b 를 잇는 원기둥
			local dir = b - a
			if dir.Magnitude < 0.01 then return nil end
			return add(name, Vector3.new(dir.Magnitude, d, d), CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0), color, material, Enum.PartType.Cylinder, nil, shadow)
		end
		local function inBaffle(x, z, pad)
			for _, r in ipairs(baffles) do
				if x > r.X0 - pad and x < r.X1 + pad and z > r.Z0 - pad and z < r.Z1 + pad then return true end
			end
			return false
		end
		local x0, x1 = zoneBounds(zone)

		-- 1) 절벽 너머 먼 산 능선 두 겹 (가까운 겹은 진하게, 먼 겹은 옅게)
		for _, side in ipairs({ -1, 1 }) do
			for layer = 1, 2 do
				local dist = layer == 1 and R(150, 190) or R(260, 320)
				local color = layer == 1 and T.RidgeNear or T.RidgeFar
				local x = x0 - 40
				while x < x1 + 40 do
					local w = R(90, 160)
					local peak = layer == 1 and R(210, 280) or R(260, 360) -- 앞 절벽(120~200)보다 위로 솟게
					-- 45도 돌린 상자 = 뾰족한 봉우리 (아래쪽은 땅속에 묻힌다)
					add("FarRidge", Vector3.new(w, w, w * 0.6), CFrame.new(x, peak - w * 0.707, side * (half + dist)) * CFrame.Angles(0, math.rad(R(-12, 12)), math.rad(45)), tint(color, R(-0.06, 0.06)), M.Slate)
					if zone == 5 and layer == 1 then -- 설원: 봉우리 끝에 눈
						add("FarSnowCap", Vector3.new(w * 0.32, w * 0.32, w * 0.62), CFrame.new(x, peak - w * 0.24, side * (half + dist)) * CFrame.Angles(0, 0, math.rad(45)), rgb(240, 246, 252), M.Snow)
					end
					x += w * 0.7
				end
			end
		end

		-- 2) 가장자리 큰 나무 (구역마다 다른 모양): 화면 양옆을 감싸는 액자
		local function bigTree(p, h, side)
			local lean = math.rad(side * -R(3, 7))
			local base = CFrame.new(p) * CFrame.Angles(lean, 0, 0)
			local function at(y) return (base * CFrame.new(0, y, 0)).Position end
			local kind = T.Tree
			if kind == "spire" then -- 심연: 결정 첨탑 무리
				for k = 0, 3 do
					local hh = h * R(0.4, 1)
					local w = R(3, 6)
					add("CrystalSpire", Vector3.new(w, hh, w), CFrame.new(p + Vector3.new(R(-4, 4), hh / 2 - 1, R(-4, 4))) * CFrame.Angles(math.rad(R(-12, 12)), math.rad(k * 45), math.rad(R(-12, 12))), tint(T.Leaf, R(-0.2, 0.05)), M.Glass, nil, 0.15, true)
				end
				return
			end
			local trunkW = kind == "palm" and R(1.6, 2.2) or R(3, 4.2)
			cyl("BigTrunk", p, at(h * 0.55), trunkW, T.Bark, M.Wood, true)
			cyl("BigTrunkTop", at(h * 0.5), at(h), trunkW * (kind == "palm" and 0.85 or 0.72), tint(T.Bark, 0.04), M.Wood, true)
			if kind ~= "palm" then
				for k = 1, 4 do -- 뿌리
					local a = k / 4 * math.pi * 2 + R(-0.3, 0.3)
					cyl("BigRoot", p + Vector3.new(0, trunkW * 0.6, 0), p + Vector3.new(math.cos(a) * trunkW * 1.6, -0.3, math.sin(a) * trunkW * 1.6), trunkW * 0.45, tint(T.Bark, -0.08), M.Wood)
				end
			end
			local top = at(h)
			if kind == "round" then
				for k = 1, 6 do
					local a = k / 6 * math.pi * 2
					local s = R(10, 15)
					ball("BigLeaves", Vector3.new(s, s * 0.7, s), top + Vector3.new(math.cos(a) * R(4, 8), R(-3, 2), math.sin(a) * R(4, 8)), tint(T.Leaf, R(-0.15, 0.08)), k % 2 == 0 and M.LeafyGrass or M.Grass, true)
				end
				ball("BigLeavesTop", Vector3.new(12, 9, 12), top + Vector3.new(0, 6, 0), tint(T.Leaf, 0.1), M.Grass, true)
			elseif kind == "pine" then -- 원뿔을 쌓은 침엽수 + 눈
				for k = 0, 3 do
					local w = 16 - k * 3.4
					local y = h * 0.35 + k * h * 0.17
					add("PineLayer", Vector3.new(w, w * 0.55, w), CFrame.new(at(y)) * CFrame.Angles(0, math.rad(k * 20), 0), tint(T.Leaf, R(-0.08, 0.06)), M.LeafyGrass, Enum.PartType.Ball, nil, true)
					add("PineSnow", Vector3.new(w * 0.8, w * 0.22, w * 0.8), CFrame.new(at(y + w * 0.2)), rgb(236, 244, 252), M.Snow, Enum.PartType.Ball)
				end
			elseif kind == "palm" then -- 야자: 위에서 사방으로 늘어진 잎
				for k = 1, 7 do
					local a = k / 7 * math.pi * 2
					local tip = top + Vector3.new(math.cos(a) * 11, -4, math.sin(a) * 11)
					add("PalmFrond", Vector3.new(1.2, 0.3, 12), CFrame.lookAt((top + tip) / 2, tip), tint(T.Leaf, R(-0.1, 0.1)), M.LeafyGrass)
				end
				ball("Coconut", Vector3.new(1.6, 1.6, 1.6), top + Vector3.new(0.9, -1.2, 0), rgb(110, 80, 50), M.Wood)
			else -- 고사목 / 불탄 나무 / 뒤틀린 나무: 앙상한 가지
				for k = 1, 5 do
					local a = k / 5 * math.pi * 2 + R(-0.4, 0.4)
					local from = at(h * R(0.55, 0.95))
					local mid = from + Vector3.new(math.cos(a) * R(4, 7), R(2, 5), math.sin(a) * R(4, 7))
					local tip = mid + Vector3.new(math.cos(a + R(-0.6, 0.6)) * R(3, 6), R(1, 4) * (kind == "twisted" and -1 or 1), math.sin(a + R(-0.6, 0.6)) * R(3, 6))
					cyl("BareBranch", from, mid, trunkW * 0.4, T.Bark, M.Wood, true)
					cyl("BareTwig", mid, tip, trunkW * 0.22, tint(T.Bark, 0.05), M.Wood)
					if kind == "charred" and k % 2 == 0 then
						add("EmberTip", Vector3.new(0.8, 0.8, 0.8), CFrame.new(tip), rgb(200, 80, 40), M.Neon, Enum.PartType.Ball, 0.3)
					elseif kind == "twisted" then
						ball("DarkLeaves", Vector3.new(4, 3, 4), tip, tint(T.Leaf, R(-0.1, 0.1)), M.LeafyGrass)
					elseif kind == "dead" and k % 3 == 0 then
						ball("DryLeaves", Vector3.new(3.5, 2.5, 3.5), tip, tint(T.Leaf, R(-0.1, 0.1)), M.Grass)
					end
				end
			end
		end
		for _, side in ipairs({ -1, 1 }) do
			local x = x0 + R(40, 70)
			while x < x1 - 60 do
				local z = side * (half - R(5, 9))
				if not inBaffle(x, z, 10) then bigTree(Vector3.new(x, floorAt(x), z), R(26, 36), side) end
				x += R(55, 75)
			end
		end

		-- 3) 공중 연출 (파티클 3개) + 숲의 햇살 기둥
		local air = T.Air
		for k = 1, 3 do
			local px = x0 + (x1 - x0) * (k / 4)
			local anchor = add("AirFxAnchor", Vector3.new(1, 1, 1), CFrame.new(px, floorAt(px) + (air[4].Y > 0 and 2 or 26), R(-60, 60)), air[1], M.SmoothPlastic, nil, 1)
			if anchor then
				local e = Instance.new("ParticleEmitter")
				e.Rate, e.Lifetime, e.Speed = air[2], NumberRange.new(6, 10), NumberRange.new(1.5, 3)
				e.SpreadAngle = Vector2.new(180, 180)
				e.Acceleration = air[4]
				e.Rotation, e.RotSpeed = NumberRange.new(0, 360), NumberRange.new(-60, 60)
				e.Color = ColorSequence.new(air[1])
				e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, air[3]), NumberSequenceKeypoint.new(1, air[3] * 0.6) })
				e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.25), NumberSequenceKeypoint.new(0.85, 0.35), NumberSequenceKeypoint.new(1, 1) })
				e.LightEmission = zone >= 6 and 0.4 or 0
				e.Parent = anchor
			end
		end
		if T.Shafts then -- 나무 사이로 비치는 햇살 기둥 (아주 옅게)
			for _ = 1, 6 do
				local px = R(x0 + 80, x1 - 100)
				add("SunShaft", Vector3.new(R(6, 10), 90, R(6, 10)), CFrame.new(px, floorAt(px) + 41, R(-half + 40, half - 40)) * CFrame.Angles(math.rad(R(-6, 6)), 0, math.rad(R(14, 20))), rgb(255, 238, 190), M.Neon, nil, 0.93)
			end
		end

		-- 4) 절벽 앞 꾸미기 (양옆, 약 22 스터드마다)
		for _, side in ipairs({ -1, 1 }) do
			local x = x0 + 30
			while x < x1 - 20 do
				local face = side * (half + 2)
				local baseY = floorAt(x)
				if not inBaffle(x, side * (half - 4), 6) then
					for _ = 1, rng:NextInteger(2, 3) do
						local s = R(9, 18)
						local rock = ball("CliffOutcrop", Vector3.new(s * R(1, 1.4), s * R(0.6, 0.9), s * 0.8), Vector3.new(x + R(-8, 8), baseY + R(6, 70), face + side * s * 0.15), tint(T.Rock, R(-0.12, 0.08)), M.Slate)
						if rock and rng:NextNumber() < 0.7 then
							add("CliffCap", Vector3.new(s * 1.1, 1.2, s * 0.75), CFrame.new(rock.Position + Vector3.new(0, s * 0.3, 0)) * CFrame.Angles(0, math.rad(R(0, 360)), 0), tint(T.Cap[1], R(-0.12, 0.05)), T.Cap[2], Enum.PartType.Ball)
							local hang = T.Hang
							if hang then
								for _ = 1, rng:NextInteger(1, 3) do
									local hx, hz = R(-s / 3, s / 3), -side * s * 0.38
									if hang[1] == "vine" then
										local len = R(6, 18)
										add("CliffVine", Vector3.new(0.35, len, R(0.8, 1.6)), CFrame.new(rock.Position + Vector3.new(hx, -len / 2, hz)), tint(hang[2], R(-0.2, 0)), M.LeafyGrass)
									elseif hang[1] == "icicle" then
										local len = R(3, 8)
										add("Icicle", Vector3.new(0.8, len, 0.8), CFrame.new(rock.Position + Vector3.new(hx, -s * 0.3 - len / 2, hz)), hang[2], M.Ice, nil, 0.2)
									elseif hang[1] == "ember" then
										local len = R(4, 10)
										add("LavaDrip", Vector3.new(0.5, len, 0.5), CFrame.new(rock.Position + Vector3.new(hx, -s * 0.3 - len / 2, hz)), hang[2], M.Neon, nil, 0.45)
									else
										local len = R(3, 6)
										add("CliffCrystal", Vector3.new(1.2, len, 1.2), CFrame.new(rock.Position + Vector3.new(hx, s * 0.3 + len / 2, hz * 0.5)) * CFrame.Angles(0, math.rad(R(0, 90)), math.rad(R(-20, 20))), hang[2], M.Glass, nil, 0.2)
									end
								end
							end
						end
					end
					local pile = R(4, 7)
					ball("CliffBoulder", Vector3.new(pile * 1.3, pile * 0.8, pile), Vector3.new(x + R(-6, 6), baseY + pile * 0.25, side * (half - 1.5)), tint(T.Rock, R(-0.15, 0)), M.Slate)
					if zone <= 3 or zone == 7 then
						ball("CliffBush", Vector3.new(R(5, 8), R(3, 4.5), R(4, 6)), Vector3.new(x + R(-8, 8), baseY + 1.4, side * (half - 3)), tint(T.Cap[1], R(-0.12, 0.08)), M.Grass)
					end
				end
				x += R(18, 26)
			end
		end

		-- 5) 바닥 디테일 (넓은 땅 곳곳)
		for _ = 1, 45 do
			local px = R(x0 + F.CampSafe, x1 - 90)
			local pz = R(-half + 20, half - 20)
			if not inBaffle(px, pz, 4) then
				local base = Vector3.new(px, floorAt(px), pz)
				local g = T.Ground
				if g == "grass" then
					for b = 1, 3 do
						local h = R(1.4, 2.6)
						add("GrassBlade", Vector3.new(0.25, h, 0.7), CFrame.new(base + Vector3.new(R(-0.8, 0.8), h / 2, R(-0.8, 0.8))) * CFrame.Angles(0, math.rad(b * 60 + R(-15, 15)), math.rad(R(-18, 18))), tint(T.Leaf, R(-0.15, 0.12)), M.Grass)
					end
				elseif g == "rubble" then
					for _ = 1, 2 do
						local s = R(1, 2.4)
						add("Rubble", Vector3.new(s, s * 0.6, s * 1.2), CFrame.new(base + Vector3.new(R(-1.5, 1.5), s * 0.25, R(-1.5, 1.5))) * CFrame.Angles(R(-0.3, 0.3), R(0, 6.28), R(-0.3, 0.3)), tint(T.Rock, R(-0.15, 0.1)), M.Cobblestone)
					end
				elseif g == "ripple" then
					for r = 0, 2 do
						add("SandRipple", Vector3.new(R(6, 10), 0.2, 0.6), CFrame.new(base + Vector3.new(0, 0.1, r * 1.4)) * CFrame.Angles(0, math.rad(R(-8, 8)), 0), tint(T.Cap[1], -0.06), M.Sand)
					end
				elseif g == "drift" then
					add("SnowDrift", Vector3.new(R(5, 9), R(1, 2), R(3, 5)), CFrame.new(base + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, R(0, 6.28), 0), rgb(236, 244, 252), M.Snow, Enum.PartType.Ball)
				elseif g == "crack" then
					add("LavaCrack", Vector3.new(R(4, 9), 0.08, 0.35), CFrame.new(base + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, R(0, 6.28), 0), rgb(190, 70, 30), M.Neon, nil, 0.5)
				elseif g == "thorn" then
					for b = 1, 3 do
						local h = R(1.5, 3)
						add("Thorn", Vector3.new(0.3, h, 0.3), CFrame.new(base + Vector3.new(R(-1, 1), h / 2, R(-1, 1))) * CFrame.Angles(math.rad(R(-25, 25)), math.rad(b * 60), math.rad(R(-25, 25))), rgb(40, 32, 48), M.Wood)
					end
				else -- shard
					local h = R(1.5, 3.5)
					add("GroundShard", Vector3.new(0.9, h, 0.9), CFrame.new(base + Vector3.new(0, h / 2 - 0.2, 0)) * CFrame.Angles(math.rad(R(-20, 20)), R(0, 6.28), math.rad(R(-20, 20))), tint(T.Leaf, R(-0.15, 0.05)), M.Glass, nil, 0.2)
				end
			end
		end

		-- 6) 캠프 꾸미기 (구역 입구 캠프 x0 + 40: 가운데 빛기둥 / 네 기둥은 그대로, 바깥쪽에 천막과 짐)
		do
			local cx = x0 + 40
			local cy = floorAt(cx)
			local canvas = rgb(206, 190, 160):Lerp(F.ZoneColors[zone] or rgb(200, 200, 200), 0.25)
			for _, spot in ipairs({ { -14, 32 }, { 16, -33 } }) do -- 천막 두 개 (A자 지붕 두 장 + 앞 깃대)
				local c = Vector3.new(cx + spot[1], cy, spot[2])
				for _, s in ipairs({ -1, 1 }) do
					add("TentSide", Vector3.new(9, 0.3, 7), CFrame.new(c + Vector3.new(0, 2.6, s * 2.3)) * CFrame.Angles(math.rad(s * 52), 0, 0), tint(canvas, R(-0.06, 0.04)), M.Fabric, nil, nil, true)
				end
				cyl("TentPole", c + Vector3.new(-4.6, 0, 0), c + Vector3.new(-4.6, 5.6, 0), 0.3, rgb(90, 66, 46), M.Wood)
				add("TentFlag", Vector3.new(0.15, 1.4, 2.2), CFrame.new(c + Vector3.new(-4.6, 5, 1.1)), F.ZoneColors[zone] or rgb(200, 80, 60), M.Fabric)
			end
			for k = 1, 3 do -- 상자 / 통
				local p = Vector3.new(cx + 26 + k * 2.6, cy, 28 - k * 1.5)
				if k == 2 then
					cyl("Barrel", p, p + Vector3.new(0, 2.6, 0), 2, rgb(120, 86, 56), M.Wood)
				else
					add("Crate", Vector3.new(2.4, 2.4, 2.4), CFrame.new(p + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, math.rad(R(-20, 20)), 0), rgb(150, 112, 70), M.WoodPlanks)
				end
			end
			local fire = Vector3.new(cx - 2, cy, -27) -- 모닥불 + 통나무 의자 (네 모서리 기둥과 겹치지 않는 자리)
			for k = 1, 4 do
				local a = k / 4 * math.pi
				cyl("FireLog", fire + Vector3.new(math.cos(a) * 1.4, 0.4, math.sin(a) * 1.4), fire + Vector3.new(-math.cos(a) * 1.4, 0.4, -math.sin(a) * 1.4), 0.5, rgb(80, 56, 40), M.Wood)
			end
			add("FireGlow", Vector3.new(1.4, 1.6, 1.4), CFrame.new(fire + Vector3.new(0, 1, 0)), rgb(255, 150, 60), M.Neon, Enum.PartType.Ball, 0.25)
			for k = 0, 2, 2 do
				local a = k / 4 * math.pi * 2 + 0.6
				local p = fire + Vector3.new(math.cos(a) * 5, 0.6, math.sin(a) * 5)
				cyl("LogSeat", p - Vector3.new(math.sin(a) * 2.2, 0, -math.cos(a) * 2.2), p + Vector3.new(math.sin(a) * 2.2, 0, -math.cos(a) * 2.2), 1.2, rgb(110, 80, 54), M.Wood)
			end
		end

		-- 7) 바닥 얼룩 + 바위 무리 + 구역 랜드마크 (넓은 한 색 바닥이 밋밋해서: 진하고 연한 얼룩, 둥근 바위 무더기, 구역마다 눈에 띄는 큰 것 하나)
		do
			local groundColor = F.ZoneColors[zone] or T.Cap[1]
			for _ = 1, 26 do -- 바닥 얼룩: 얇은 원판 (밟아도 걸리지 않게 아주 얇게)
				local x, z = R(x0 + 30, x1 - 30), R(-half + 20, half - 20)
				if not inBaffle(x, z, 6) then
					local r = R(7, 18)
					add("GroundPatch", Vector3.new(0.12, r * 2, r * R(1.1, 2)), CFrame.new(x, floorAt(x) + 0.07, z) * CFrame.Angles(0, R(0, 6.28), math.rad(90)),
						tint(groundColor, R(-0.12, 0.1)), T.Cap[2], Enum.PartType.Cylinder)
				end
			end
			for _ = 1, 12 do -- 바위 무리: 둥근 바위 2~3개 + 작은 돌
				local x, z = R(x0 + 30, x1 - 30), R(-half + 25, half - 25)
				if not inBaffle(x, z, 10) and math.abs(z) > 18 then
					local y = floorAt(x)
					for k = 1, 3 do
						local s = k == 1 and R(3, 5) or R(1.2, 2.6)
						ball("RockPile", Vector3.new(s, s, s), Vector3.new(x + R(-3, 3), y + s * 0.25, z + R(-3, 3)), tint(T.Rock, R(-0.12, 0.08)), M.Slate, k == 1)
					end
				end
			end
			-- 랜드마크: 구역 가운데 길 옆에 하나 (먼 곳에서도 "여기가 그 구역" 이 보이게)
			local lx, lz = (x0 + x1) / 2 + R(-80, 80), -half * 0.55
			if not inBaffle(lx, lz, 30) then
				local ly = floorAt(lx)
				local base = Vector3.new(lx, ly, lz)
				local kind = ({ "stones", "log", "arch", "bones", "spires", "spikes", "crystals", "rings" })[zone] or "stones"
				if kind == "stones" or kind == "crystals" then -- 돌 고리 (초원) / 결정 고리 (암흑)
					for k = 1, 8 do
						local a = k / 8 * math.pi * 2
						local h = R(9, 14)
						local mat, col = M.Slate, tint(T.Rock, R(-0.05, 0.1))
						if kind == "crystals" then mat, col = M.Glass, T.Leaf end
						add("LandmarkStone", Vector3.new(3, h, 2), CFrame.new(base + Vector3.new(math.cos(a) * 16, h / 2 - 0.5, math.sin(a) * 16)) * CFrame.Angles(math.rad(R(-6, 6)), -a, math.rad(R(-6, 6))), col, mat, nil, kind == "crystals" and 0.15 or nil, true)
					end
					add("LandmarkTop", Vector3.new(3, 2, 14), CFrame.new(base + Vector3.new(16, 14, 0)), tint(T.Rock, -0.05), M.Slate, nil, nil, true)
				elseif kind == "log" then -- 쓰러진 거목 + 버섯
					cyl("LandmarkLog", base + Vector3.new(-22, 3, 0), base + Vector3.new(22, 4, 4), 7, T.Bark, M.Wood, true)
					for k = 1, 5 do
						local p = base + Vector3.new(R(-18, 18), 0, R(5, 9))
						cyl("LandmarkStem", p, p + Vector3.new(0, 2.5, 0), 0.8, rgb(232, 222, 200), M.SmoothPlastic)
						ball("LandmarkCap", Vector3.new(3, 3, 3), p + Vector3.new(0, 2.7, 0), rgb(200, 80, 70), M.SmoothPlastic)
					end
				elseif kind == "arch" then -- 무너진 아치 (폐허)
					for _, side in ipairs({ -1, 1 }) do
						add("LandmarkPillar", Vector3.new(4, side < 0 and 22 or 13, 4), CFrame.new(base + Vector3.new(side * 10, (side < 0 and 22 or 13) / 2, 0)), tint(T.Rock, 0.05), M.Cobblestone, nil, nil, true)
					end
					add("LandmarkBeam", Vector3.new(14, 3.5, 4.5), CFrame.new(base + Vector3.new(-4, 22, 0)) * CFrame.Angles(0, 0, math.rad(-8)), tint(T.Rock, 0.08), M.Cobblestone, nil, nil, true)
					add("LandmarkRubble", Vector3.new(6, 2.5, 5), CFrame.new(base + Vector3.new(6, 1.2, 4)) * CFrame.Angles(0, 0.5, 0.2), tint(T.Rock, -0.1), M.Cobblestone)
				elseif kind == "bones" then -- 반쯤 묻힌 거대한 뼈 (사막)
					local bone = rgb(236, 226, 204)
					for k = 0, 5 do
						local r = 9 - k * 0.6
						local cx = base.X + k * 3.4
						for seg = 0, 5 do -- 갈비뼈 한 대 = 원통 마디 6개로 반원
							local a0, a1 = seg / 6 * math.pi, (seg + 1) / 6 * math.pi
							cyl("LandmarkRib", Vector3.new(cx, base.Y + math.sin(a0) * r, base.Z + math.cos(a0) * r), Vector3.new(cx, base.Y + math.sin(a1) * r, base.Z + math.cos(a1) * r), 1.3, bone, M.SmoothPlastic, seg == 2)
						end
					end
					ball("LandmarkSkull", Vector3.new(8, 8, 8), base + Vector3.new(-6, 2, 0), bone, M.SmoothPlastic, true)
				elseif kind == "spires" or kind == "spikes" then -- 얼음 첨탑 (설원) / 흑요석 가시 + 용암 웅덩이 (화산)
					local col, mat = rgb(200, 236, 255), M.Ice
					if kind == "spikes" then col, mat = rgb(40, 32, 36), M.Basalt end
					for k = 1, 6 do
						local h = R(12, 26)
						add("LandmarkSpire", Vector3.new(R(3, 5), h, R(3, 5)), CFrame.new(base + Vector3.new(R(-12, 12), h / 2 - 1, R(-8, 8))) * CFrame.Angles(math.rad(R(-12, 12)), R(0, 6.28), math.rad(R(-12, 12))), col, mat, nil, kind == "spires" and 0.1 or nil, true)
					end
					if kind == "spikes" then
						add("LandmarkLava", Vector3.new(0.2, 18, 18), CFrame.new(base + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)), rgb(255, 110, 40), M.Neon, Enum.PartType.Cylinder, 0.35)
					end
				else -- rings: 떠 있는 돌 고리 (심연)
					for k = 1, 10 do
						local a = k / 10 * math.pi * 2
						ball("LandmarkOrbit", Vector3.new(3, 3, 3), base + Vector3.new(math.cos(a) * 12, 16 + math.sin(a * 2) * 2, math.sin(a) * 12), tint(T.Rock, 0.1), M.Slate)
					end
					add("LandmarkCore", Vector3.new(5, 5, 5), CFrame.new(base + Vector3.new(0, 16, 0)), T.Leaf, M.Neon, Enum.PartType.Ball, 0.3)
				end
			end
		end
	end
	return folder
end

return Q
