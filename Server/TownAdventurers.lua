-- TownAdventurers (ServerScriptService > Modules 안의 ModuleScript, 이름: TownAdventurers)
-- 마을을 돌아다니는 "모험가 NPC": 플레이어처럼 생긴 사람 모양 캐릭터가 광장 / 대장간 / 뽑기 / 훈련장 / 쉼터 / 던전 게이트 사이를 걸어 다니고,
-- 가끔 말풍선으로 한마디 하거나 가까이 온 플레이어에게 손을 흔든다. 마을이 비어 보이지 않게 하는 용도.
--   * 진짜 플레이어로 착각하지 않게 머리 위에 항상 "Adventurer NPC" 표시를 단다 (가짜 접속자처럼 보이게 하지 않는다)
--   * 플레이어와 부딪히지 않는다 (충돌 그룹): 문 / 계단 / 상점 앞을 막지 않는다
--   * 마을에 플레이어가 아무도 없으면 쉬고 있는다 (서버 부담)
--   TownAdventurers.Init(groundY, spots)  spots = { Vector3, ... } 걸어갈 목적지 (땅 높이 기준)

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local PhysicsService = game:GetService("PhysicsService")

local Town = {}

local NPC_GROUP, PLAYER_GROUP = "TownNpc", "TownPlayer"

local ANIM = {
	Idle = "rbxassetid://507766388",
	Walk = "rbxassetid://507777826",
	Wave = "rbxassetid://507770239",
	Cheer = "rbxassetid://507770677",
}

local SKINS = { Color3.fromRGB(255, 220, 177), Color3.fromRGB(234, 184, 146), Color3.fromRGB(204, 142, 105), Color3.fromRGB(160, 110, 80), Color3.fromRGB(110, 76, 56), Color3.fromRGB(253, 234, 141) }

-- 모험가 7명: 이름 / 옷 색 / 모자 / 등에 멘 것
local ROSTER = {
	{ Name = "Rook", Shirt = Color3.fromRGB(196, 72, 64), Pants = Color3.fromRGB(52, 56, 74), Hat = "cap", Hat2 = Color3.fromRGB(40, 44, 60), Back = "sword" },
	{ Name = "Hana", Shirt = Color3.fromRGB(246, 168, 196), Pants = Color3.fromRGB(240, 240, 248), Hat = "bow", Hat2 = Color3.fromRGB(255, 255, 255), Back = "staff" },
	{ Name = "Milo", Shirt = Color3.fromRGB(80, 150, 90), Pants = Color3.fromRGB(110, 84, 60), Hat = "hood", Hat2 = Color3.fromRGB(60, 110, 66), Back = "bow" },
	{ Name = "Sora", Shirt = Color3.fromRGB(80, 140, 220), Pants = Color3.fromRGB(36, 40, 56), Hat = "beanie", Hat2 = Color3.fromRGB(250, 210, 80), Back = "pack" },
	{ Name = "Ivy", Shirt = Color3.fromRGB(150, 100, 200), Pants = Color3.fromRGB(60, 46, 84), Hat = "wizard", Hat2 = Color3.fromRGB(110, 70, 170), Back = "staff" },
	{ Name = "Dex", Shirt = Color3.fromRGB(60, 60, 66), Pants = Color3.fromRGB(30, 30, 34), Hat = "band", Hat2 = Color3.fromRGB(220, 60, 60), Back = "sword" },
	{ Name = "Nori", Shirt = Color3.fromRGB(250, 200, 90), Pants = Color3.fromRGB(80, 110, 160), Hat = "cap", Hat2 = Color3.fromRGB(240, 120, 50), Back = "pack" },
}

local LINES = {
	"Just got a new weapon from Tom!",
	"The Zone 2 lord hits hard... time to train more.",
	"Anyone up for a dungeon run?",
	"Come on, gacha... give me something good!",
	"Resting by the campfire earns gold even while idle.",
	"I'll beat the Final Lord someday!",
	"Don't forget your free daily dungeon entries!",
	"My gear just hit +10!",
	"Skills feel amazing once your cooldowns are low.",
	"Field lords drop keys. Grab them!",
}
local GREETINGS = { "Hey there!", "Good luck out there!", "Nice gear!" }

local active = {}

local function setupCollision()
	pcall(function()
		PhysicsService:RegisterCollisionGroup(NPC_GROUP)
		PhysicsService:RegisterCollisionGroup(PLAYER_GROUP)
		PhysicsService:CollisionGroupSetCollidable(NPC_GROUP, PLAYER_GROUP, false)
		PhysicsService:CollisionGroupSetCollidable(NPC_GROUP, NPC_GROUP, false)
	end)
	local function tagCharacter(character)
		local function tag(item)
			if item:IsA("BasePart") and item.CollisionGroup == "Default" then item.CollisionGroup = PLAYER_GROUP end
		end
		for _, item in ipairs(character:GetDescendants()) do tag(item) end
		character.DescendantAdded:Connect(tag)
	end
	local function onPlayer(player)
		player.CharacterAdded:Connect(tagCharacter)
		if player.Character then tagCharacter(player.Character) end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do onPlayer(player) end
