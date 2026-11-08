-- FieldQuality (ServerScriptService > Modules 안의 ModuleScript, 이름: FieldQuality)
-- 1~2구역(사람이 가장 오래 머무는 곳) 화질 올리기 2단계. FieldDecor 가 만든 장식 위에 "무대 꾸미기"를 더한다:
--   * 양옆 절벽: 밋밋한 큰 상자 절벽 앞에 튀어나온 바위 / 이끼 덮개 / 늘어진 덩굴 / 밑동 바위 더미
--   * 가장자리를 감싸는 큰 나무 (화면 양옆을 채워 깊이감)
--   * 절벽 너머 먼 산 능선 두 겹 (안개에 흐려져 멀리 보인다)
--   * 숲: 나무 사이로 비치는 옅은 햇살 기둥 + 떨어지는 나뭇잎 / 초원: 날리는 꽃잎
--   * 초원: 넓은 풀밭 곳곳에 풀 포기
-- 모든 부품은 앵커 + 충돌 / 질의 / 접촉 없음. 고정 시드라 매번 같은 모양. 실패해도 게임은 계속된다 (FieldService 가 pcall 로 부른다).
-- 예산: 구역당 최대 600 부품 (먼 산 -> 큰 나무 -> 공중 연출 -> 절벽 -> 풀 순서로 채운다), 파티클 4개, 불빛 0개.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local F = Config.Field

local Q = {}

local BUDGET = 600

