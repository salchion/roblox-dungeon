-- GameServer (ServerScriptService 안의 Script)
-- 게임 전체의 진입점. 로비 / 필드 / 던전, 플레이어 세팅, 공격 처리, 무기·장비 요청을 서로 연결한다.
--
-- 구조 (자세한 배치는 README.md / manifest.json 참고)
--   ReplicatedStorage:      Config, Remotes, AudioIds (ModuleScript)
--   ServerScriptService:    GameServer (이 Script) + Modules 폴더(Effects, WeaponService, GearService, PartyService,
--                           LobbyService, DummyService, FieldService, DungeonService, QuestService, RankService, DataService)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes")) -- RemoteEvent 들이 여기서 만들어짐

local Modules = ServerScriptService:WaitForChild("Modules")
local Effects = require(Modules:WaitForChild("Effects"))
local Weapon = require(Modules:WaitForChild("WeaponService"))
Weapon.BuildPreviews() -- 강화창 3D 미리보기용 총 모델 (ReplicatedStorage.WeaponPreviews)
local Gear = require(Modules:WaitForChild("GearService"))
local Party = require(Modules:WaitForChild("PartyService"))
local Lobby = require(Modules:WaitForChild("LobbyService"))
local Dummy = require(Modules:WaitForChild("DummyService"))
local Dungeon = require(Modules:WaitForChild("DungeonService"))
local Field = require(Modules:WaitForChild("FieldService"))
local Skill = require(Modules:WaitForChild("SkillService"))
local Daily = require(Modules:WaitForChild("DailyService"))
local Meta = require(Modules:WaitForChild("MetaService"))
local Tutorial = require(Modules:WaitForChild("TutorialService"))
local EventService = require(Modules:WaitForChild("EventService"))
local Showcase = require(Modules:WaitForChild("ShowcaseService"))
local Quest = require(Modules:WaitForChild("QuestService"))
local Level = require(Modules:WaitForChild("LevelService"))
local Rank = require(Modules:WaitForChild("RankService"))
local Inventory = require(Modules:WaitForChild("InventoryService"))
local Keys = require(Modules:WaitForChild("KeyService"))
local Growth = require(Modules:WaitForChild("GrowthService"))
local Monetization = require(Modules:WaitForChild("MonetizationService"))
local Data = require(Modules:WaitForChild("DataService"))

Monetization.SaveHook = Data.Save -- 결제 영수증 처리 때 "저장 성공"을 확인하는 데 사용

------------------------------------------------------------
-- 로비 / 게이트 / 강화대 / 뽑기 머신 / 허수아비 / 랭킹판 / 필드
------------------------------------------------------------
local lobby = Lobby.Build()

local function promptPosition(prompt)
	local parent = prompt.Parent
	if parent:IsA("Attachment") then
		return parent.WorldPosition
	elseif parent:IsA("BasePart") then
		return parent.Position
	end
	return parent:GetPivot().Position
end
Tutorial.SetTargets({ -- 튜토리얼 미션 표지 위치
	Dummy = lobby.DummyStart + Vector3.new(0, 4, 0),
	Anvil = promptPosition(lobby.AnvilPrompt),
	Gacha = promptPosition(lobby.GachaPrompt),
	Field = promptPosition(lobby.WarpPrompt),
	Gate = promptPosition(lobby.GatePrompt),
})
Dungeon.Init(lobby.SpawnCFrame)
Dummy.Build(lobby.DummyStart)
Rank.Init(lobby.RankBoardCFrame)
Showcase.Init(lobby.RankBoardCFrame) -- 랭킹판 앞 명예의 전당 (최강 3명)
Field.Init(lobby.SpawnCFrame)
EventService.Start() -- 주기적 골든 타임

-- 던전 게이트: 파티장(또는 솔로)에게 던전 종류 / 난이도 선택창을 띄운다
for _, gate in ipairs(lobby.Gates) do -- 던전마다 게이트가 따로 있다
	gate.Prompt.Triggered:Connect(function(player)
		Dungeon.StartGate(player, gate.Index)
	end)
end

lobby.AnvilPrompt.Triggered:Connect(function(player)
	if player:GetAttribute("Zone") == "Lobby" then
		Remotes.OpenEnhance:FireClient(player)
	end
end)

