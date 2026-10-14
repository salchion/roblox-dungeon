-- MetaService (ServerScriptService > Modules 안의 ModuleScript, 이름: MetaService)
-- 캐릭터 성장 보조 시스템 세 가지를 한곳에서 관리한다.
--   1) 스킬 강화: 골드로 스킬 레벨업 (SkillLv_<스킬> Attribute)
--   2) 펫: 골드로 펫 기능 열기 / 레벨업(기능이 하나씩 늘어남) / 외형 선택 (Pet* Attribute 로 효과를 알린다)
--   3) 무한의 탑 최고 층 (TowerBest Attribute)
-- 저장: { Skills = {...}, Pet = { Unlocked, Level, Look, Color }, Tower = 최고층, Rift }

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local RunService = game:GetService("RunService")
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Effects = require(script.Parent:WaitForChild("Effects"))
local Level = require(script.Parent:WaitForChild("LevelService"))
local Event = require(script.Parent:WaitForChild("EventService"))
local PetModel = require(script.Parent:WaitForChild("PetModel"))

local Meta = {}

local states = {} -- [player] = { Skills, Owned, Equipped, Tower }

local function notify(player, text)
	Remotes.Notify:FireClient(player, text)
end

------------------------------------------------------------
-- 펫 능력치 / 모델
------------------------------------------------------------
local PET_ATTRS = { "PetSpeed", "PetXp", "PetDamage", "PetCrit", "PetHaste", "PetAtkSpeed", "PetGold", "PetLoot", "PetGuard", "PetShoot" }

local function applyPetStats(player, state)
	for _, attr in ipairs(PET_ATTRS) do
		player:SetAttribute(attr, 0)
	end
	local pet = state.Pet
	if pet.Unlocked then
		for attr, value in pairs(Config.GetPetStats(pet.Level)) do
			player:SetAttribute(attr, value)
		end
	end
	player:SetAttribute("PetLevel", pet.Unlocked and pet.Level or 0)
	player:SetAttribute("PetLook", pet.Look)
end

-- 이 외형을 쓸 수 있는가: 처음부터 / 필드 군주를 쓰러뜨림 / 칭호(업적)를 땀
local function lookUnlocked(player, lookKey)
	local look = Config.Pet.Looks[lookKey]
	if not look then return false end
	local rule = look.Unlock
	if rule == "Free" then return true end
	if rule.Zone then return (player:GetAttribute("ClearedZone") or 0) >= rule.Zone end
	if rule.Ach then
		local ok, Quest = pcall(function() return require(script.Parent:WaitForChild("QuestService")) end)
		return ok and Quest.IsDone(player, rule.Ach) or false
	end
	return false
end

local function removePetModel(player)
	local character = player.Character
	if not character then return end
	-- 펫 모델이 여러 개 남아 있어도(예전 것이 안 지워진 경우) 전부 지운다. 몸에 남은 따라다니기 고정점도 같이 정리한다.
	for _, child in ipairs(character:GetChildren()) do
		if child.Name == "PetModel" then child:Destroy() end
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		for _, child in ipairs(root:GetChildren()) do
			if child.Name == "PetAnchor" then child:Destroy() end
		end
	end
end

