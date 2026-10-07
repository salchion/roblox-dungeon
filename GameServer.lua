-- GameServer (ServerScriptService 안의 Script)
-- 게임 전체의 진입점. 로비 / 필드 / 던전, 플레이어 세팅, 공격 처리, 무기·장비 강화 요청을 서로 연결한다.
--
-- 구조 (자세한 배치는 README.md 참고)
--   ReplicatedStorage:      Config, Remotes, AudioIds (ModuleScript)
--   ServerScriptService:    GameServer (이 Script) + Modules 폴더(Effects, WeaponService, GearService, PartyService,
--                           LobbyService, DummyService, FieldService, DungeonService, DataService)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes")) -- RemoteEvent 들이 여기서 만들어짐

local Modules = ServerScriptService:WaitForChild("Modules")
local Effects = require(Modules:WaitForChild("Effects"))
local Weapon = require(Modules:WaitForChild("WeaponService"))
local Gear = require(Modules:WaitForChild("GearService"))
local Party = require(Modules:WaitForChild("PartyService"))
local Lobby = require(Modules:WaitForChild("LobbyService"))
local Dummy = require(Modules:WaitForChild("DummyService"))
local Dungeon = require(Modules:WaitForChild("DungeonService"))
local Field = require(Modules:WaitForChild("FieldService"))
local Data = require(Modules:WaitForChild("DataService"))

------------------------------------------------------------
-- 로비 / 게이트 / 강화대 / 뽑기 머신 / 허수아비 / 필드
------------------------------------------------------------
local lobby = Lobby.Build()
Dungeon.Init(lobby.SpawnCFrame)
Dummy.Build(lobby.DummyStart)
Field.Init()

-- 던전 게이트: 파티가 있으면 파티장만 입장 가능 (검사는 Dungeon.Start 안에서)
lobby.GatePrompt.Triggered:Connect(function(player)
	Dungeon.Start(player)
end)

lobby.AnvilPrompt.Triggered:Connect(function(player)
	if player:GetAttribute("Zone") == "Lobby" then
		Remotes.OpenEnhance:FireClient(player)
	end
end)

lobby.GachaPrompt.Triggered:Connect(function(player)
	if player:GetAttribute("Zone") == "Lobby" then
		Remotes.OpenGear:FireClient(player)
	end
end)

------------------------------------------------------------
-- 플레이어
------------------------------------------------------------
local function onCharacterAdded(player, character)
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None -- 기본 이름표 대신 전투력/무기 레벨이 보이는 이름표 사용
	humanoid.MaxHealth = Dungeon.GetMaxHealth(player)
	humanoid.Health = humanoid.MaxHealth

	Dungeon.OnCharacterAdded(player, character)

	character:WaitForChild("Head")
	Weapon.Refresh(player)
	task.wait(0.2) -- 몸 부위가 다 붙은 뒤 장비 외형을 씌운다
	Gear.ApplyVisuals(player)
end

-- 전투력 = 무기 강화 + 스탯 + 장비 (이름표 / 리더보드에 표시)
local function updatePower(player)
	player:SetAttribute("Power", Config.GetPower(
		player:GetAttribute("WeaponLevel") or 0,
		player:GetAttribute("CritPoints") or 0,
		player:GetAttribute("SpeedPoints") or 0,
		player:GetAttribute("GearHealth") or 0,
		player:GetAttribute("GearCrit") or 0
	))
end

local function setupPlayer(player)
	-- 3인칭 카메라 (1인칭으로 들어가지 못하게 최소 거리를 둠)
	player.CameraMode = Enum.CameraMode.Classic
	player.CameraMinZoomDistance = 8
	player.CameraMaxZoomDistance = 60

	player:SetAttribute("Zone", "Lobby")
	player:SetAttribute("PartyId", 0)
	player:SetAttribute("Gold", 0)
	player:SetAttribute("Tickets", 0)
	player:SetAttribute("WeaponLevel", 0)
	player:SetAttribute("MaxZone", 0)
	player:SetAttribute("Power", 0)
	for _, attribute in pairs(Config.StatAttributes) do
		player:SetAttribute(attribute, 0)
	end
	player:SetAttribute("StatPoints", 0)

	Gear.Load(player, nil) -- 빈 장비로 시작 (저장 데이터는 아래에서 덮어씀)
	Gear.Watch(player)

	-- 리더보드: 전투력 / 골드 / 무기 / 티켓
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local function addStat(name, attribute, onChange)
		local value = Instance.new("IntValue")
		value.Name = name
		value.Parent = leaderstats
		player:GetAttributeChangedSignal(attribute):Connect(function()
			value.Value = player:GetAttribute(attribute) or 0
			if onChange then
				onChange()
			end
		end)
	end
	addStat("전투력", "Power", function() Weapon.UpdateNameplate(player) end)
	addStat("Gold", "Gold")
	addStat("Weapon", "WeaponLevel")
	addStat("Tickets", "Tickets")

	-- 무기 강화 즉시 무기 외형 변경 (모든 플레이어에게 보임) + 전투력 갱신
	player:GetAttributeChangedSignal("WeaponLevel"):Connect(function()
		Weapon.Refresh(player)
		updatePower(player)
	end)
	for _, attribute in ipairs({ "CritPoints", "SpeedPoints", "GearHealth", "GearCrit" }) do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			updatePower(player)
		end)
	end
	-- 장비로 최대 체력이 바뀌면 바로 반영
	player:GetAttributeChangedSignal("GearHealth"):Connect(function()
		Dungeon.RefreshMaxHealth(player)
	end)
	player:GetAttributeChangedSignal("PartyId"):Connect(function()
		Weapon.UpdateNameplate(player)
	end)
	player:GetAttributeChangedSignal("MaxZone"):Connect(function()
		Weapon.UpdateNameplate(player)
	end)

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end

	-- 저장된 데이터 적용 (DataStore 대기 중에도 캐릭터는 이미 스폰될 수 있음)
	local saved = Data.Load(player)
	if player.Parent then
		player:SetAttribute("Gold", saved.Gold)
		player:SetAttribute("Tickets", saved.Tickets)
		player:SetAttribute("MaxZone", saved.MaxZone)
		player:SetAttribute("WeaponLevel", saved.WeaponLevel)
		Gear.Load(player, saved.Gear)
		updatePower(player)
	end
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(setupPlayer, player)
end