-- 필드 입구: 도달한 구역의 캠프로 바로 워프하는 메뉴
lobby.WarpPrompt.Triggered:Connect(function(player)
	if player:GetAttribute("Zone") ~= "Dungeon" then
		Remotes.Warp:FireClient(player, "Open")
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

	-- 로블록스 기본 체력 자동 회복(초당 1%)을 끈다: 필드에서는 힐 스킬로만 회복. 마을(로비)에서는 천천히 가득 찬다
	task.spawn(function()
		local regen = character:WaitForChild("Health", 3)
		if regen then regen:Destroy() end
		while character.Parent and humanoid.Health > 0 do
			if player:GetAttribute("Zone") == "Lobby" and humanoid.Health < humanoid.MaxHealth then
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * 0.1)
			end
			task.wait(1)
		end
	end)

	Dungeon.OnCharacterAdded(player, character)

	-- 필드에서 죽으면 로비(마을)로 귀환한다: 기본 스폰 위치에서 다시 시작 (진행한 구역 / 관문 / 아이템은 그대로)
	if player:GetAttribute("DiedInField") then
		player:SetAttribute("DiedInField", nil)
		player:SetAttribute("Zone", "Lobby")
		Remotes.Notify:FireClient(player, "💀 쓰러져서 마을로 돌아왔어요. 장비를 정비하고 다시 도전하세요!")
	end
	humanoid.Died:Connect(function()
		if player:GetAttribute("Zone") == "Field" then
			player:SetAttribute("DiedInField", true)
		end
	end)

	character:WaitForChild("Head")
	Weapon.Refresh(player)
	Meta.RefreshPetModel(player)
	task.wait(0.2) -- 몸 부위가 다 붙은 뒤 장비 외형을 씌운다
	Gear.ApplyVisuals(player)
	Monetization.ApplyAura(player) -- 꾸미기 오라
end

-- 전투력 = 무기(종류+강화) + 스탯 + 장비 (이름표 / 리더보드 / 랭킹에 표시)
local function updatePower(player)
	player:SetAttribute("Power", Config.GetPower(
		player:GetAttribute("WeaponLevel") or 0,
		player:GetAttribute("CritPoints") or 0,
		player:GetAttribute("SpeedPoints") or 0,
		(player:GetAttribute("GearHealth") or 0) + (player:GetAttribute("TrainHealth") or 0),
		(player:GetAttribute("GearCrit") or 0) + (player:GetAttribute("TrainCrit") or 0),
		player:GetAttribute("WeaponType") or "Pistol",
		player:GetAttribute("Level") or 1,
		(player:GetAttribute("GearDamage") or 0) + (player:GetAttribute("TrainDamage") or 0)
	))
end