end

local function deco(parent, anchor, size, offset, color, material, shape)
	local part = Instance.new("Part")
	part.Name = "Gear"
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	if shape then part.Shape = shape end
	part.CanCollide, part.CanQuery, part.CanTouch, part.Massless, part.CastShadow = false, false, false, true, false
	part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	part.CFrame = anchor.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = anchor, part
	weld.Parent = part
	part.Parent = parent
	return part
end

local function dressUp(model, def)
	local head = model:FindFirstChild("Head")
	local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
	if not head or not torso then return end
	local c = def.Hat2
	local hs = head.Size.Y
	if def.Hat == "cap" then
		deco(model, head, Vector3.new(hs * 1.08, hs * 0.32, hs * 1.08), CFrame.new(0, hs * 0.42, 0.04), c, Enum.Material.Fabric)
		deco(model, head, Vector3.new(hs * 0.9, hs * 0.1, hs * 0.55), CFrame.new(0, hs * 0.3, -hs * 0.68), c, Enum.Material.Fabric)
	elseif def.Hat == "beanie" then
		deco(model, head, Vector3.new(hs * 1.1, hs * 0.5, hs * 1.1), CFrame.new(0, hs * 0.38, 0), c, Enum.Material.Fabric)
		deco(model, head, Vector3.new(hs * 0.35, hs * 0.35, hs * 0.35), CFrame.new(0, hs * 0.72, 0), Color3.fromRGB(255, 255, 255), Enum.Material.Fabric, Enum.PartType.Ball)
	elseif def.Hat == "hood" then
		deco(model, head, Vector3.new(hs * 1.18, hs * 1.12, hs * 1.15), CFrame.new(0, hs * 0.08, hs * 0.12), c, Enum.Material.Fabric)
	elseif def.Hat == "wizard" then
		deco(model, head, Vector3.new(hs * 1.7, hs * 0.12, hs * 1.7), CFrame.new(0, hs * 0.5, 0), c, Enum.Material.Fabric)
		deco(model, head, Vector3.new(hs * 0.9, hs * 1.1, hs * 0.9), CFrame.new(0, hs * 1.05, 0.05) * CFrame.Angles(math.rad(-8), 0, math.rad(6)), c, Enum.Material.Fabric)
	elseif def.Hat == "band" then
		deco(model, head, Vector3.new(hs * 1.06, hs * 0.18, hs * 1.06), CFrame.new(0, hs * 0.25, 0), c, Enum.Material.Fabric)
		deco(model, head, Vector3.new(hs * 0.12, hs * 0.5, hs * 0.18), CFrame.new(hs * 0.2, hs * 0.05, hs * 0.6) * CFrame.Angles(0, 0, math.rad(20)), c, Enum.Material.Fabric)
	elseif def.Hat == "bow" then
		deco(model, head, Vector3.new(hs * 0.3, hs * 0.3, hs * 0.3), CFrame.new(hs * 0.45, hs * 0.45, 0), c, Enum.Material.Fabric, Enum.PartType.Ball)
		deco(model, head, Vector3.new(hs * 0.3, hs * 0.3, hs * 0.3), CFrame.new(hs * 0.45, hs * 0.45, hs * 0.32), c, Enum.Material.Fabric, Enum.PartType.Ball)
	end
	local ty = torso.Size.Y
	local back = CFrame.new(0, 0, torso.Size.Z / 2 + 0.2)
	if def.Back == "sword" then
		deco(model, torso, Vector3.new(0.25, ty * 2.2, 0.55), back * CFrame.Angles(0, 0, math.rad(35)), Color3.fromRGB(200, 206, 220), Enum.Material.Metal)
		deco(model, torso, Vector3.new(0.3, 0.3, 1.1), back * CFrame.Angles(0, 0, math.rad(35)) * CFrame.new(0, -ty * 0.75, 0), Color3.fromRGB(150, 110, 60), Enum.Material.Wood)
	elseif def.Back == "staff" then
		deco(model, torso, Vector3.new(0.22, ty * 2.6, 0.22), back * CFrame.Angles(0, 0, math.rad(-30)), Color3.fromRGB(110, 80, 56), Enum.Material.Wood)
		deco(model, torso, Vector3.new(0.6, 0.6, 0.6), back * CFrame.Angles(0, 0, math.rad(-30)) * CFrame.new(0, ty * 1.35, 0), def.Hat2, Enum.Material.Glass, Enum.PartType.Ball)
	elseif def.Back == "bow" then
		deco(model, torso, Vector3.new(0.18, ty * 2, 0.18), back * CFrame.Angles(0, 0, math.rad(25)), Color3.fromRGB(120, 86, 50), Enum.Material.Wood)
		deco(model, torso, Vector3.new(0.6, ty * 0.9, 0.6), back * CFrame.new(-0.4, 0.1, 0.25), Color3.fromRGB(130, 90, 60), Enum.Material.Fabric, Enum.PartType.Cylinder)
	elseif def.Back == "pack" then
		deco(model, torso, Vector3.new(torso.Size.X * 0.8, ty * 0.85, 0.7), back * CFrame.new(0, -0.05, 0.2), Color3.fromRGB(140, 100, 64), Enum.Material.Fabric)
		deco(model, torso, Vector3.new(torso.Size.X * 0.82, ty * 0.25, 0.75), back * CFrame.new(0, ty * 0.38, 0.2), Color3.fromRGB(110, 76, 48), Enum.Material.Fabric)
	end
