-- NpcService (ServerScriptService > Modules 안의 ModuleScript, 이름: NpcService)
-- 마을의 NPC: 각 시설(모루 / 뽑기 / 필드 문 / 던전 게이트 / 심연 포탈) 옆에 서서 숨 쉬듯 흔들리고, 가까이 간 플레이어를 바라보며 말풍선으로 한마디씩 한다.
--   Npc.Init(ground, { { Name, Title, Position, Skin, Shirt, Pants, Hat, Prop, Lines }... })
--   Position = 시설 위치(대화 상자 위치): NPC 는 마을 중앙 쪽으로 6 스터드 떨어진 곳에 선다

local Players = game:GetService("Players")

local Npc = {}

local npcs = {}

local function newPart(model, shape, size, color, material, props)
	local part = Instance.new("Part")
	part.Shape = shape or Enum.PartType.Block
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	for key, value in pairs(props or {}) do part[key] = value end
	part.Parent = model
	return part
end

local Block, Ball = Enum.PartType.Block, Enum.PartType.Ball

-- 블록 인형: 몸통 중심이 PrimaryPart. 발바닥이 y=0 이 되게 높이 5.4 로 만든다.
local function build(def, position)
	local model = Instance.new("Model")
	model.Name = "Npc_" .. def.Name
	local skin = def.Skin or Color3.fromRGB(240, 200, 160)
	local shirt = def.Shirt or Color3.fromRGB(90, 120, 190)
	local pants = def.Pants or Color3.fromRGB(60, 62, 80)

	local torso = newPart(model, Block, Vector3.new(2, 2, 1), shirt, Enum.Material.Fabric)
	torso.Name = "Torso"
	torso.CFrame = CFrame.new(position + Vector3.new(0, 3.4, 0))
	model.PrimaryPart = torso

	local function limb(size, offset, color, material)
		return newPart(model, Block, size, color, material, { CFrame = torso.CFrame * CFrame.new(offset) })
	end
	local head = newPart(model, Block, Vector3.new(1.4, 1.4, 1.4), skin, Enum.Material.SmoothPlastic, { Name = "Head", CFrame = torso.CFrame * CFrame.new(0, 1.8, 0) })
	local face = Instance.new("Decal")
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head
	limb(Vector3.new(1, 2, 1), Vector3.new(-1.5, 0, 0), shirt, Enum.Material.Fabric).Name = "ArmL"
	local armR = limb(Vector3.new(1, 2, 1), Vector3.new(1.5, 0, 0), shirt, Enum.Material.Fabric)
	armR.Name = "ArmR"
	limb(Vector3.new(0.9, 0.5, 0.9), Vector3.new(-1.5, -1.2, 0), skin) -- 손
	limb(Vector3.new(0.9, 0.5, 0.9), Vector3.new(1.5, -1.2, 0), skin)
	limb(Vector3.new(1, 2, 1), Vector3.new(-0.5, -2, 0), pants)
	limb(Vector3.new(1, 2, 1), Vector3.new(0.5, -2, 0), pants)
	limb(Vector3.new(1.05, 0.5, 1.15), Vector3.new(-0.5, -3.15, -0.05), Color3.fromRGB(40, 36, 36))
	limb(Vector3.new(1.05, 0.5, 1.15), Vector3.new(0.5, -3.15, -0.05), Color3.fromRGB(40, 36, 36))

	-- 모자 / 소품
	local hat = def.Hat
	local accent = def.Accent or Color3.fromRGB(150, 90, 50)
	if hat == "cap" then
		newPart(model, Block, Vector3.new(1.55, 0.4, 1.55), accent, Enum.Material.Fabric, { CFrame = head.CFrame * CFrame.new(0, 0.8, 0) })
		newPart(model, Block, Vector3.new(1.4, 0.2, 0.7), accent, Enum.Material.Fabric, { CFrame = head.CFrame * CFrame.new(0, 0.65, -0.95) })
	elseif hat == "wizard" then
		newPart(model, Block, Vector3.new(2.2, 0.2, 2.2), accent, Enum.Material.Fabric, { CFrame = head.CFrame * CFrame.new(0, 0.75, 0) })
		newPart(model, Block, Vector3.new(1.2, 1.4, 1.2), accent, Enum.Material.Fabric, { CFrame = head.CFrame * CFrame.new(0, 1.5, 0) * CFrame.Angles(0, 0, math.rad(6)) })
		newPart(model, Ball, Vector3.new(0.5, 0.5, 0.5), Color3.fromRGB(255, 225, 120), Enum.Material.Neon, { CFrame = head.CFrame * CFrame.new(0.1, 2.3, 0) })
	elseif hat == "helmet" then
		newPart(model, Block, Vector3.new(1.6, 0.9, 1.6), Color3.fromRGB(150, 156, 170), Enum.Material.Metal, { CFrame = head.CFrame * CFrame.new(0, 0.55, 0) })
		newPart(model, Block, Vector3.new(0.2, 0.9, 1.2), accent, Enum.Material.Fabric, { CFrame = head.CFrame * CFrame.new(0, 1.3, 0) }) -- 투구 깃
	elseif hat == "hood" then
		newPart(model, Block, Vector3.new(1.7, 1.6, 1.7), accent, Enum.Material.Fabric, { CFrame = head.CFrame * CFrame.new(0, 0.2, 0.25) })
		head.CFrame = head.CFrame * CFrame.new(0, 0, -0.15)
	end
	local prop = def.Prop
	local handPos = torso.CFrame * CFrame.new(1.5, -1.2, -0.3)
	if prop == "hammer" then
		newPart(model, Block, Vector3.new(0.35, 2.6, 0.35), Color3.fromRGB(110, 80, 50), Enum.Material.Wood, { CFrame = handPos * CFrame.new(0, 0.6, 0) })
		newPart(model, Block, Vector3.new(1.6, 0.9, 0.9), Color3.fromRGB(110, 114, 126), Enum.Material.Metal, { CFrame = handPos * CFrame.new(0, 1.9, 0) })
	elseif prop == "spear" then
		newPart(model, Block, Vector3.new(0.3, 6.6, 0.3), Color3.fromRGB(120, 90, 60), Enum.Material.Wood, { CFrame = handPos * CFrame.new(0, 1.5, 0) })
		newPart(model, Block, Vector3.new(0.6, 1.2, 0.3), Color3.fromRGB(190, 196, 210), Enum.Material.Metal, { CFrame = handPos * CFrame.new(0, 5.2, 0) })
	elseif prop == "staff" then
		newPart(model, Block, Vector3.new(0.3, 5.4, 0.3), Color3.fromRGB(100, 70, 120), Enum.Material.Wood, { CFrame = handPos * CFrame.new(0, 1.1, 0) })
		local orb = newPart(model, Ball, Vector3.new(0.9, 0.9, 0.9), accent, Enum.Material.Neon, { CFrame = handPos * CFrame.new(0, 4.0, 0) })
		local light = Instance.new("PointLight")
		light.Color, light.Range, light.Brightness = accent, 9, 0.8
		light.Parent = orb
	elseif prop == "lantern" then
		newPart(model, Block, Vector3.new(0.9, 1.2, 0.9), Color3.fromRGB(255, 210, 130), Enum.Material.Neon, { CFrame = handPos * CFrame.new(0, -0.9, 0) })
	end

	-- 이름 + 말풍선
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 220, 0, 74)
	gui.StudsOffset = Vector3.new(0, 3.4, 0)
	gui.MaxDistance = 55
	gui.AlwaysOnTop = true -- 가게 지붕 / 간판 뒤에 서 있어도 이름과 대사가 가려지지 않게
	gui.Parent = head
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 22)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 16
	title.TextColor3 = Color3.fromRGB(255, 232, 160)
	title.TextStrokeTransparency = 0.4
	title.Text = def.Title and (def.Title .. "  " .. def.Name) or def.Name
	title.Parent = gui
	local bubble = Instance.new("TextLabel")
	bubble.Size = UDim2.new(1, 0, 0, 44)
	bubble.Position = UDim2.new(0, 0, 0, 26)
	bubble.BackgroundColor3 = Color3.fromRGB(250, 248, 240)
	bubble.BackgroundTransparency = 0.05
	bubble.Font = Enum.Font.GothamBold
	bubble.TextSize = 14
	bubble.TextColor3 = Color3.fromRGB(40, 36, 50)
	bubble.TextWrapped = true
	bubble.Text = ""
	bubble.Visible = false
	bubble.Parent = gui
	Instance.new("UICorner", bubble).CornerRadius = UDim.new(0, 10)

	return model, bubble
