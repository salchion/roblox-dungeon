-- GameServer (ServerScriptService 안의 Script)
-- 게임 전체의 진입점. 로비 생성, 플레이어 세팅, 공격 처리, 강화 요청, 던전 입장을 서로 연결한다.
--
-- 구조 (자세한 배치는 README.md 참고)
--   ReplicatedStorage:      Config, Remotes (ModuleScript)
--   ServerScriptService:    GameServer (이 Script) + Modules 폴더(Effects, WeaponService, PartyService,
--                           LobbyService, DungeonService, DataService)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes")) -- RemoteEvent 들이 여기서 만들어짐

local Modules = ServerScriptService:WaitForChild("Modules")
local Effects = require(Modules:WaitForChild("Effects"))
local Weapon = require(Modules:WaitForChild("WeaponService"))
local Party = require(Modules:WaitForChild("PartyService"))
local Lobby = require(Modules:WaitForChild("LobbyService"))
local Dungeon = require(Modules:WaitForChild("DungeonService"))
local Data = require(Modules:WaitForChild("DataService"))
local Dummy = require(Modules:WaitForChild("DummyService"))

------------------------------------------------------------
-- 로비 / 게이트 / 강화대
------------------------------------------------------------
local lobby = Lobby.Build()
Dungeon.Init(lobby.SpawnCFrame)
Dummy.Build(Vector3.new(-62, 0, 0)) -- 허수아비 훈련장

-- 던전 게이트: 파티가 있으면 파티장만 입장 가능 (검사는 Dungeon.Start 안에서)
lobby.GatePrompt.Triggered:Connect(function(player)
	Dungeon.Start(player)
end)

lobby.AnvilPrompt.Triggered:Connect(function(player)
	if player:GetAttribute("Zone") == "Lobby" then
		Remotes.OpenEnhance:FireClient(player)
	end
end)

------------------------------------------------------------
-- 플레이어
------------------------------------------------------------
local function onCharacterAdded(player, character)
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None -- 기본 이름표 대신 무기 레벨이 보이는 이름표 사용
	humanoid.MaxHealth = Dungeon.GetMaxHealth(player)
	humanoid.Health = humanoid.MaxHealth

	Dungeon.OnCharacterAdded(player, character)

	character:WaitForChild("Head")
	Weapon.Refresh(player)
end

local function setupPlayer(player)
	-- 3인칭 카메라 (1인칭으로 들어가지 못하게 최소 거리를 둠)
	player.CameraMode = Enum.CameraMode.Classic
	player.CameraMinZoomDistance = 8
	player.CameraMaxZoomDistance = 60

	player:SetAttribute("Zone", "Lobby")
	player:SetAttribute("PartyId", 0)
	player:SetAttribute("Gold", 0)
	player:SetAttribute("WeaponLevel", 0)
	for _, attribute in pairs(Config.StatAttributes) do
		player:SetAttribute(attribute, 0)
	end
	player:SetAttribute("StatPoints", 0)

	-- 리더보드에 골드 / 무기 강화 수치 표시
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local goldValue = Instance.new("IntValue")
	goldValue.Name = "Gold"
	goldValue.Parent = leaderstats

	local weaponValue = Instance.new("IntValue")
	weaponValue.Name = "Weapon"
	weaponValue.Parent = leaderstats

	player:GetAttributeChangedSignal("Gold"):Connect(function()
		goldValue.Value = player:GetAttribute("Gold") or 0
	end)
	player:GetAttributeChangedSignal("WeaponLevel"):Connect(function()
		weaponValue.Value = player:GetAttribute("WeaponLevel") or 0
		Weapon.Refresh(player) -- 강화 즉시 무기 외형 변경 (모든 플레이어에게 보임)
	end)
	player:GetAttributeChangedSignal("PartyId"):Connect(function()
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
		player:SetAttribute("WeaponLevel", saved.WeaponLevel)
	end
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(setupPlayer, player)
end

local lastAttack = {}

Players.PlayerRemoving:Connect(function(player)
	lastAttack[player] = nil
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
-- 로비에서도 쏠 수 있다 (무기 이펙트 자랑용, 데미지 없음).
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

	-- 던전 안이면 몬스터, 로비면 허수아비를 판정 (둘 다 아니면 nil)
	local endPosition = Dungeon.Shoot(player, origin, direction) or Dummy.Shoot(player, origin, direction)
	endPosition = endPosition or (origin + direction * Config.Player.AttackRange)

	-- 무기 등급마다 모양이 다른 발사체가 날아감
	local level = player:GetAttribute("WeaponLevel") or 0
	local tier = Config.GetWeaponTier(level)
	local color = tier.Rainbow and Color3.fromHSV((now * 0.5) % 1, 0.8, 1) or tier.Color
	Effects.Shot(Weapon.GetTipPosition(player) or origin, endPosition, tier.Shot, color, tier.Rainbow)
	Weapon.PlayShot(player)
end)

------------------------------------------------------------
-- 무기 강화
------------------------------------------------------------
local lastEnhance = {}

Remotes.Enhance.OnServerEvent:Connect(function(player)
	local now = os.clock()
	if now - (lastEnhance[player] or 0) < 0.25 then return end
	lastEnhance[player] = now

	local ok, message = Weapon.Enhance(player)
	Remotes.Enhance:FireClient(player, ok, message)
end)

Players.PlayerRemoving:Connect(function(player)
	lastEnhance[player] = nil
end)