end

local function nameTag(model, def)
	local head = model:FindFirstChild("Head")
	if not head then return nil end
	local gui = Instance.new("BillboardGui")
	gui.Name = "AdventurerTag"
	gui.Size = UDim2.new(0, 220, 0, 82)
	gui.StudsOffset = Vector3.new(0, 3.2, 0)
	gui.MaxDistance = 70
	gui.Parent = head
	local bubble = Instance.new("TextLabel")
	bubble.Name = "Bubble"
	bubble.Size = UDim2.new(1, 0, 0, 40)
	bubble.BackgroundColor3 = Color3.fromRGB(250, 248, 240)
	bubble.BackgroundTransparency = 0.05
	bubble.Font = Enum.Font.GothamBold
	bubble.TextSize = 12
	bubble.TextColor3 = Color3.fromRGB(40, 36, 50)
	bubble.TextWrapped = true
	bubble.Visible = false
	bubble.Parent = gui
	Instance.new("UICorner", bubble).CornerRadius = UDim.new(0, 10)
	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, 0, 0, 22)
	name.Position = UDim2.new(0, 0, 0, 44)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBlack
	name.TextSize = 15
	name.TextColor3 = Color3.fromRGB(255, 255, 255)
	name.TextStrokeTransparency = 0.35
	name.Text = def.Name
	name.Parent = gui
	local tag = Instance.new("TextLabel")
	tag.Size = UDim2.new(1, 0, 0, 14)
	tag.Position = UDim2.new(0, 0, 0, 64)
	tag.BackgroundTransparency = 1
	tag.Font = Enum.Font.GothamBold
	tag.TextSize = 11
	tag.TextColor3 = Color3.fromRGB(170, 220, 255)
	tag.TextStrokeTransparency = 0.4
	tag.Text = "Adventurer NPC"
	tag.Parent = gui
	return bubble
end