function Q.Build(parentFolder, helpers)
	local folder = Instance.new("Folder")
	folder.Name = "FieldQuality"
	folder.Parent = parentFolder
	local floorAt, zoneBounds = helpers.FloorAt, helpers.ZoneBounds
	local half = (helpers.Width or F.Width) / 2
	local baffles = helpers.Baffles or {}

	for zone = 1, 2 do
		local rng = Random.new(9100 + zone * 31)
		local parts = 0
		local function R(a, b) return rng:NextNumber(a, b) end
		local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
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
		local function inBaffle(x, z, pad)
			for _, r in ipairs(baffles) do
				if x > r.X0 - pad and x < r.X1 + pad and z > r.Z0 - pad and z < r.Z1 + pad then return true end
			end
			return false
		end

		local x0, x1 = zoneBounds(zone)
		local leaf = zone == 1 and rgb(96, 158, 82) or rgb(52, 104, 62)
		local cliffRock = zone == 1 and rgb(128, 124, 116) or rgb(96, 104, 92)
		local bark = zone == 1 and rgb(110, 80, 56) or rgb(80, 60, 44)

		-- 3) 절벽 너머 먼 산 능선 두 겹 (가까운 겹은 진하게, 먼 겹은 옅고 푸르게: 안개가 거리감을 만든다)
		for _, side in ipairs({ -1, 1 }) do
			for layer = 1, 2 do
				local dist = layer == 1 and R(150, 190) or R(260, 320)
				local color = layer == 1 and tint(cliffRock, -0.2):Lerp(leaf, 0.35) or tint(cliffRock, 0.05):Lerp(rgb(150, 170, 200), 0.5)
				local x = x0 - 40
				while x < x1 + 40 do
					local w = R(90, 160)
					local peak = layer == 1 and R(210, 280) or R(260, 360) -- 봉우리 높이 (앞 절벽 120~200 보다 위로 솟게)
					-- 45도 돌린 상자 = 뾰족한 봉우리 (아래쪽은 땅속에 묻힌다)
					add("FarRidge", Vector3.new(w, w, w * 0.6), CFrame.new(x, peak - w * 0.707, side * (half + dist)) * CFrame.Angles(0, math.rad(R(-12, 12)), math.rad(45)), tint(color, R(-0.06, 0.06)), Enum.Material.Slate)
					x += w * 0.7
				end
			end
		end

		-- 2) 가장자리 큰 나무: 화면 양옆을 감싸는 액자 (60 스터드마다, 안쪽으로 살짝 기운다)
		local function bigTree(p, h, side)
			local lean = math.rad(side * -R(3, 7))
			local trunkW = R(3, 4.2)
			local base = CFrame.new(p) * CFrame.Angles(lean, 0, 0)
			add("BigTrunk", Vector3.new(h * 0.55, trunkW, trunkW), base * CFrame.new(0, h * 0.275, 0) * CFrame.Angles(0, 0, math.rad(90)), bark, Enum.Material.Wood, Enum.PartType.Cylinder, nil, true)
			add("BigTrunkTop", Vector3.new(h * 0.5, trunkW * 0.72, trunkW * 0.72), base * CFrame.new(0, h * 0.78, 0) * CFrame.Angles(0, 0, math.rad(90)), tint(bark, 0.04), Enum.Material.Wood, Enum.PartType.Cylinder, nil, true)
			for k = 1, 4 do -- 뿌리
				local a = k / 4 * math.pi * 2 + R(-0.3, 0.3)
				add("BigRoot", Vector3.new(trunkW * 1.6, trunkW * 0.45, trunkW * 0.5), CFrame.new(p + Vector3.new(math.cos(a) * trunkW * 0.8, trunkW * 0.15, math.sin(a) * trunkW * 0.8)) * CFrame.Angles(0, -a, math.rad(-18)), tint(bark, -0.08), Enum.Material.Wood, Enum.PartType.Ball)
			end
			local top = (base * CFrame.new(0, h, 0)).Position
			for k = 1, 6 do -- 잎 층: 아래는 넓게, 위로 갈수록 작게
				local a = k / 6 * math.pi * 2
				local reach = R(4, 8)
				local s = R(10, 15)
				ball("BigLeaves", Vector3.new(s, s * 0.7, s), top + Vector3.new(math.cos(a) * reach, R(-3, 2), math.sin(a) * reach), tint(leaf, R(-0.15, 0.08)), k % 2 == 0 and Enum.Material.LeafyGrass or Enum.Material.Grass, true)
			end
			ball("BigLeavesTop", Vector3.new(12, 9, 12), top + Vector3.new(0, 6, 0), tint(leaf, 0.1), Enum.Material.Grass, true)
		end
		for _, side in ipairs({ -1, 1 }) do
			local x = x0 + R(40, 70)
			while x < x1 - 60 do
				local z = side * (half - R(5, 9))
				if not inBaffle(x, z, 10) then bigTree(Vector3.new(x, floorAt(x), z), R(26, 36), side) end
				x += R(55, 75)
			end
		end

		-- 4) 공중 연출: 숲 = 햇살 기둥 + 떨어지는 나뭇잎 / 초원 = 날리는 꽃잎
		local function emitter(pos, color, rate, size, speed, life)
			local anchor = add("AirFxAnchor", Vector3.new(1, 1, 1), CFrame.new(pos), color, Enum.Material.SmoothPlastic, nil, 1)
			if not anchor then return end
			local e = Instance.new("ParticleEmitter")
			e.Rate, e.Lifetime, e.Speed = rate, NumberRange.new(life, life * 1.6), NumberRange.new(speed * 0.5, speed)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Acceleration = Vector3.new(1.5, -2, 0.5)
			e.Rotation, e.RotSpeed = NumberRange.new(0, 360), NumberRange.new(-60, 60)
			e.Color = ColorSequence.new(color)
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, size * 0.7) })
			e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.2), NumberSequenceKeypoint.new(0.85, 0.3), NumberSequenceKeypoint.new(1, 1) })
			e.LightEmission = 0
			e.Parent = anchor
		end
		local span = x1 - x0
		for k = 1, 3 do
			local px = x0 + span * (k / 4)
			if zone == 2 then
				emitter(Vector3.new(px, floorAt(px) + 28, R(-60, 60)), rgb(120, 160, 70), 2, 0.6, 3, 6) -- 나뭇잎
			else
				emitter(Vector3.new(px, floorAt(px) + 22, R(-60, 60)), rgb(255, 214, 226), 1.5, 0.35, 3, 6) -- 꽃잎
			end
		end
		if zone == 2 then -- 나무 사이로 비치는 햇살 기둥 (아주 옅게: 눈부시지 않게)
			for _ = 1, 6 do
				local px = R(x0 + 80, x1 - 100)
				local pz = R(-half + 40, half - 40)
				local h = 90
				add("SunShaft", Vector3.new(R(6, 10), h, R(6, 10)), CFrame.new(px, floorAt(px) + h / 2 - 4, pz) * CFrame.Angles(math.rad(R(-6, 6)), 0, math.rad(R(14, 20))), rgb(255, 238, 190), Enum.Material.Neon, nil, 0.93)
			end
		end

		-- 1) 절벽 앞 꾸미기 (양옆, 22 스터드마다)
		for _, side in ipairs({ -1, 1 }) do
			local x = x0 + 30
			while x < x1 - 20 do
				local face = side * (half + 2)
				local baseY = floorAt(x)
				if not inBaffle(x, side * (half - 4), 6) then
					-- 튀어나온 바위 두세 개 (높이가 제각각)
					for _ = 1, rng:NextInteger(2, 3) do
						local s = R(9, 18)
						local y = baseY + R(6, 70)
						local rock = ball("CliffOutcrop", Vector3.new(s * R(1, 1.4), s * R(0.6, 0.9), s * 0.8), Vector3.new(x + R(-8, 8), y, face + side * s * 0.15), tint(cliffRock, R(-0.12, 0.08)), Enum.Material.Slate)
						if rock and rng:NextNumber() < 0.7 then -- 위에 이끼 덮개 + 늘어진 덩굴
							add("CliffMoss", Vector3.new(s * 1.1, 1.2, s * 0.75), CFrame.new(rock.Position + Vector3.new(0, s * 0.3, 0)) * CFrame.Angles(0, math.rad(R(0, 360)), 0), tint(leaf, R(-0.15, 0.05)), Enum.Material.Grass, Enum.PartType.Ball)
							for _ = 1, rng:NextInteger(1, 3) do
								local len = R(6, 18)
								add("CliffVine", Vector3.new(0.35, len, R(0.8, 1.6)), CFrame.new(rock.Position + Vector3.new(R(-s / 3, s / 3), -len / 2, -side * s * 0.38)), tint(leaf, R(-0.25, -0.05)), Enum.Material.LeafyGrass)
							end
						end
					end
					-- 밑동: 바위 더미 + 덤불 (벽 바로 앞, 길을 막지 않을 만큼 가장자리)
					local pile = R(4, 7)
					ball("CliffBoulder", Vector3.new(pile * 1.3, pile * 0.8, pile), Vector3.new(x + R(-6, 6), baseY + pile * 0.25, side * (half - 1.5)), tint(cliffRock, R(-0.15, 0)), Enum.Material.Slate)
					ball("CliffBush", Vector3.new(R(5, 8), R(3, 4.5), R(4, 6)), Vector3.new(x + R(-8, 8), baseY + 1.4, side * (half - 3)), tint(leaf, R(-0.12, 0.08)), Enum.Material.Grass)
				end
				x += R(18, 26)
			end
		end

		-- 5) 초원: 넓은 풀밭 곳곳의 풀 포기 (가는 풀잎 세 장 묶음)
		if zone == 1 then
			for _ = 1, 45 do
				local px = R(x0 + F.CampSafe, x1 - 90)
				local pz = R(-half + 20, half - 20)
				if not inBaffle(px, pz, 4) then
					local base = Vector3.new(px, floorAt(px), pz)
					for b = 1, 3 do
						local h = R(1.4, 2.6)
						add("GrassBlade", Vector3.new(0.25, h, 0.7), CFrame.new(base + Vector3.new(R(-0.8, 0.8), h / 2, R(-0.8, 0.8))) * CFrame.Angles(0, math.rad(b * 60 + R(-15, 15)), math.rad(R(-18, 18))), tint(rgb(104, 170, 80), R(-0.15, 0.1)), Enum.Material.Grass)
					end
				end
			end
		end
	end
	return folder
end

return Q