-- 캐릭터 옆을 둥둥 떠서 따라다니는 펫 (AlignPosition 으로 부드럽게 따라옴)
function Meta.RefreshPetModel(player)
	local state = states[player]
	removePetModel(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not state or not state.Pet.Unlocked or not root then return end
	local pet = state.Pet
	local color = Config.Pet.Colors[pet.Color] or Config.Pet.Colors[1]
	local okBuild, model = pcall(PetModel.Build, pet.Look, color)
	if not okBuild then
		warn("[Pet] Could not build model:", pet.Look, model)
		return
	end
	local body = model.PrimaryPart
	body.CFrame = root.CFrame * CFrame.new(3, 2.5, 3)

	local petAttachment = Instance.new("Attachment")
	petAttachment.Parent = body
	local anchorAttachment = Instance.new("Attachment")
	anchorAttachment.Name = "PetAnchor"
	anchorAttachment.Position = Vector3.new(3, 2.5, 3)
	anchorAttachment.Parent = root

	local align = Instance.new("AlignPosition")
	align.Attachment0 = petAttachment
	align.Attachment1 = anchorAttachment
	align.MaxForce = 40000
	align.Responsiveness = 12
	align.Parent = body

	local orient = Instance.new("AlignOrientation")
	orient.Attachment0 = petAttachment
	orient.Attachment1 = anchorAttachment
	orient.MaxTorque = 40000
	orient.Responsiveness = 12
	orient.Parent = body

	model.Parent = character
	pcall(function()
		body:SetNetworkOwner(nil)
	end)
	print(string.format("[Pet] Changed %s's follower pet to %s (color %d)", player.Name, tostring(pet.Look), pet.Color or 1))
end

------------------------------------------------------------
-- 클라이언트로 상태 보내기
------------------------------------------------------------
local function buildPayload(state)
	return { Skills = state.Skills, Pet = state.Pet, Tower = state.Tower }
end

function Meta.Push(player)
	local state = states[player]
	if state and player.Parent then
		local payload = buildPayload(state)
		local unlockedLooks = {}
		for _, key in ipairs(Config.Pet.LookOrder) do
			unlockedLooks[key] = lookUnlocked(player, key)
		end
		payload.UnlockedLooks = unlockedLooks
		Remotes.Meta:FireClient(player, "State", payload)
	end
end

------------------------------------------------------------
-- 불러오기 / 저장
------------------------------------------------------------
local function syncSkillAttributes(player, state)
	for _, key in ipairs(Config.Skills.UpgradeOrder) do
		player:SetAttribute("SkillLv_" .. key, state.Skills[key])
	end
end

function Meta.Load(player, saved)
	local state = { Skills = {}, Pet = { Unlocked = false, Level = 1, Look = "Orb", Color = 1 }, Tower = 0, Codex = { Kills = {}, Boss = {}, Sets = {} }, Rift = { BestScore = 0, BestBoss = 0, BestTime = 0, Week = 0, WeekBest = 0, Day = 0, Used = 0, Hints = {}, LvStats = {} } }
	for _, key in ipairs(Config.Skills.UpgradeOrder) do
		local level = typeof(saved) == "table" and typeof(saved.Skills) == "table" and tonumber(saved.Skills[key]) or 1
		state.Skills[key] = math.clamp(math.floor(level), 1, Config.SkillUpgrade.MaxLevel)
	end
	if typeof(saved) == "table" then
		if typeof(saved.Pet) == "table" then
			local p = saved.Pet
			state.Pet.Unlocked = p.Unlocked == true
			state.Pet.Level = math.clamp(math.floor(tonumber(p.Level) or 1), 1, Config.Pet.MaxLevel)
			if typeof(p.Look) == "string" and Config.Pet.Looks[p.Look] then state.Pet.Look = p.Look end
			state.Pet.Color = math.clamp(math.floor(tonumber(p.Color) or 1), 1, #Config.Pet.Colors)
		elseif typeof(saved.Owned) == "table" then -- 예전 저장(알 부화 방식): 펫이 하나라도 있었으면 기능을 열어 주고, 가장 높은 레벨을 이어받는다
			local best = 0
			for _, level in pairs(saved.Owned) do
				best = math.max(best, tonumber(level) or 0)
			end
			if best > 0 then
				state.Pet.Unlocked = true
				state.Pet.Level = math.clamp(math.floor(best), 1, Config.Pet.MaxLevel)
			end
		end
		if typeof(saved.Codex) == "table" then
			for _, group in ipairs({ "Kills", "Boss", "Sets" }) do
				if typeof(saved.Codex[group]) == "table" then
					for key, count in pairs(saved.Codex[group]) do
						if typeof(key) == "string" and #key <= 16 and tonumber(count) then state.Codex[group][key] = math.max(0, math.floor(tonumber(count))) end
					end
				end
			end
		end
		state.Tower = math.max(0, math.floor(tonumber(saved.Tower) or 0))
		if typeof(saved.Rift) == "table" then
			state.Rift = { BestScore = math.max(0, math.floor(tonumber(saved.Rift.BestScore) or 0)), Day = math.floor(tonumber(saved.Rift.Day) or 0), Used = math.max(0, math.floor(tonumber(saved.Rift.Used) or 0)), Tip = saved.Rift.Tip == true, DungeonTip = saved.Rift.DungeonTip == true, DungeonDay = math.floor(tonumber(saved.Rift.DungeonDay) or 0), DungeonUsed = math.max(0, math.floor(tonumber(saved.Rift.DungeonUsed) or 0)), KeyDay = math.floor(tonumber(saved.Rift.KeyDay) or 0), KeyDropsTier = typeof(saved.Rift.KeyDropsTier) == "table" and { tonumber(saved.Rift.KeyDropsTier[1]) or 0, tonumber(saved.Rift.KeyDropsTier[2]) or 0, tonumber(saved.Rift.KeyDropsTier[3]) or 0 } or { 0, 0, 0 }, Hints = (function() local list = {} if typeof(saved.Rift.Hints) == "table" then for key, value in pairs(saved.Rift.Hints) do if typeof(key) == "string" and #key <= 24 and value == true then list[key] = true end end end return list end)(), GrowthTip = saved.Rift.GrowthTip == true, BestBoss = math.max(0, math.floor(tonumber(saved.Rift.BestBoss) or 0)), BestDealt = math.max(0, tonumber(saved.Rift.BestDealt) or 0), BestTime = math.max(0, math.floor(tonumber(saved.Rift.BestTime) or 0)), Week = math.floor(tonumber(saved.Rift.Week) or 0), WeekBest = math.max(0, tonumber(saved.Rift.WeekBest) or 0), IdleSeen = math.max(0, math.floor(tonumber(saved.Rift.IdleSeen) or 0)), LvStats = (function() local list = {} for _, key in ipairs(Config.LevelStats.Order) do list[key] = typeof(saved.Rift.LvStats) == "table" and math.clamp(math.floor(tonumber(saved.Rift.LvStats[key]) or 0), 0, 99) or 0 end return list end)(), LvGold = math.clamp(math.floor(tonumber(saved.Rift.LvGold) or 0), 0, Config.LevelStats.MaxGoldPoints), AugBoss = (function() local list = {} if typeof(saved.Rift.AugBoss) == "table" then for z = 1, Config.Field.ZoneCount do if saved.Rift.AugBoss[tostring(z)] == true then list[tostring(z)] = true end end end return list end)(), AugLv = (function() local list = {} if typeof(saved.Rift.AugLv) == "table" then for z = 1, Config.Field.ZoneCount do local lv = math.clamp(math.floor(tonumber(saved.Rift.AugLv[tostring(z)]) or 0), 0, 3) if lv > 0 then list[tostring(z)] = lv end end end return list end)(), AugOn = (function() local list = {} if typeof(saved.Rift.AugOn) == "table" then for z = 1, Config.Field.ZoneCount do if saved.Rift.AugOn[tostring(z)] == true then list[tostring(z)] = true end end end return list end)() }
		end
	end
	states[player] = state
	syncSkillAttributes(player, state)
	applyPetStats(player, state)
	player:SetAttribute("RiftBest", state.Rift.BestScore)
	player:SetAttribute("RiftBossBest", state.Rift.BestBoss)
	player:SetAttribute("RiftTimeBest", state.Rift.BestTime)
	Meta.RefreshPetModel(player)
	Meta.Push(player)
end

function Meta.Serialize(player)
	local state = states[player]
	if not state then return nil end
	return { Skills = state.Skills, Pet = state.Pet, Tower = state.Tower, Rift = state.Rift, Codex = state.Codex }
end

function Meta.Forget(player)
	states[player] = nil
end

-- 도감: 몬스터 처치 수 / 구역 군주 처치 수 / 세트 장비 획득 수 (키는 문자열: "Slime", "1", "Zone3")
function Meta.CodexKill(player, typeKey, bossZone)
	local state = states[player]
	if not state then return end
	local group, key = "Kills", typeKey
	if bossZone then group, key = "Boss", tostring(bossZone) end
	if typeof(key) ~= "string" then return end
	state.Codex[group][key] = (state.Codex[group][key] or 0) + 1
end

function Meta.CodexSet(player, setKey)
	local state = states[player]
	if not state or typeof(setKey) ~= "string" then return end
	state.Codex.Sets[setKey] = (state.Codex.Sets[setKey] or 0) + 1
end

-- 기본값(저장 데이터가 없을 때) 초기화: setupPlayer 에서 호출
function Meta.Init(player)
	if not states[player] then
		Meta.Load(player, nil)
	end
end

------------------------------------------------------------
-- 무한의 탑 기록
------------------------------------------------------------
-- 심연 도전 기록 (RiftService 가 읽고 쓴다): { Best, Day, Used }
function Meta.GetRift(player)
	local state = states[player]
	return state and state.Rift or nil
end

------------------------------------------------------------
-- 스킬 강화
------------------------------------------------------------
local function upgradeSkill(player, key)
	local state = states[player]
	if not state or typeof(key) ~= "string" or key == "Order" or not Config.Skills[key] or not state.Skills[key] then return end
	local level = state.Skills[key]
	if level >= Config.SkillUpgrade.MaxLevel then
		notify(player, "Already at max level!")
		return
	end
	local cost = Config.GetSkillUpgradeCost(level)
	local gold = player:GetAttribute("Gold") or 0
	if gold < cost then
		notify(player, string.format("Not enough gold. (%d G needed)", cost))
		return
	end
	player:SetAttribute("Gold", gold - cost)
	state.Skills[key] = level + 1
	player:SetAttribute("SkillLv_" .. key, level + 1)
	notify(player, string.format("✨ %s Lv.%d!", Config.Skills[key].Name, level + 1))
	Meta.Push(player)
end

------------------------------------------------------------
-- 펫: 기능 열기 (골드 한 번) / 레벨업 (골드) / 외형 / 색
------------------------------------------------------------
local function unlockPet(player)
	local state = states[player]
	if not state or state.Pet.Unlocked then return end
	local cost = Config.Pet.UnlockCost
	local gold = player:GetAttribute("Gold") or 0
	if gold < cost then
		notify(player, string.format("Not enough gold. (%d G needed)", cost))
		return
	end
	player:SetAttribute("Gold", gold - cost)
	state.Pet.Unlocked = true
	state.Pet.Level = 1
	notify(player, "🐾 Pets unlocked! Level up with gold to gain new abilities. (More looks unlock by defeating Lords or earning titles)")
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		Effects.Burst(root.Position + Vector3.new(0, 3, 0), Color3.fromRGB(255, 220, 120), 80)
	end
	applyPetStats(player, state)
	Meta.RefreshPetModel(player)
	Meta.Push(player)
end

local function levelUpPet(player)
	local state = states[player]
	if not state or not state.Pet.Unlocked then return end
	local level = state.Pet.Level
	if level >= Config.Pet.MaxLevel then
		notify(player, "Your pet is already at max level!")
		return
	end
	local cost = Config.GetPetLevelCost(level)
	local gold = player:GetAttribute("Gold") or 0
	if gold < cost then
		notify(player, string.format("Not enough gold. (%d G needed)", cost))
		return
	end
	player:SetAttribute("Gold", gold - cost)
	state.Pet.Level = level + 1
	local gained
	for _, fn in ipairs(Config.Pet.Functions) do
		if fn.Level == level + 1 then gained = fn end
	end
	notify(player, gained and string.format("🐾 Pet Lv.%d! New ability %s %s — %s", level + 1, gained.Icon, gained.Name, gained.Desc) or string.format("🐾 Pet Lv.%d!", level + 1))
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		Effects.Burst(root.Position + Vector3.new(0, 3, 0), Color3.fromRGB(255, 225, 120), gained and 70 or 30)
	end
	applyPetStats(player, state)
	Meta.Push(player)
end

local function setPetLook(player, key)
	local state = states[player]
	if not state or not state.Pet.Unlocked then return end
	if typeof(key) ~= "string" or not lookUnlocked(player, key) then
		notify(player, "This look isn't unlocked yet.")
		return
	end
	state.Pet.Look = key
	applyPetStats(player, state)
	Meta.RefreshPetModel(player)
	Meta.Push(player)
end

local function setPetColor(player, index)
	local state = states[player]
	if not state or not state.Pet.Unlocked or typeof(index) ~= "number" then return end
	state.Pet.Color = math.clamp(math.floor(index), 1, #Config.Pet.Colors)
	Meta.RefreshPetModel(player)
	Meta.Push(player)
end

-- 펫 수호: 체력이 25% 아래로 떨어지면 3초 동안 무적 (90초마다)
local guardReady = setmetatable({}, { __mode = "k" })
task.spawn(function()
	while true do
		task.wait(0.4)
		local now = os.clock()
		for _, player in ipairs(Players:GetPlayers()) do
			if (player:GetAttribute("PetGuard") or 0) > 0 and now >= (guardReady[player] or 0) then
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 and humanoid.Health / math.max(1, humanoid.MaxHealth) <= 0.25 and not character:FindFirstChildOfClass("ForceField") then
					guardReady[player] = now + 90
					local shield = Instance.new("ForceField")
					shield.Parent = character
					game:GetService("Debris"):AddItem(shield, 3)
					notify(player, "🛡 Pet's Guard! Invincible for 3 seconds (every 90 seconds)")
				end
			end
		end
	end
end)

local last = setmetatable({}, { __mode = "k" })
Players.PlayerRemoving:Connect(function(player)
	last[player] = nil
end)

Remotes.Meta.OnServerEvent:Connect(function(player, action, arg)
	local now = os.clock()
	if now - (last[player] or 0) < 0.25 then return end
	last[player] = now
	if action == "Request" then
		Meta.Push(player)
	elseif action == "Codex" then
		local state = states[player]
		if state then Remotes.Meta:FireClient(player, "Codex", state.Codex) end
	elseif action == "PetPeek" then -- 펫 창을 열어 봤다 (첫날 퀘스트 "펫 구경")
		local okQ, Quest = pcall(function() return require(script.Parent:WaitForChild("QuestService")) end)
		if okQ then Quest.Add(player, "PetPeek", 1) end
	elseif action == "SkillUp" then
		upgradeSkill(player, arg)
	elseif action == "PetUnlock" then
		unlockPet(player)
	elseif action == "PetLevel" then
		levelUpPet(player)
	elseif action == "PetLook" then
		setPetLook(player, arg)
	elseif action == "PetColor" then
		setPetColor(player, arg)
	end
end)

return Meta