local function build(def, at, folder)
	local desc = Instance.new("HumanoidDescription")
	local skin = SKINS[math.random(1, #SKINS)]
	desc.HeadColor = skin
	desc.TorsoColor = def.Shirt
	desc.LeftArmColor, desc.RightArmColor = def.Shirt, def.Shirt
	desc.LeftLegColor, desc.RightLegColor = def.Pants, def.Pants
	local ok, model = pcall(function() return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15) end)
	if not ok or not model then
		warn("[TownAdventurers] 캐릭터를 만들지 못했습니다: " .. tostring(model))
		return nil
	end
	model.Name = "Adventurer_" .. def.Name
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then model:Destroy() return nil end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.WalkSpeed = math.random(11, 14)
	humanoid.MaxHealth, humanoid.Health = 100, 100
	humanoid.BreakJointsOnDeath = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	model:PivotTo(CFrame.new(at + Vector3.new(0, 3.5, 0)) * CFrame.Angles(0, math.random() * 6.28, 0))
	dressUp(model, def)
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") then
			item.CollisionGroup = NPC_GROUP
			item.CanTouch = false
		end
	end
	local bubble = nameTag(model, def)
	model.Parent = folder
	pcall(function() root:SetNetworkOwner(nil) end) -- 서버가 움직인다 (플레이어 컴퓨터에 넘기지 않는다)

	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	local tracks = {}
	for key, id in pairs(ANIM) do
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local okLoad, track = pcall(function() return animator:LoadAnimation(anim) end)
		if okLoad and track then tracks[key] = track end
	end
	if tracks.Idle then tracks.Idle.Looped = true tracks.Idle:Play() end
	if tracks.Walk then tracks.Walk.Looped = true end
	humanoid.Running:Connect(function(speed)
		if not tracks.Walk then return end
		if speed > 0.5 then
			if not tracks.Walk.IsPlaying then tracks.Walk:Play(0.15) end
			tracks.Walk:AdjustSpeed(humanoid.WalkSpeed / 14)
		elseif tracks.Walk.IsPlaying then
			tracks.Walk:Stop(0.2)
		end
	end)
	return { Model = model, Humanoid = humanoid, Root = root, Bubble = bubble, Tracks = tracks, Def = def, Home = at }
end

local function say(npc, text, seconds)
	if not npc.Bubble then return end
	npc.Bubble.Text = text
	npc.Bubble.Visible = true
	local token = {}
	npc.SayToken = token
	task.delay(seconds or 4, function()
		if npc.SayToken == token and npc.Bubble then npc.Bubble.Visible = false end
	end)
end

local function anyoneInTown()
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("Zone") == "Lobby" or player:GetAttribute("Zone") == nil then return true end
	end
	return false
end

local function nearestPlayer(position, radius)
	local best, bestDist
	for _, player in ipairs(Players:GetPlayers()) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local dist = (root.Position - position).Magnitude
			if dist < radius and (not bestDist or dist < bestDist) then best, bestDist = root, dist end
		end
	end
	return best
end

-- 길 따라 걷기: 경로를 못 찾거나 오래 막히면 포기하고 다른 곳을 고른다
local function walkTo(npc, target)
	local path = PathfindingService:CreatePath({ AgentRadius = 2.5, AgentHeight = 5.5, AgentCanJump = false, WaypointSpacing = 6 })
	local ok = pcall(function() path:ComputeAsync(npc.Root.Position, target) end)
	if not ok or path.Status ~= Enum.PathStatus.Success then return false end
	local stuck = 0
	for _, waypoint in ipairs(path:GetWaypoints()) do
		if not npc.Model.Parent then return false end
		npc.Humanoid:MoveTo(waypoint.Position)
		local started = os.clock()
		while os.clock() - started < 3 do
			task.wait(0.15)
			local flat = Vector3.new(waypoint.Position.X - npc.Root.Position.X, 0, waypoint.Position.Z - npc.Root.Position.Z)
			if flat.Magnitude < 2.5 then break end
		end
		if os.clock() - started >= 3 then
			stuck += 1
			if stuck >= 2 then return false end
		end
	end
	return true
end

local function faceToward(npc, position)
	local here = npc.Root.Position
	local look = Vector3.new(position.X, here.Y, position.Z)
	if (look - here).Magnitude > 0.5 then
		npc.Root.CFrame = CFrame.lookAt(here, look)
	end
end

local function life(npc, spots, groundY)
	task.wait(math.random() * 4)
	local last
	while npc.Model.Parent do
		if not anyoneInTown() then
			npc.Humanoid:MoveTo(npc.Root.Position)
			task.wait(3)
			continue
		end
		if npc.Root.Position.Y < groundY - 30 then -- 떨어졌으면 광장으로 되돌린다
			npc.Model:PivotTo(CFrame.new(npc.Home + Vector3.new(0, 3.5, 0)))
		end
		local target
		repeat target = spots[math.random(1, #spots)] until target ~= last or #spots < 2
		last = target
		local jitter = Vector3.new(math.random(-8, 8), 0, math.random(-8, 8))
		walkTo(npc, target + jitter)
		-- 도착: 잠깐 서서 쉬거나, 한마디 하거나, 기뻐하거나, 가까운 플레이어에게 손을 흔든다
		local roll = math.random()
		local friend = nearestPlayer(npc.Root.Position, 16)
		if friend and roll < 0.5 then
			faceToward(npc, friend.Position)
			if npc.Tracks.Wave then npc.Tracks.Wave:Play(0.2) end
			say(npc, GREETINGS[math.random(1, #GREETINGS)], 3)
		elseif roll < 0.45 then
			say(npc, LINES[math.random(1, #LINES)], 4.5)
		elseif roll < 0.6 and npc.Tracks.Cheer then
			npc.Tracks.Cheer:Play(0.2)
		end
		task.wait(math.random(4, 10))
	end
end

function Town.Init(groundY, spots)
	if not spots or #spots == 0 then return end
	setupCollision()
	local folder = Instance.new("Folder")
	folder.Name = "TownAdventurers"
	folder.Parent = workspace
	for index, def in ipairs(ROSTER) do
		local npc = build(def, spots[(index - 1) % #spots + 1], folder)
		if npc then
			table.insert(active, npc)
			task.spawn(life, npc, spots, groundY)
		end
		task.wait() -- (만들기를 한 프레임씩 나눈다)
	end
end

return Town
