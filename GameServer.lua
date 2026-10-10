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
local LevelStat = require(Modules:WaitForChild("LevelStatService"))
local Monetization = require(Modules:WaitForChild("MonetizationService"))
local Data = require(Modules:WaitForChild("DataService"))
local Rift = require(Modules:WaitForChild("RiftService"))
local Advice = require(Modules:WaitForChild("AdviceService"))
local Idle = require(Modules:WaitForChild("IdleService"))
local Journey = require(Modules:WaitForChild("JourneyService"))
local Npc = require(Modules:WaitForChild("NpcService"))

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
	Dummy = lobby.DummyStart + Vector3.new(0, 1, 0), -- 대장간 옆 훈련장의 큰 허수아비
	Anvil = promptPosition(lobby.AnvilPrompt),
	Gacha = promptPosition(lobby.GachaPrompt),
	Field = promptPosition(lobby.WarpPrompt),
	Gate = promptPosition(lobby.GatePrompt),
})
Dungeon.Init(lobby.SpawnCFrame)
Dummy.Build(lobby.DummyStart)
Dummy.BuildRest(lobby.RestStart) -- 휴식 구역 (방치 수입)
Npc.Init(lobby.DummyStart.Y, { -- 시설마다 NPC 가 서서 말을 건다 (허공에 대고 말하는 느낌을 없애려고)
	{ Name = "톰", Title = "🔨 대장장이", Position = promptPosition(lobby.AnvilPrompt), Shirt = Color3.fromRGB(150, 98, 60), Pants = Color3.fromRGB(70, 56, 48), Hat = "cap", Accent = Color3.fromRGB(110, 70, 44), Prop = "hammer",
		Lines = { "쾅쾅! 무기를 두드려 볼까?", "강화하다 보면 더 강한 무기로 진화해!", "실패해도 단계는 안 내려가니까 걱정 마!" } },
	{ Name = "루나", Title = "🎰 뽑기 상인", Position = promptPosition(lobby.GachaPrompt), Shirt = Color3.fromRGB(120, 80, 170), Pants = Color3.fromRGB(60, 44, 90), Hat = "wizard", Accent = Color3.fromRGB(150, 100, 210), Prop = "staff",
		Lines = { "티켓 있어? 행운을 시험해 봐!", "여러 장 뽑기엔 가끔 좋은 게 숨어 있대.", "세트 장비는 필드에서 모아야 맞출 수 있어!" } },
	{ Name = "카이", Title = "🛡 필드 문지기", Position = promptPosition(lobby.WarpPrompt), Shirt = Color3.fromRGB(110, 120, 140), Pants = Color3.fromRGB(70, 74, 90), Hat = "helmet", Accent = Color3.fromRGB(190, 60, 60), Prop = "spear",
		Lines = { "필드는 위험해. 군주를 쓰러뜨리면 다음 구역이 열려.", "Q 대시로 탄을 아슬아슬하게 피해 봐!", "준비됐으면 문으로 가!" } },
	{ Name = "벨", Title = "🗝 던전 안내원", Position = promptPosition(lobby.GatePrompt), Shirt = Color3.fromRGB(70, 110, 100), Pants = Color3.fromRGB(46, 62, 60), Hat = "hood", Accent = Color3.fromRGB(60, 96, 90), Prop = "lantern",
		Lines = { "던전은 하루 무료 입장이 있어.", "던전마다 몬스터도 보스도 달라!", "열쇠는 필드 군주가 줘." } },
	{ Name = "미라", Title = "🌀 심연 관리인", Position = promptPosition(lobby.RiftPrompt), Shirt = Color3.fromRGB(150, 60, 120), Pants = Color3.fromRGB(70, 36, 66), Hat = "hood", Accent = Color3.fromRGB(190, 70, 150), Prop = "staff",
		Lines = { "필드를 정복한 자만 심연에 들어갈 수 있어.", "깊이 들어갈수록 보상이 커져.", "기록이 곧 소탕 보상이야." } },
})
Rank.Init(lobby.RankBoardCFrame)
Showcase.Init(lobby.RankBoardCFrame) -- 랭킹판 앞 명예의 전당 (최강 3명)
Field.Init(lobby.SpawnCFrame)
Rift.Init(lobby.RiftPrompt) -- 심연 도전 포탈
do -- 튜토리얼 이후 안내 (구역 2 / 심연 / 새 던전 게이트 표지, 전투 중 첫 위기 한 줄)
	local gatePositions = {}
	for _, gate in ipairs(lobby.Gates) do
		gatePositions[gate.Index] = promptPosition(gate.Prompt)
	end
	Journey.Init({ Field = promptPosition(lobby.WarpPrompt), Rift = promptPosition(lobby.RiftPrompt), Gates = gatePositions })
	Journey.Start()