local lastAttack = {}
local lastEnhance = {}
local lastGear = {}

Players.PlayerRemoving:Connect(function(player)
	lastAttack[player] = nil
	lastEnhance[player] = nil
	lastGear[player] = nil
	Party.OnPlayerRemoving(player)
	Dungeon.OnPlayerRemoving(player)
	Data.Save(player)
	Data.Forget(player)
end)

task.spawn(function()
	while true do
		task.wait(60)
		for _, player in ipairs(Players:GetPlayers()) do
			Data.Save(player)
		end
	end
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(Data.Save, player)
	end
	task.wait(2)
end)

------------------------------------------------------------
-- 공격: 클라이언트는 마우스가 가리키는 지점만 보내고, 맞았는지는 서버가 판정한다.
--   던전 -> 몬스터 / 필드 -> 필드 몬스터 / 로비 -> 허수아비 (골드)
------------------------------------------------------------
Remotes.Attack.OnServerEvent:Connect(function(player, aimPoint)
	if typeof(aimPoint) ~= "Vector3" or aimPoint ~= aimPoint then return end -- NaN 방어

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then return end

	local now = os.clock()
	local speedPoints = player:GetAttribute("SpeedPoints") or 0
	local cooldown = Config.Player.BaseCooldown / (1 + speedPoints * Config.Player.SpeedPerPoint)
	if now - (lastAttack[player] or 0) < cooldown * 0.9 then return end -- 연타 제한 (네트워크 오차 10% 허용)
	lastAttack[player] = now

	local origin = root.Position + Vector3.new(0, 1.5, 0)
	local offset = aimPoint - origin
	if offset.Magnitude < 0.5 then return end
	local direction = offset.Unit

	local endPosition = Dungeon.Shoot(player, origin, direction)
		or Field.Shoot(player, origin, direction)
		or Dummy.Shoot(player, origin, direction)
	endPosition = endPosition or (origin + direction * Config.Player.AttackRange)

	-- 무기 등급마다 모양이 다른 발사체가 날아감
	local level = player:GetAttribute("WeaponLevel") or 0
	local tier = Config.GetWeaponTier(level)
	local color = tier.Rainbow and Color3.fromHSV((now * 0.5) % 1, 0.8, 1) or tier.Color
	Effects.Shot(Weapon.GetTipPosition(player) or origin, endPosition, tier.Shot, color, tier.Rainbow)
	Weapon.PlayShot(player)
end)

------------------------------------------------------------
-- 무기 강화 / 장비 강화 / 장비 뽑기
------------------------------------------------------------
Remotes.Enhance.OnServerEvent:Connect(function(player)
	local now = os.clock()
	if now - (lastEnhance[player] or 0) < 0.25 then return end
	lastEnhance[player] = now

	local ok, message = Weapon.Enhance(player)
	Remotes.Enhance:FireClient(player, ok, message)
end)

Remotes.Gear.OnServerEvent:Connect(function(player, action, arg)
	local now = os.clock()
	if now - (lastGear[player] or 0) < 0.25 then return end
	lastGear[player] = now

	if action == "Enhance" and typeof(arg) == "string" then
		local ok, message = Gear.Enhance(player, arg)
		Remotes.Gear:FireClient(player, "Result", { Ok = ok, Message = message })
	elseif action == "Roll" then
		local ok, message, roll = Gear.Roll(player)
		Remotes.Gear:FireClient(player, "Result", { Ok = ok, Message = message, Roll = roll })
	end
end)