end

-- 이름별 고정 서는 자리 (Lift: 가게 바닥 높이 / FaceX, FaceZ: 처음 바라보는 쪽)
local STANDS = {
	["톰"] = { X = -41.4, Z = 23, Lift = 0.6, FaceX = 0, FaceZ = 28 },     -- 대장간 카운터 뒤 (모루 옆)
	["루나"] = { X = 40.8, Z = 33.5, Lift = 0.6, FaceX = 0, FaceZ = 28 },  -- 뽑기 상점 카운터 뒤 (머신 옆)
	["카이"] = { X = 113, Z = 10.5, FaceX = 90, FaceZ = 0 },               -- 필드 문 안쪽, 길 옆 초소
	["벨"] = { X = -15.5, Z = -87, FaceX = 0, FaceZ = -40 },               -- 던전 게이트 구역 입구 아치 옆
	["미라"] = { X = 62.5, Z = 86, FaceX = 40, FaceZ = 78 },               -- 심연 포탈 제단 앞 (광장 쪽을 바라봄)
}

function Npc.Init(groundY, list)
	local folder = Instance.new("Folder")
	folder.Name = "Npcs"
	folder.Parent = workspace
	for _, def in ipairs(list) do
		local flat = Vector3.new(def.Position.X, 0, def.Position.Z)
		local toCenter = flat.Magnitude > 1 and -flat.Unit or Vector3.new(0, 0, 1)
		local standAt = Vector3.new(def.Position.X, groundY, def.Position.Z) + toCenter * 6
		local startYaw = 0
		local stand = STANDS[def.Name]
		if stand then -- 마을 배치에 맞춘 고정 자리 (가게 카운터 뒤 / 문 옆 / 길 옆), 오는 길 쪽을 바라본다
			standAt = Vector3.new(stand.X, groundY + (stand.Lift or 0), stand.Z)
			startYaw = math.atan2(-(stand.FaceX - stand.X), -(stand.FaceZ - stand.Z))
		end
		local model, bubble = build(def, standAt)
		model.Parent = folder
		table.insert(npcs, { Model = model, Bubble = bubble, Base = model:GetPivot(), Def = def, Phase = math.random() * 6, NextLine = 0, Line = 1, Yaw = startYaw })
	end
	task.spawn(function()
		while true do
			task.wait(0.1)
			local now = os.clock()
			for _, npc in ipairs(npcs) do
				-- 가장 가까운 플레이어
				local nearest, nearestDist
				for _, player in ipairs(Players:GetPlayers()) do
					local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if root and player:GetAttribute("Zone") == "Lobby" then
						local dist = (root.Position - npc.Base.Position).Magnitude
						if not nearestDist or dist < nearestDist then nearest, nearestDist = root, dist end
					end
				end
				local pivot = npc.Base * CFrame.new(0, math.sin(now * 1.8 + npc.Phase) * 0.08, 0) -- 숨 쉬듯 살짝 위아래
				if nearest and nearestDist < 32 then
					local look = Vector3.new(nearest.Position.X - npc.Base.Position.X, 0, nearest.Position.Z - npc.Base.Position.Z)
					if look.Magnitude > 0.1 then
						local targetYaw = math.atan2(-look.X, -look.Z)
						local diff = (targetYaw - npc.Yaw + math.pi) % (2 * math.pi) - math.pi
						npc.Yaw += diff * 0.35 -- 천천히 돌아본다
					end
				end
				npc.Model:PivotTo(CFrame.new(pivot.Position) * CFrame.Angles(0, npc.Yaw, 0))
				-- 말풍선: 가까이 가면 몇 초마다 다른 대사
				if nearest and nearestDist < 22 and npc.Def.Lines and #npc.Def.Lines > 0 then
					if now >= npc.NextLine then
						npc.NextLine = now + 5
						npc.Line = npc.Line % #npc.Def.Lines + 1
						npc.Bubble.Text = npc.Def.Lines[npc.Line]
					end
					npc.Bubble.Visible = true
				else
					npc.Bubble.Visible = false
				end
			end
		end
	end)
end

return Npc