-- 무기는 강화 단계(WeaponLevel) 하나로 정해진다. 그 단계의 무기 종류(권총 / 리볼버 / ...)를 WeaponType 으로 맞춘다.
local function syncWeaponLevel(player)
	local level = player:GetAttribute("WeaponLevel") or 0
	player:SetAttribute("WeaponType", Config.GetWeaponTier(level).Class)
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
	player:SetAttribute("WeaponType", "Pistol")
	player:SetAttribute("MaxZone", 0)
	player:SetAttribute("ClearedZone", 0)
	player:SetAttribute("GateKills", 0)
	player:SetAttribute("Power", 0)
	player:SetAttribute("Title", "")
	Level.Load(player, 1, 0)
	for _, attribute in pairs(Config.StatAttributes) do
		player:SetAttribute(attribute, 0)
	end
	player:SetAttribute("StatPoints", 0)
	Skill.Reset(player)
	Meta.Init(player) -- 저장 데이터를 읽기 전에도 스킬 레벨 등 기본값 보장

	player:SetAttribute("RespawnZone", 0)
	player:SetAttribute("Keys", 0)
	player:SetAttribute("GatePassed", 0)
	player:SetAttribute("TimeSkip", 0)
	player:SetAttribute("KeyNext", 0)
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
	addStat("전투력", "Power", function()
		Weapon.UpdateNameplate(player)
		Quest.Refresh(player)
	end)
	addStat("Lv", "Level")
	addStat("Gold", "Gold")
	addStat("Weapon", "WeaponLevel")
	addStat("Tickets", "Tickets")

	-- 강화 단계 / 무기 종류 / 모델 / 전투력 동기화
	player:GetAttributeChangedSignal("WeaponLevel"):Connect(function()
		syncWeaponLevel(player) -- 단계가 오르면 무기(종류)가 바뀔 수 있다
		Quest.Refresh(player)
		Weapon.Refresh(player) -- 강화 즉시 무기 외형 변경 (모든 플레이어에게 보임)
		updatePower(player)
	end)
	for _, attribute in ipairs({ "CritPoints", "SpeedPoints", "GearHealth", "GearCrit", "GearDamage", "TrainHealth", "TrainCrit", "TrainDamage" }) do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			updatePower(player)
		end)
	end
	-- 장비로 최대 체력이 바뀌면 바로 반영
	player:GetAttributeChangedSignal("GearHealth"):Connect(function()
		Dungeon.RefreshMaxHealth(player)
	end)
	player:GetAttributeChangedSignal("TrainHealth"):Connect(function()
		Dungeon.RefreshMaxHealth(player) -- 훈련소 체력 단련
	end)
	player:GetAttributeChangedSignal("PartyId"):Connect(function()
		Weapon.UpdateNameplate(player)
	end)
	player:GetAttributeChangedSignal("MaxZone"):Connect(function()
		Weapon.UpdateNameplate(player)
		Quest.Refresh(player)
	end)
	player:GetAttributeChangedSignal("Title"):Connect(function()
		Weapon.UpdateNameplate(player)
	end)
	for _, cosmeticKind in ipairs({ "Aura", "Banner", "Mount" }) do
		player:GetAttributeChangedSignal(cosmeticKind):Connect(function()
			Monetization.ApplyAura(player)
		end)
	end
	-- 레벨이 오르면 최대 체력(완전 회복) / 전투력 / 이름표 / 업적 갱신
	player:GetAttributeChangedSignal("Level"):Connect(function()
		Dungeon.RefreshMaxHealth(player)
		updatePower(player)
		Quest.Refresh(player)
	end)
	for _, slot in ipairs(Config.Gear.Slots) do
		player:GetAttributeChangedSignal("Gear_" .. slot.Key .. "_R"):Connect(function()
			Quest.Refresh(player)
		end)
	end

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
		player:SetAttribute("ClearedZone", saved.ClearedZone or 0)
		player:SetAttribute("WeaponLevel", saved.WeaponLevel)
		syncWeaponLevel(player)
		Level.Load(player, saved.Level, saved.XP)
		Monetization.Load(player, saved.Monetization)  -- 가방 칸 / 열쇠 보관량 등 BM 효과가 먼저 반영돼야 함
		Inventory.Load(player, saved.Inventory, saved.Gear) -- 예전 저장 형식의 장비는 아이템으로 이어받음
		Keys.Load(player, saved.KeysData and saved.KeysData.Keys, saved.KeysData and saved.KeysData.Base)
		Growth.Load(player, saved.Growth) -- 훈련소 / 돌파 (오프라인 중 끝난 것도 완료 처리)
		Quest.Load(player, saved.Quest)
		Daily.Load(player, saved.Daily) -- 출석 보상 (하루 한 번 자동 지급)
		Meta.Load(player, saved.Meta)   -- 스킬 레벨 / 펫 / 무한의 탑 기록
		Tutorial.Load(player, saved.Tutorial) -- 처음 1~5분 가이드 미션
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
local lastWeapon = {}