end
Idle.Init(lobby.RestStart) -- 방치 수입 (휴식 구역 원 안에 서 있기 + 오프라인 적립)
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
	Tutorial.EarlyFreeze(player, character) -- 튜토리얼 상태가 로드되기 전까지 움직이지 못하게 (처음 접속 시)
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
		local doomed = player:GetAttribute("TutorialDoomed")
		if doomed then
			player:SetAttribute("TutorialDoomed", nil)
			if doomed == "Retry" then
				Remotes.Notify:FireClient(player, "💀 쓰러졌어요! 이번엔 일회성 힘이 깃들었어요 (군주에게 주는 피해 크게 증가 + 궁극기 가득) — 다시 군주에게 도전해요!")
			else
				Remotes.Notify:FireClient(player, "💀 최후의 군주에게 쓰러졌어요… 하지만 전리품은 남았어요!")
			end
		else
			Remotes.Notify:FireClient(player, "💀 쓰러져서 마을로 돌아왔어요. 장비를 정비하고 다시 도전하세요!")
		end
		task.delay(1.5, function() Advice.AfterDefeat(player) end) -- 쓰러진 직후: 지금 남은 골드 / 티켓 / 빈 장비 / 빈 훈련 슬롯을 알려준다
	end
	humanoid.Died:Connect(function()
		if player:GetAttribute("Zone") == "Field" then
			player:SetAttribute("DiedInField", true)
			if player:GetAttribute("TutorialDoom") and not player:GetAttribute("InDoomArena") then
				-- 지역 군주에게 쓰러짐: 미션은 끝나지 않는다. 일회성 힘을 받아 다시 군주에게 도전 (군주를 잡아야 최후의 군주에게 끌려간다)
				player:SetAttribute("TutorialDoomed", "Retry")
				player:SetAttribute("TutorialRetryBuff", true)
			else
				if player:GetAttribute("TutorialDoom") then
					player:SetAttribute("TutorialDoomed", "Final") -- 최후의 군주에게 쓰러짐 (미션 완료)
				end
				Quest.Add(player, "FieldDeaths", 1)
			end
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
		Keys.Load(player, saved.KeysData and saved.KeysData.Keys, saved.KeysData and saved.KeysData.Base, saved.KeysData)
		Growth.Load(player, saved.Growth) -- 훈련소 / 돌파 (오프라인 중 끝난 것도 완료 처리)
		Quest.Load(player, saved.Quest)
		Daily.Load(player, saved.Daily) -- 출석 보상 (하루 한 번 자동 지급)
		Meta.Load(player, saved.Meta)   -- 스킬 레벨 / 펫 / 무한의 탑 기록
		LevelStat.Refresh(player)       -- 레벨 스탯 (이동 속도 / 사정거리 / 투사체 ...) 효과 반영
		Tutorial.Load(player, saved.Tutorial) -- 처음 1~5분 가이드 미션
		Idle.OnJoin(player) -- 자리를 비운 동안 쌓인 방치 골드
		Journey.OnJoin(player) -- 이미 본 안내 기록
		updatePower(player)
		player:SetAttribute("DataReady", true) -- 저장된 정보를 다 불러왔다 (화면의 "불러오는 중" 표시를 끈다)
		-- 진행 기록(Studio 출력창): 접속 후 몇 분 몇 초에 어디까지 왔는지 찍는다. 신규 플레이어가 5분 / 30분에 어디까지 오는지 재는 용도.
		task.spawn(function()
			local startedAt = os.clock()
			local function stamp() local t = math.floor(os.clock() - startedAt) return string.format("%d:%02d", t // 60, t % 60) end
			local function log(text) print(string.format("[진행 기록] %s · %s · %s", player.Name, stamp(), text)) end
			local lastWeaponTier = Config.GetWeaponTier(player:GetAttribute("WeaponLevel") or 0).Index
			local seen = {}
			local function once(key, text) if not seen[key] then seen[key] = true log(text) end end
			log(string.format("시작 (레벨 %d, 골드 %d)", player:GetAttribute("Level") or 1, player:GetAttribute("Gold") or 0))
			player:GetAttributeChangedSignal("Level"):Connect(function() log(string.format("레벨 %d 달성 (전투력 %d)", player:GetAttribute("Level") or 1, player:GetAttribute("Power") or 0)) end)
			player:GetAttributeChangedSignal("ClearedZone"):Connect(function() log(string.format("%d구역 관문 열림 (군주 격파)", player:GetAttribute("ClearedZone") or 0)) end)
			player:GetAttributeChangedSignal("MaxZone"):Connect(function() log(string.format("%d구역에 처음 도착", player:GetAttribute("MaxZone") or 0)) end)
			player:GetAttributeChangedSignal("Zone"):Connect(function() once("zone_" .. tostring(player:GetAttribute("Zone")), "처음 입장: " .. tostring(player:GetAttribute("Zone"))) end)
			player:GetAttributeChangedSignal("TutorialActive"):Connect(function() if player:GetAttribute("TutorialActive") ~= true then once("tut_end", "튜토리얼 종료") end end)
			player:GetAttributeChangedSignal("InDoomArena"):Connect(function() if player:GetAttribute("InDoomArena") then once("doom", "최후의 군주 결투장 입장") end end)
			player:GetAttributeChangedSignal("GrowthUnlocked"):Connect(function() if player:GetAttribute("GrowthUnlocked") then once("growth", "성장 훈련 해금") end end)
			player:GetAttributeChangedSignal("WeaponLevel"):Connect(function()
				once("weapon1", string.format("첫 무기 강화 (%d단계)", player:GetAttribute("WeaponLevel") or 0))
				local tier = Config.GetWeaponTier(player:GetAttribute("WeaponLevel") or 0).Index
				if tier ~= lastWeaponTier then lastWeaponTier = tier log(string.format("무기 진화 → %d번째 무기", tier)) end
			end)
			for _, minutes in ipairs({ 5, 10, 20, 30 }) do
				task.delay(minutes * 60 - (os.clock() - startedAt), function()
					if player.Parent then
						log(string.format("== %d분 요약 == 레벨 %d · 전투력 %d · 무기 %d단계(%d번째) · 도달 %d구역 / 격파 %d구역 · 골드 %d · 티켓 %d", minutes,
							player:GetAttribute("Level") or 1, player:GetAttribute("Power") or 0, player:GetAttribute("WeaponLevel") or 0,
							Config.GetWeaponTier(player:GetAttribute("WeaponLevel") or 0).Index, player:GetAttribute("MaxZone") or 0, player:GetAttribute("ClearedZone") or 0,
							player:GetAttribute("Gold") or 0, player:GetAttribute("Tickets") or 0))
					end
				end)
			end
		end)
	end
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(setupPlayer, player)
end

local lastAttack = setmetatable({}, { __mode = "k" })
local lastEnhance = setmetatable({}, { __mode = "k" })
local lastGear = setmetatable({}, { __mode = "k" })
local lastWeapon = setmetatable({}, { __mode = "k" })

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
	LevelStat.Forget(player)
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
--   던전 -> 몬스터 / 필드 -> 필드 몬스터 / 로비 -> 허수아비 (대미지 / DPS 연습)
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

Remotes.Attack.OnServerEvent:Connect(function(player, aimPoint, manual)
	if typeof(aimPoint) ~= "Vector3" or aimPoint ~= aimPoint then return end -- NaN 방어

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then return end

	local weaponType = Config.GetPlayerWeapon(player)
	local now = os.clock()
	local speedPoints = player:GetAttribute("SpeedPoints") or 0
	local cooldown = Config.Player.BaseCooldown * weaponType.Cooldown / ((1 + speedPoints * Config.Player.SpeedPerPoint) * (1 + (player:GetAttribute("PetAtkSpeed") or 0))) -- 펫 가속 포함
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
	local isManual = manual == true
	local fanAngle = math.rad(Config.Perks.FanAngle)
	-- 한 번의 사격(탄 여러 발). 더블샷이 터지면 이어서 한 번 더 부른다.
	local function fireVolley(volleyOrigin, volleyTip)
		player:SetAttribute("ShotManual", isManual) -- Dungeon / Field.Shoot 이 읽는다: 약점 보너스는 직접 조준한 탄에만
		player:SetAttribute("ShotDmgScale", extra > 0 and (pellets - extra + extra * Config.LevelStats.OtherExtraShotValue) / pellets or 1) -- 추가 탄은 위력이 낮다 (합계 피해가 배수로 뛰지 않게)
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
			local endPosition = Dungeon.Shoot(player, volleyOrigin, direction)
				or Field.Shoot(player, volleyOrigin, direction)
				or Dummy.Shoot(player, volleyOrigin, direction)
			endPosition = endPosition or (volleyOrigin + direction * Config.GetRange(player, weaponType))
			Effects.Shot(volleyTip, endPosition, shot, color, tier.Rainbow, tier.Class, tier.Era)
		end
		player:SetAttribute("ShotDmgScale", 1)
		Weapon.PlayShot(player)
	end
	fireVolley(origin, tipPosition)
	-- 더블샷: 레벨 스탯 확률로 한 번 더 "따-땅" 이어서 나간다 (같은 방향, 위력도 같다)
	if math.random() < (player:GetAttribute("LvDouble") or 0) then
		task.delay(0.09, function()
			local liveRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local liveHumanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if not liveRoot or not liveHumanoid or liveHumanoid.Health <= 0 then return end
			local liveOrigin = liveRoot.Position + Vector3.new(0, 1.5, 0)
			fireVolley(liveOrigin, Weapon.GetTipPosition(player) or liveOrigin)
		end)
	end
	if isManual and (player:GetAttribute("HitTick") or 0) > hitsBefore then
		player:SetAttribute("ManualHitTick", (player:GetAttribute("ManualHitTick") or 0) + 1) -- 연습장 "직접 조준" 판정
	end
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
	if player:GetAttribute("TutorialActive") and player:GetAttribute("TutorialEnhanceCost") == nil then
		count = 1 -- 처음 강화 미션에서는 한 번씩만 (무기 진화 미션부터는 x10 / 최대 강화도 쓸 수 있다)
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
			Remotes.Gear:FireClient(player, "Result", { Ok = ok, Message = message, Roll = roll, Upgrades = ok and Inventory.CountUpgrades(player) or 0 })
		elseif (player:GetAttribute("Tickets") or 0) < count then
			Remotes.Gear:FireClient(player, "Result", { Ok = false, Message = string.format("🎫 %d연 뽑기는 티켓 %d장이 필요해요 (지금 %d장)", count, count, player:GetAttribute("Tickets") or 0) })
		else
			-- 여러 개 동시에 뽑기 (10연): 티켓이 10장 있을 때만
			local rolls, failMessage = {}, nil
			local heroAt = (player:GetAttribute("TutorialRoll") == "Hero" and not player:GetAttribute("TutorialHero") and count >= 10) and math.random(count) or nil
			for index = 1, count do
				local ok, message, roll = Gear.Roll(player, index == heroAt and 3 or nil)
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
					Ok = true, Roll = best, Rolls = rolls, Upgrades = Inventory.CountUpgrades(player),
					Message = string.format("%d회 뽑기 완료! 최고 등급: %s", #rolls, Config.Gear.RarityNames[best.Rarity]),
				})
			end
		end
	end
end)
