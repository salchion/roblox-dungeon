-- FieldWorld (ServerScriptService > Modules 안의 ModuleScript, 이름: FieldWorld)
-- 필드 맵 짓기: 구역 꾸미기 / 캠프 / 관문 / 바닥 / 벽 (서버가 시작할 때 한 번만 돈다).
-- FieldService 가 Studio 스크립트 한도(200KB)에 가까워서 본문을 그대로 옮겼다 (동작 변경 없음). 필요한 것은 Build(env) 로 넘겨 받는다.
--   env: CollectionService, Config, F, Remotes, TOP, ZONE_LAYOUTS, ZONE_SEGMENTS, baffleRects, baffleXs, campCFrames, zoneBounds(표: 여기서 채운다),
--        floorAt, makePart, makeSign, zoneOfX (함수). 반환: worldFolder, monstersFolder

local FieldWorld = {}

function FieldWorld.Build(env)
	local CollectionService, Config, F, Remotes, TOP = env.CollectionService, env.Config, env.F, env.Remotes, env.TOP
	local ZONE_LAYOUTS, ZONE_SEGMENTS, baffleRects, baffleXs, campCFrames, zoneBounds = env.ZONE_LAYOUTS, env.ZONE_SEGMENTS, env.baffleRects, env.baffleXs, env.campCFrames, env.zoneBounds
	local floorAt, makePart, makeSign, zoneOfX = env.floorAt, env.makePart, env.makeSign, env.zoneOfX
	local worldFolder, monstersFolder

	-- ===== 구역 꾸미기 (구역마다 완전히 다른 지형지물 + 그 구역의 랜드마크 하나) =====
	-- 장식은 대부분 충돌이 없거나 작아서 길을 막지 않는다. 경사로 / 꺾임 벽 / 캠프 근처에는 놓지 않는다.
	local function propBlocked(zone, offset)
		local layout = ZONE_LAYOUTS[zone] or ZONE_LAYOUTS[1]
		for _, stair in ipairs(layout.Stairs) do
			if offset > stair.At - 10 and offset < stair.At + stair.Run + 10 then return true end
		end
		for _, wall in ipairs(layout.Baffles) do
			if math.abs(offset - wall.Offset) < 20 then return true end
		end
		return false
	end

	local okZoneProps, FieldZoneProps = pcall(function() return require(script.Parent:WaitForChild("FieldZoneProps", 10)) end) -- (구역 꾸미기는 따로 뺀 모듈)
	local function decorateZone(zone, rng)
		if not okZoneProps or not FieldZoneProps then warn("[FieldService] FieldZoneProps 모듈이 없어 구역 장식을 건너뜁니다 (던전 업데이트를 다시 해 주세요)") return end
		local ok, err = pcall(FieldZoneProps.Decorate, zone, rng, { ZoneBounds = zoneBounds, MakePart = makePart, FloorAt = floorAt, PropBlocked = propBlocked, Folder = worldFolder })
		if not ok then warn("[FieldService] 구역 " .. tostring(zone) .. " 장식 오류: " .. tostring(err)) end
	end

	local function buildCanyon(rng, totalLength, half)
		local endX = F.StartX + totalLength

		-- 뒤에 깔아두는 끊김 없는 절벽 벽 (절벽 덩어리 사이로 바깥이 비치지 않게)
		for _, side in ipairs({ -1, 1 }) do
			makePart({
				Name = "CanyonBack", Size = Vector3.new(totalLength + 120, 240, 8),
				Position = Vector3.new(F.StartX + totalLength / 2, 120, side * (half + 34)),
				Color = Color3.fromRGB(55, 50, 58), Material = Enum.Material.Slate,
			}, worldFolder)

			-- 구역 색을 띤 크고 울퉁불퉁한 절벽 덩어리들
			local x = F.StartX - 10
			while x < endX + 20 do
				local zone = zoneOfX(math.clamp(x, F.StartX, endX - 1))
				local width = rng:NextNumber(34, 52)
				local height = rng:NextNumber(120, 200)
				local depth = rng:NextNumber(18, 30)
				local inner = half + rng:NextNumber(-4, 4)
				makePart({
					Name = "Cliff", Size = Vector3.new(width, height, depth),
					CFrame = CFrame.new(x, height / 2 - 2, side * (inner + depth / 2)) * CFrame.Angles(0, math.rad(rng:NextNumber(-6, 6)), 0),
					Color = F.ZoneColors[zone]:Lerp(Color3.fromRGB(70, 65, 72), 0.55),
					Material = Enum.Material.Slate,
				}, worldFolder)
				x += width * 0.8
			end
		end

		-- 필드 끝 / 로비에서 들어오는 통로 양옆도 절벽으로 막는다
		makePart({
			Name = "CanyonEnd", Size = Vector3.new(40, 240, F.Width + 90),
			Position = Vector3.new(endX + 150, 120, 0), -- (예전 endX + 20: 오프닝의 최후의 군주(endX + 6)가 이 벽 속에 파묻혀 안 보였다. 군주 뒤쪽으로 물린다)
			Color = Color3.fromRGB(35, 30, 45), Material = Enum.Material.Slate,
		}, worldFolder)
		for _, side in ipairs({ -1, 1 }) do
			makePart({
				Name = "CanyonGate", Size = Vector3.new(34, 80, 50),
				Position = Vector3.new(F.StartX - 16, 40, side * (21 + 25)),
				Color = Color3.fromRGB(95, 110, 85), Material = Enum.Material.Slate,
			}, worldFolder)
		end
	end

	-- 구역 입구 캠프: 안전지대 + 워프 비콘 + 부활 지점
	local function buildCamp(zone, x0)
		local center = Vector3.new(x0 + 40, TOP, 0)
		local accent = F.ZoneColors[zone]:Lerp(Color3.fromRGB(255, 255, 255), 0.35)

		makePart({
			Name = "CampFloor", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 64, 64),
			CFrame = CFrame.new(center + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(120, 112, 100), Material = Enum.Material.Cobblestone,
		}, worldFolder)

		local beacon = makePart({
			Name = "CampBeacon", Size = Vector3.new(3, 26, 3), Position = center + Vector3.new(0, 13, 0),
			Color = accent, Material = Enum.Material.Neon,
		}, worldFolder)
		local light = Instance.new("PointLight")
		light.Range = 45
		light.Brightness = 1.6
		light.Color = accent
		light.Parent = beacon
		makeSign(beacon, "⛺ Camp · Warp", Color3.fromRGB(255, 240, 200), 18)

		for index = 0, 3 do
			local angle = math.rad(index * 90 + 45)
			local post = center + Vector3.new(math.cos(angle) * 24, 0, math.sin(angle) * 24)
			makePart({ Name = "CampPost", Size = Vector3.new(1, 8, 1), Position = post + Vector3.new(0, 4, 0), Color = Color3.fromRGB(70, 50, 38), Material = Enum.Material.Wood }, worldFolder)
			local flame = makePart({
				Name = "CampFlame", Shape = Enum.PartType.Ball, Size = Vector3.new(2, 2, 2), Position = post + Vector3.new(0, 9, 0),
				Color = Color3.fromRGB(255, 150, 60), Material = Enum.Material.Neon, CanCollide = false,
			}, worldFolder)
			local flameLight = Instance.new("PointLight")
			flameLight.Range = 26
			flameLight.Color = Color3.fromRGB(255, 170, 90)
			flameLight.Parent = flame
		end

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Warp / Camp"
		prompt.ObjectText = string.format("Zone %d Camp", zone)
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 18
		prompt.RequiresLineOfSight = false
		prompt.Parent = beacon
		prompt.Triggered:Connect(function(player)
			Remotes.Warp:FireClient(player, "Open")
		end)

		-- 안전지대 경계: 이 선 안에서는 사격이 통하지 않고 몬스터도 들어오지 않는다. 은은한 청록 선 + 작은 말뚝으로 어디까지인지 보이게 한다
		local boundaryX = x0 + F.CampSafe
		local teal = Color3.fromRGB(110, 205, 195)
		local line = makePart({
			Name = "SafeLine", Size = Vector3.new(0.7, 0.2, F.Width), Position = Vector3.new(boundaryX, TOP + 0.12, 0),
			Color = teal, Material = Enum.Material.Neon, Transparency = 0.55, CanCollide = false, CanQuery = false,
		}, worldFolder)
		local lineGui = Instance.new("BillboardGui") -- 작은 글씨: 가까이 갔을 때만 보인다
		lineGui.Size = UDim2.new(0, 240, 0, 26)
		lineGui.StudsOffset = Vector3.new(0, 4, 0)
		lineGui.MaxDistance = 55
		lineGui.Parent = line
		local lineText = Instance.new("TextLabel")
		lineText.Size = UDim2.new(1, 0, 1, 0)
		lineText.BackgroundTransparency = 1
		lineText.Font = Enum.Font.GothamBold
		lineText.TextScaled = true
		lineText.TextColor3 = Color3.fromRGB(190, 240, 232)
		lineText.TextStrokeTransparency = 0.4
		lineText.Text = "🛡 Safe Zone Edge (no shooting inside)"
		lineText.Parent = lineGui
		for z = -F.Width / 2 + 20, F.Width / 2 - 20, 40 do
			makePart({ Name = "SafePost", Size = Vector3.new(0.7, 3, 0.7), Position = Vector3.new(boundaryX, TOP + 1.5, z), Color = Color3.fromRGB(70, 90, 92), Material = Enum.Material.Slate, CanCollide = false, CanQuery = false }, worldFolder)
			makePart({ Name = "SafeCap", Shape = Enum.PartType.Ball, Size = Vector3.new(0.9, 0.9, 0.9), Position = Vector3.new(boundaryX, TOP + 3.2, z), Color = teal, Material = Enum.Material.Neon, Transparency = 0.35, CanCollide = false, CanQuery = false }, worldFolder)
		end

		campCFrames[zone] = CFrame.lookAt(Vector3.new(x0 + 40, TOP + 4, 16), Vector3.new(x0 + 140, TOP + 4, 16)) -- (필드 안쪽(동쪽)을 바라보고 선다: 등 뒤가 마을)
	end

	-- 구역 관문: 구역마다 컨셉이 다른 성문 / 입구. 문은 활짝 열려 있고, 이름 / 컨셉 / 몬스터 레벨이 위에 걸려 있다.
	--   1 초원 목책 문 · 2 숲속 고성 정문 · 3 무너진 요새 · 4 사막 신전 · 5 얼음 궁전 · 6 용암 요새 · 7 암흑 성 · 8 심연의 문
	local GATE_THEMES = {
		{ Tag = "🌾 Adventure Begins", Wall = Color3.fromRGB(140, 105, 70), Mat = Enum.Material.Wood, Accent = Color3.fromRGB(255, 205, 90), Height = 24, Crenel = false },
		{ Tag = "🏰 Forest Castle Gate", Wall = Color3.fromRGB(105, 125, 105), Mat = Enum.Material.Brick, Accent = Color3.fromRGB(120, 230, 130), Height = 34, Crenel = true },
		{ Tag = "🏚 Ruined Fortress Gate", Wall = Color3.fromRGB(120, 105, 90), Mat = Enum.Material.Cobblestone, Accent = Color3.fromRGB(255, 170, 80), Height = 30, Crenel = true },
		{ Tag = "🏜 Desert Temple Entrance", Wall = Color3.fromRGB(205, 175, 110), Mat = Enum.Material.Sandstone, Accent = Color3.fromRGB(255, 215, 70), Height = 32, Crenel = false },
		{ Tag = "❄ Ice Palace Gate", Wall = Color3.fromRGB(180, 215, 235), Mat = Enum.Material.Ice, Accent = Color3.fromRGB(130, 220, 255), Height = 34, Crenel = true },
		{ Tag = "🌋 Lava Fortress Gate", Wall = Color3.fromRGB(70, 45, 42), Mat = Enum.Material.Basalt, Accent = Color3.fromRGB(255, 110, 40), Height = 34, Crenel = true },
		{ Tag = "🦇 Dark Castle Gate", Wall = Color3.fromRGB(45, 38, 62), Mat = Enum.Material.Slate, Accent = Color3.fromRGB(170, 100, 255), Height = 40, Crenel = true },
		{ Tag = "🌀 Gate of the Abyss", Wall = Color3.fromRGB(28, 24, 40), Mat = Enum.Material.Slate, Accent = Color3.fromRGB(255, 70, 130), Height = 40, Crenel = false },
	}

	local function buildGateway(zone, x0)
		local theme = GATE_THEMES[zone]
		local half = F.Width / 2
		local open = 56            -- 열린 통로 폭 (로비 쪽 통로 40보다 넓게)
		local H = theme.Height + (zone - 1) * 5 -- 동쪽으로 갈수록 관문이 점점 거대해진다
		local thick = 8
		local accent = theme.Accent

		local function part(name, size, position, color, material, extra)
			local props = { Name = name, Size = size, Position = position, Color = color or theme.Wall, Material = material or theme.Mat }
			for key, value in pairs(extra or {}) do
				props[key] = value
			end
			if props.CFrame then
				props.Position = nil -- CFrame 이 위치를 정한다 (둘 다 있으면 적용 순서가 불확실)
			end
			return makePart(props, worldFolder)
		end
		local function torch(position)
			local flame = part("GateFlame", Vector3.new(2.4, 2.4, 2.4), position, accent, Enum.Material.Neon, { Shape = Enum.PartType.Ball, CanCollide = false })
			local light = Instance.new("PointLight")
			light.Range = 36
			light.Brightness = 1.6
			light.Color = accent
			light.Parent = flame
		end

		for _, side in ipairs({ -1, 1 }) do
			-- 성벽 + 흉벽
			local length = half - open / 2
			local zc = side * (open / 2 + length / 2)
			part("GateWall", Vector3.new(thick, H, length), Vector3.new(x0 + 2, H / 2, zc))
			if theme.Crenel then
				for z = open / 2 + 8, half - 4, 12 do
					part("Crenel", Vector3.new(thick, 4, 6), Vector3.new(x0 + 2, H + 2, side * z))
				end
			end

			-- 문루(탑) + 지붕 띠 + 창
			local towerZ = side * (open / 2 + 8)
			part("GateTower", Vector3.new(16, H + 14, 16), Vector3.new(x0 + 2, (H + 14) / 2, towerZ))
			part("TowerCap", Vector3.new(19, 3, 19), Vector3.new(x0 + 2, H + 15.5, towerZ), accent, Enum.Material.Neon)
			part("TowerWindow", Vector3.new(1, 7, 3.5), Vector3.new(x0 + 10.4, H * 0.72, towerZ), accent, Enum.Material.Neon, { CanCollide = false })
			part("TowerWindow", Vector3.new(1, 7, 3.5), Vector3.new(x0 - 6.4, H * 0.72, towerZ), accent, Enum.Material.Neon, { CanCollide = false })
			torch(Vector3.new(x0 + 11, 15, side * (open / 2 - 1)))

			-- 활짝 열린 문짝: 통로 가장자리에 경첩을 두고 안쪽(+x)으로 거의 활짝 젖혀 놓는다
			if zone ~= 8 then
				local hinge = Vector3.new(x0 + 2, 0, side * (open / 2 - 0.5))
				local angle = math.rad(78)
				local doorLength = 26
				local vector = Vector3.new(math.sin(angle), 0, -side * math.cos(angle)) * doorLength
				local center = hinge + vector / 2 + Vector3.new(0, H * 0.45, 0)
				part("GateDoor", Vector3.new(2, H * 0.9, doorLength), center, theme.Wall:Lerp(Color3.fromRGB(60, 45, 35), 0.5), Enum.Material.Wood,
					{ CFrame = CFrame.lookAt(center, center + vector) })
				-- 문짝 장식 띠
				part("DoorBand", Vector3.new(2.2, 2, doorLength), center + Vector3.new(0, H * 0.25, 0), accent, Enum.Material.Neon,
					{ CFrame = CFrame.lookAt(center + Vector3.new(0, H * 0.25, 0), center + Vector3.new(0, H * 0.25, 0) + vector), CanCollide = false })
			end
		end

		-- 상인방(문 위 가로보) + 컨셉 장식
		if zone ~= 8 then
			part("GateLintel", Vector3.new(thick, 7, open + 2), Vector3.new(x0 + 2, H - 0.5, 0))
			part("LintelGlow", Vector3.new(thick + 0.4, 1.2, open + 2.4), Vector3.new(x0 + 2, H - 4.5, 0), accent, Enum.Material.Neon, { CanCollide = false })
		end

		if zone == 1 then -- 목책: 문 앞뒤로 말뚝 울타리 + 깃발
			for _, side in ipairs({ -1, 1 }) do
				for index = 0, 5 do
					part("Fence", Vector3.new(1.4, 6, 1.4), Vector3.new(x0 + 14 + index * 7, 3, side * (open / 2 + 14)))
				end
				part("FenceRail", Vector3.new(42, 1, 0.8), Vector3.new(x0 + 35, 4.5, side * (open / 2 + 14)))
				part("Banner", Vector3.new(0.4, 9, 5), Vector3.new(x0 + 2, H + 6, side * (open / 2 + 8)), Color3.fromRGB(210, 70, 60), Enum.Material.Fabric, { CanCollide = false })
			end
		elseif zone == 2 then -- 이끼 낀 성: 덩굴 + 녹색 깃발
			for _, side in ipairs({ -1, 1 }) do
				part("Banner", Vector3.new(0.4, 14, 6), Vector3.new(x0 + 11, H - 4, side * (open / 2 + 8)), Color3.fromRGB(50, 130, 70), Enum.Material.Fabric, { CanCollide = false })
				part("Moss", Vector3.new(thick + 0.3, 6, 22), Vector3.new(x0 + 2, H - 3, side * (open / 2 + 30)), Color3.fromRGB(60, 120, 60), Enum.Material.Grass, { CanCollide = false })
			end
		elseif zone == 3 then -- 폐허: 부러진 기둥 + 잔해
			for _, side in ipairs({ -1, 1 }) do
				part("BrokenPillar", Vector3.new(5, 16, 5), Vector3.new(x0 - 8, 8, side * (open / 2 + 28)), nil, nil, { CFrame = CFrame.new(x0 - 8, 8, side * (open / 2 + 28)) * CFrame.Angles(0, 0.4, math.rad(side * 14)) })
				part("Rubble", Vector3.new(7, 3.5, 6), Vector3.new(x0 + 16, 1.7, side * (open / 2 + 6)), nil, nil, { CFrame = CFrame.new(x0 + 16, 1.7, side * (open / 2 + 6)) * CFrame.Angles(0.2, 0.8, 0.1) })
			end
		elseif zone == 4 then -- 사막 신전: 오벨리스크
			for _, side in ipairs({ -1, 1 }) do
				part("Obelisk", Vector3.new(6, 42, 6), Vector3.new(x0 - 12, 21, side * (open / 2 + 34)))
				part("ObeliskTip", Vector3.new(4, 6, 4), Vector3.new(x0 - 12, 45, side * (open / 2 + 34)), accent, Enum.Material.Neon)
			end
		elseif zone == 5 then -- 얼음 궁전: 기울어진 얼음 첨탑
			for _, side in ipairs({ -1, 1 }) do
				for index = 1, 3 do
					local z = side * (open / 2 + 18 + index * 9)
					local height = 14 + index * 4
					part("IceSpike", Vector3.new(4, height, 4), Vector3.new(x0 + 6, height / 2, z), Color3.fromRGB(190, 230, 250), Enum.Material.Ice,
						{ CFrame = CFrame.new(x0 + 6, height / 2, z) * CFrame.Angles(0, 0, math.rad(side * -10)), Transparency = 0.25 })
				end
			end
		elseif zone == 6 then -- 용암 요새: 바닥 용암 줄기 + 불기둥
			for _, side in ipairs({ -1, 1 }) do
				part("LavaStream", Vector3.new(30, 0.4, 7), Vector3.new(x0 + 22, 0.25, side * (open / 2 + 5)), accent, Enum.Material.Neon, { CanCollide = false })
				torch(Vector3.new(x0 - 6, 22, side * (open / 2 + 20)))
			end
		elseif zone == 7 then -- 암흑 성: 보랏빛 룬과 박쥐 깃발
			for _, side in ipairs({ -1, 1 }) do
				part("Banner", Vector3.new(0.4, 18, 6), Vector3.new(x0 + 11, H - 2, side * (open / 2 + 8)), Color3.fromRGB(60, 25, 90), Enum.Material.Fabric, { CanCollide = false })
				part("FloatRune", Vector3.new(4, 4, 4), Vector3.new(x0 + 6, H + 26, side * 16), accent, Enum.Material.Neon, { CanCollide = false, CFrame = CFrame.new(x0 + 6, H + 26, side * 16) * CFrame.Angles(0.8, 0.6, 0.3) })
			end
		elseif zone == 8 then -- 심연의 문: 거대한 고리 + 빛나는 막
			local segments = 18
			local radius = 30
			for index = 0, segments - 1 do
				local angle = index / segments * math.pi * 2
				local position = Vector3.new(x0 + 2, 32 + math.sin(angle) * radius, math.cos(angle) * radius)
				part("PortalRing", Vector3.new(4, 7, 7), position, accent, Enum.Material.Neon, { CanCollide = false,
					CFrame = CFrame.new(position) * CFrame.Angles(angle, 0, 0) })
			end
			part("PortalVeil", Vector3.new(1, 50, 56), Vector3.new(x0 + 2, 27, 0), accent, Enum.Material.Neon, { Transparency = 0.85, CanCollide = false, CanQuery = false })
		end

		-- 관문 봉인막: 구역 2부터. 보이는 모습은 클라이언트(GoalClient)가 내 진행도에 맞춰 열고 닫는다 (서버는 위치로 막는다)
		if zone >= 2 then
			local seal = part("GateSeal", Vector3.new(1, H - 4, open), Vector3.new(x0 - 1, (H - 4) / 2, 0), accent, Enum.Material.Neon,
				{ Transparency = 0.45, CanCollide = false, CanQuery = false })
			seal:SetAttribute("SealZone", zone)
			CollectionService:AddTag(seal, "ZoneSeal")
			local gui = Instance.new("BillboardGui")
			gui.Name = "SealGui"
			gui.Size = UDim2.new(0, 340, 0, 90)
			gui.StudsOffset = Vector3.new(-6, 0, 0)
			gui.MaxDistance = 140
			gui.Parent = seal
			local label = Instance.new("TextLabel")
			label.Name = "Text"
			label.Size = UDim2.new(1, 0, 1, 0)
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.GothamBold
			label.TextScaled = true
			label.TextColor3 = Color3.new(1, 1, 1)
			label.TextStrokeTransparency = 0
			label.Text = "🔒"
			label.Parent = gui
		end

		-- 바닥 경고 줄무늬 (구역 번호만큼): 위험도가 눈에 보인다. (예전에 있던 구역 입구의 하늘 빛기둥 + 불빛은 눈이 부시고 시야를 가려서 껐다)
		do
			for stripe = 1, zone do -- 구역 번호만큼 줄무늬: 위험도가 눈에 보인다
				part("GateWarnStripe", Vector3.new(1.6, 0.25, open + 8), Vector3.new(x0 - 4 - stripe * 4, TOP + 0.2, 0), accent, Enum.Material.Neon,
					{ Transparency = 0.25 + 0.05 * (stripe % 2), CanCollide = false, CanQuery = false })
			end
		end

		-- 간판: 구역 이름 + 컨셉 + 몬스터 레벨
		local signPart = part("GateSign", Vector3.new(1, 1, 1), Vector3.new(x0 + 2, H + 24, 0), accent, Enum.Material.Neon, { Transparency = 1, CanCollide = false, CanQuery = false })
		local zoneSet = Config.Sets[Config.Sets.ZoneKeys[zone]]
		-- 간판: 큰 제목 한 줄 + 작은 줄 둘 (예전: 네 줄을 한 글자 상자에 몰아 넣어서 글자가 작고 서로 겹쳐 보였다). 가까이 갔을 때만 보인다.
		local sign = Instance.new("BillboardGui")
		sign.Name = "ZoneSignGui"
		sign.Size = UDim2.new(0, 360, 0, 104)
		sign.MaxDistance = zone == 1 and 40 or 80 -- (1구역 간판은 마을 문 바로 뒤라서 멀리서 보이면 문 위 큰 글씨와 겹친다: 가까이 와야 보인다)
		sign.AlwaysOnTop = false
		sign.Parent = signPart
		local function signLine(y, h, text, size, color, font)
			local line = Instance.new("TextLabel")
			line.Size = UDim2.new(1, 0, 0, h)
			line.Position = UDim2.new(0, 0, 0, y)
			line.BackgroundTransparency = 1
			line.Font = font or Enum.Font.GothamBold
			line.TextSize = size
			line.TextColor3 = color
			line.TextStrokeTransparency = 0.25
			line.Text = text
			line.Parent = sign
		end
		signLine(0, 44, string.format("Zone %d · %s", zone, F.ZoneNames[zone]), 32, Color3.fromRGB(255, 240, 190), Enum.Font.GothamBlack)
		-- (11-19 2축 신호: 권장 전투력 숫자는 빼고 위험도만 남긴다. 이 줄은 클라이언트(FieldSignalClient)가 내 예상 처치 시간 / 한 방 % 로 덮어쓴다)
		signLine(46, 24, string.format("Danger %s", string.rep("☠", zone)), 16, Color3.fromRGB(255, 255, 255))
		signLine(72, 22, string.format("%s New set: %s", zoneSet.Icon, zoneSet.Name), 15, Color3.fromRGB(190, 235, 255))
	end

	-- 바닥(평지 / 경사로 / 받침)은 "항상 불러오는" 모델에 담는다 (StreamingEnabled 여도 멀리 있는 바닥이 비지 않는다).
	--   오프닝 비행 때 카메라 아래 땅이 비어 보였다 (로그: x=2119 부터 '아래 지면 없음'). 바닥 조각은 수십 개라 항상 받아도 가볍다.
	--   모델 이름 = 바닥 이름 그대로 (오프닝 로딩이 "Ground" 로 시작하는 이름을 센다)
	local function makeFloorPart(props, parent)
		local holder = Instance.new("Model")
		holder.Name = props.Name
		holder.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		local part = makePart(props, holder)
		holder.Parent = parent
		return part
	end

	local function buildWorld()
		worldFolder = Instance.new("Folder")
		worldFolder.Name = "Field"
		worldFolder.Parent = workspace

		monstersFolder = Instance.new("Folder")
		monstersFolder.Name = "FieldMonsters"
		monstersFolder.Parent = workspace

		local half = F.Width / 2
		local totalLength = F.TotalLength()
		local rng = Random.new(77)

		for zone = 1, F.ZoneCount do
			local x0 = zoneBounds(zone)
			-- 바닥: 평지(층) 블록 + 좁은 계단통(양옆은 높은 벽, 가운데 폭 14 계단). 높은 층일수록 살짝 밝아져서 "층"이 구분된다
			for _, segment in ipairs(ZONE_SEGMENTS[zone]) do
				local top = TOP + segment.H
				local tint = F.ZoneColors[zone]:Lerp(Color3.new(1, 1, 1), 0.08 * segment.H / 24)
				if segment.Kind == "Floor" then
					makeFloorPart({
						Name = "Ground" .. zone, Size = Vector3.new(segment.B - segment.A, top + 1.95, F.Width),
						Position = Vector3.new(x0 + (segment.A + segment.B) / 2, (top - 1.95) / 2, 0), Color = tint, Material = F.ZoneMaterials[zone],
					}, worldFolder)
				else
					local stair = segment.Stair
					-- 경사로: 비스듬한 두꺼운 판 + 아래쪽을 받치는 바닥 덩어리 (표면은 시작 / 끝 높이에 딱 맞는다)
					local startY, endY = TOP + stair.From, TOP + stair.From + stair.Rise
					local length = math.sqrt(stair.Run * stair.Run + stair.Rise * stair.Rise)
					local angle = math.atan2(stair.Rise, stair.Run)
					local thickness = 6
					local midX, midY = x0 + stair.At + stair.Run / 2, (startY + endY) / 2
					-- 표면에서 두께의 절반만큼 아래(법선 반대 방향)로 중심을 내린다
					local center = Vector3.new(midX + math.sin(angle) * thickness / 2, midY - math.cos(angle) * thickness / 2, 0)
					makeFloorPart({
						Name = "Ramp" .. zone, Size = Vector3.new(length, thickness, F.Width),
						CFrame = CFrame.new(center) * CFrame.Angles(0, 0, angle),
						Color = Color3.fromRGB(205, 195, 180):Lerp(F.ZoneColors[zone], 0.3), Material = Enum.Material.Cobblestone,
					}, worldFolder)
					local lowY = math.min(startY, endY)
					makeFloorPart({
						Name = "RampBase" .. zone, Size = Vector3.new(stair.Run, math.max(0.5, lowY - thickness + 1.95), F.Width),
						Position = Vector3.new(midX, (lowY - thickness - 1.95) / 2, 0), Color = F.ZoneColors[zone], Material = F.ZoneMaterials[zone],
					}, worldFolder)
					for dx = 0, stair.Run, 14 do
						table.insert(baffleXs, x0 + stair.At + dx)
					end
				end
			end
			buildGateway(zone, x0)

			decorateZone(zone, rng)
			buildCamp(zone, x0)
		end

		-- 꺾임 벽: 구역마다 벽의 개수 / 종류 / 틈의 크기가 다르다 (ZONE_LAYOUTS). 길이 꺾이거나 갈라져서 한눈에 다 보이지 않는다.
		do
			for zone = 1, F.ZoneCount do
				local x0 = zoneBounds(zone)
				for _, wallSpec in ipairs(ZONE_LAYOUTS[zone].Baffles) do
					local offset, gapSize = wallSpec.Offset, wallSpec.Gap
					if zone == F.ZoneCount and x0 + offset > F.ZoneEnd(zone) - 110 then continue end -- 최후의 군주 포탈 주변은 벽 없이 탁 트이게
					local height = 96 + ((zone * 37 + offset * 7) % 43) -- 벽마다 높이가 다르다 (96~138: 위에서 내려다볼 때 똑같은 판이 줄지어 선 느낌을 없앤다)
					local color = F.ZoneColors[zone]:Lerp(Color3.fromRGB(70, 65, 72), 0.5)
					-- 이 위치의 땅 높이만큼 벽을 올려 세운다 (언덕 위에 서 있는 벽)
					local base = floorAt(x0 + offset) - TOP
					if wallSpec.Type == "Center" then
						local wallLength = F.Width - gapSize * 2
						makePart({
							Name = "Baffle", Size = Vector3.new(22, height, wallLength), Position = Vector3.new(x0 + offset, base + height / 2 - 2, 0),
							Color = color, Material = Enum.Material.Slate,
						}, worldFolder)
						table.insert(baffleXs, x0 + offset)
						table.insert(baffleRects, { X0 = x0 + offset - 11, X1 = x0 + offset + 11, Z0 = -wallLength / 2, Z1 = wallLength / 2, Top = base + height - 2 })
					else
						local side = wallSpec.Side or 1
						local wallLength = F.Width - gapSize
						local zCenter = -side * gapSize / 2
						makePart({
							Name = "Baffle", Size = Vector3.new(22, height, wallLength), Position = Vector3.new(x0 + offset, base + height / 2 - 2, zCenter),
							Color = color, Material = Enum.Material.Slate,
						}, worldFolder)
						table.insert(baffleXs, x0 + offset)
						table.insert(baffleRects, { X0 = x0 + offset - 11, X1 = x0 + offset + 11, Z0 = zCenter - wallLength / 2, Z1 = zCenter + wallLength / 2, Top = base + height - 2 })
					end
				end
			end
		end

		buildCanyon(rng, totalLength, half)

		-- 필드 가장자리 보이지 않는 벽 (옆면 / 끝 / 로비 쪽 입구 통로)
		local function wall(size, position)
			makePart({ Name = "Wall", Size = size, Position = position, Transparency = 1 }, worldFolder)
		end
		local centerX = F.StartX + totalLength / 2
		wall(Vector3.new(totalLength + 4, 240, 2), Vector3.new(centerX, 120, half + 1))
		wall(Vector3.new(totalLength + 4, 240, 2), Vector3.new(centerX, 120, -half - 1))
		wall(Vector3.new(2, 240, F.Width), Vector3.new(F.StartX + totalLength + 1, 120, 0))
		wall(Vector3.new(2, 50, half - 20), Vector3.new(F.StartX - 1, 25, (half + 20) / 2))
		wall(Vector3.new(2, 50, half - 20), Vector3.new(F.StartX - 1, 25, -(half + 20) / 2))
		wall(Vector3.new(26, 50, 2), Vector3.new(F.StartX - 14, 25, 21))
		wall(Vector3.new(26, 50, 2), Vector3.new(F.StartX - 14, 25, -21))

		-- 구역별 분위기 장식 (충돌 없는 장식 + 바닥 무늬, 실패해도 게임은 계속)
		local okDecor, decorErr = pcall(function() require(script.Parent:WaitForChild("FieldDecor")).Build(worldFolder, { FloorAt = floorAt, ZoneBounds = zoneBounds, Width = F.Width, Blocked = propBlocked, Baffles = baffleRects }) end)
		if not okDecor then warn("FieldDecor failed: " .. tostring(decorErr)) end
		local okQ, qErr = pcall(function() require(script.Parent:WaitForChild("FieldQuality", 5)).Build(worldFolder, { FloorAt = floorAt, ZoneBounds = zoneBounds, Width = F.Width, Baffles = baffleRects }) end) -- 1~2구역 화질 올리기 (절벽 / 큰 나무 / 먼 산 / 공중 연출)
		if not okQ then warn("FieldQuality failed: " .. tostring(qErr)) end
	end

	buildWorld()
	return worldFolder, monstersFolder
end

return FieldWorld