Players.PlayerRemoving:Connect(function(player)
	lastAttack[player] = nil
	lastEnhance[player] = nil
	lastGear[player] = nil
	lastWeapon[player] = nil
	Party.OnPlayerRemoving(player)
	Dungeon.OnPlayerRemoving(player)
	Data.Save(player)
	Data.Forget(player)
	Quest.Forget(player)
	Inventory.Forget(player)
	Keys.Forget(player)
	Monetization.Forget(player)
	Growth.Forget(player)
	Daily.Forget(player)
	Meta.Forget(player)
	Tutorial.Forget(player)
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
-- 공격: 클라이언트는 조준 지점만 보내고, 맞았는지는 서버가 판정한다.
--   던전 -> 몬스터 / 필드 -> 필드 몬스터 / 로비 -> 허수아비 (골드)
-- 무기 종류에 따라 공격 속도 / 탄 수 / 퍼짐 / 사거리가 다르다 (Config.WeaponTypes)
------------------------------------------------------------
local function spreadDirection(direction, degrees)
	if degrees <= 0 then
		return direction
	end
	local yaw = math.rad((math.random() - 0.5) * degrees)
	local pitch = math.rad((math.random() - 0.5) * degrees * 0.6)
	return (CFrame.lookAt(Vector3.zero, direction) * CFrame.Angles(pitch, yaw, 0)).LookVector
end

Remotes.Attack.OnServerEvent:Connect(function(player, aimPoint)
	if typeof(aimPoint) ~= "Vector3" or aimPoint ~= aimPoint then return end -- NaN 방어

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then return end

	local weaponType = Config.GetPlayerWeapon(player)
	local now = os.clock()
	local speedPoints = player:GetAttribute("SpeedPoints") or 0
	local cooldown = Config.Player.BaseCooldown * weaponType.Cooldown / (1 + speedPoints * Config.Player.SpeedPerPoint)
	if now - (lastAttack[player] or 0) < cooldown * 0.9 then return end -- 연타 제한 (네트워크 오차 10% 허용)
	lastAttack[player] = now

	local origin = root.Position + Vector3.new(0, 1.5, 0)
	local offset = aimPoint - origin
	if offset.Magnitude < 0.5 then return end
	local baseDirection = offset.Unit

	-- 무기 등급마다 모양이 다른 발사체 (무기 종류별로 크기 / 속도 보정)
	local level = player:GetAttribute("WeaponLevel") or 0
	local tier = Config.GetWeaponTier(level)
	local color = tier.Rainbow and Color3.fromHSV((now * 0.5) % 1, 0.8, 1) or tier.Color
	local extra = (player:GetAttribute("Zone") == "Dungeon" and (player:GetAttribute("PerkMulti") or 0) or 0) + (player:GetAttribute("GearShot") or 0)
	local shot = table.clone(tier.Shot)
	shot.Size *= weaponType.ShotScale * (1 + 0.04 * Config.GetWeaponStage(level)) -- 강화 단계마다 발사체가 조금씩 커진다
	shot.Speed *= weaponType.SpeedScale
	if weaponType.Pellets + extra > 1 then
		shot.Impact = math.floor(shot.Impact / 3)
	end
	local tipPosition = Weapon.GetTipPosition(player) or origin

	-- 던전 특성 "분산탄": 탄이 +N발, 부채꼴로 흩어져 나간다 (권총류는 대칭 부채꼴, 샷건은 산탄이 더 늘어남)
	local pellets = weaponType.Pellets + extra
	local hitsBefore = player:GetAttribute("HitTick") or 0
	local fanAngle = math.rad(Config.Perks.FanAngle)
	for pellet = 1, pellets do
		local direction
		if weaponType.Pellets == 1 then
			if pellets == 1 then
				direction = baseDirection
			else
				direction = (CFrame.fromAxisAngle(Vector3.yAxis, (pellet - (pellets + 1) / 2) * fanAngle) * CFrame.new(baseDirection)).Position
			end
		else
			direction = spreadDirection(baseDirection, weaponType.Spread)
		end
		local endPosition = Dungeon.Shoot(player, origin, direction)
			or Field.Shoot(player, origin, direction)
			or Dummy.Shoot(player, origin, direction)
		endPosition = endPosition or (origin + direction * weaponType.Range)
		Effects.Shot(tipPosition, endPosition, shot, color, tier.Rainbow, tier.Class, tier.Era)
	end
	Weapon.PlayShot(player)
	-- 궁극기 게이지: 몬스터를 실제로 맞혔을 때만 찬다 (허공에 쏴서는 안 참)
	if (player:GetAttribute("HitTick") or 0) > hitsBefore then
		Skill.AddCharge(player, Config.Skills.ChargePerShot)
	end
end)

------------------------------------------------------------
-- 무기 강화 / 무기 종류 구매·장착 / 장비 강화·뽑기
------------------------------------------------------------
Remotes.Enhance.OnServerEvent:Connect(function(player, count)
	local now = os.clock()
	if now - (lastEnhance[player] or 0) < 0.25 then return end
	lastEnhance[player] = now

	count = typeof(count) == "number" and math.clamp(math.floor(count), 1, 50) or 1
	if player:GetAttribute("TutorialActive") then
		count = 1 -- 튜토리얼 중에는 한 번씩만 (x10 / 최대 강화는 튜토리얼이 끝난 뒤)
	end
	if count == 1 then
		local ok, message = Weapon.Enhance(player)
		Remotes.Enhance:FireClient(player, ok, message)
		return
	end

	-- 여러 번 연속 강화 (골드가 모일 때 한 번에): 골드가 떨어지거나 무기가 진화하면 거기서 멈춘다 (진화한 새 무기를 보게)
	local attempts, successes, spent, evolvedMessage, lastMessage = 0, 0, 0, nil, ""
	for _ = 1, count do
		local ok, message, stop, evolved, cost = Weapon.Enhance(player)
		if stop then
			lastMessage = message
			break
		end
		attempts += 1
		spent += cost or 0
		lastMessage = message
		if ok then successes += 1 end
		if evolved then
			evolvedMessage = message
			break
		end
	end
	if attempts == 0 then
		Remotes.Enhance:FireClient(player, false, lastMessage)
		return
	end
	local summary = string.format("%d회 강화: 성공 %d / 실패 %d  (골드 -%d)", attempts, successes, attempts - successes, spent)
	Remotes.Enhance:FireClient(player, successes > 0, evolvedMessage or summary, { Attempts = attempts, Successes = successes, Spent = spent, Evolved = evolvedMessage ~= nil, Summary = summary })
end)

Remotes.Weapon.OnServerEvent:Connect(function(player, action, typeKey)
	local now = os.clock()
	if now - (lastWeapon[player] or 0) < 0.25 then return end
	lastWeapon[player] = now
	if typeof(typeKey) ~= "string" then return end

	local ok, message
	if action == "Equip" then
		ok, message = Weapon.Equip(player, typeKey)
	elseif action == "Buy" then
		if player:GetAttribute("Zone") ~= "Lobby" then
			ok, message = false, "무기 구매는 로비에서만 할 수 있어요."
		else
			ok, message = Weapon.Buy(player, typeKey)
		end
	else
		return
	end
	Remotes.Notify:FireClient(player, (ok and "✅ " or "⚠ ") .. message)
end)

Remotes.Gear.OnServerEvent:Connect(function(player, action, arg)
	local now = os.clock()
	if now - (lastGear[player] or 0) < 0.25 then return end
	lastGear[player] = now

	if action == "Enhance" and typeof(arg) == "string" then
		local ok, message = Gear.Enhance(player, arg)
		Remotes.Gear:FireClient(player, "Result", { Ok = ok, Message = message })
	elseif action == "Roll" then
		local count = typeof(arg) == "number" and math.clamp(math.floor(arg), 1, 10) or 1
		if count == 1 then
			local ok, message, roll = Gear.Roll(player)
			Remotes.Gear:FireClient(player, "Result", { Ok = ok, Message = message, Roll = roll })
		else
			-- 여러 개 동시에 뽑기 (최대 10연): 티켓이 모자라면 있는 만큼만 뽑는다
			local rolls, failMessage = {}, nil
			for _ = 1, count do
				local ok, message, roll = Gear.Roll(player)
				if not ok then
					failMessage = message
					break
				end
				table.insert(rolls, roll)
			end
			if #rolls == 0 then
				Remotes.Gear:FireClient(player, "Result", { Ok = false, Message = failMessage or "뽑을 수 없어요." })
			else
				local best = rolls[1]
				for _, roll in ipairs(rolls) do
					if roll.Rarity > best.Rarity then best = roll end
				end
				Remotes.Gear:FireClient(player, "Result", {
					Ok = true, Roll = best, Rolls = rolls,
					Message = string.format("%d회 뽑기 완료! 최고 등급: %s", #rolls, Config.Gear.RarityNames[best.Rarity]),
				})
			end
		end
	end
end)
