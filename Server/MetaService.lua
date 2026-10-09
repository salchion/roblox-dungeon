-- MetaService (ServerScriptService > Modules 안의 ModuleScript, 이름: MetaService)
-- 캐릭터 성장 보조 시스템 세 가지를 한곳에서 관리한다.
--   1) 스킬 강화: 골드로 스킬 레벨업 (SkillLv_<스킬> Attribute)
--   2) 펫: 알 부화 / 장착 / 따라다니는 펫 모델 + 능력치 (PetDamage, PetCrit, PetXp, PetSpeed, PetHaste Attribute)
--   3) 무한의 탑 최고 층 (TowerBest Attribute)
-- 저장: { Skills = {Barrier=1,...}, Pets = {Owned={Key=레벨}}, Equipped = "Key", Tower = 최고층 }

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Effects = require(script.Parent:WaitForChild("Effects"))
local Level = require(script.Parent:WaitForChild("LevelService"))
local Event = require(script.Parent:WaitForChild("EventService"))

local Meta = {}

local states = {} -- [player] = { Skills, Owned, Equipped, Tower }

local PET_STATS = { "Damage", "Crit", "Xp", "Speed", "Haste" }

local function notify(player, text)
	Remotes.Notify:FireClient(player, text)
end

------------------------------------------------------------
-- 펫 능력치 / 모델
------------------------------------------------------------
local function applyPetStats(player, state)
	for _, stat in ipairs(PET_STATS) do
		player:SetAttribute("Pet" .. stat, 0)
	end
	local key = state.Equipped
	local level = key and state.Owned[key]
	if key and level and Config.Pets[key] then
		local pet = Config.Pets[key]
		player:SetAttribute("Pet" .. pet.Stat, Config.GetPetValue(key, level))
	end
	player:SetAttribute("PetKey", key or "")
end

local function removePetModel(player)
	local character = player.Character
	local old = character and character:FindFirstChild("PetModel")
	if old then old:Destroy() end
end

-- 캐릭터 옆을 둥둥 떠서 따라다니는 펫 (AlignPosition 으로 부드럽게 따라옴)
function Meta.RefreshPetModel(player)
	local state = states[player]
	removePetModel(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not state or not state.Equipped or not root then return end
	local key = state.Equipped
	local pet = Config.Pets[key]
	if not pet then return end

	local model = Instance.new("Model")
	model.Name = "PetModel"

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.new(1.8, 1.8, 1.8)
	body.Color = pet.Color
	body.Material = Enum.Material.Neon
	body.CanCollide = false
	body.CanQuery = false
	body.CanTouch = false
	body.Massless = true
	body.CFrame = root.CFrame * CFrame.new(3, 2.5, 3)
	body.Parent = model

	local light = Instance.new("PointLight")
	light.Range = 12
	light.Brightness = 1.5
	light.Color = pet.Color
	light.Parent = body

	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Rate = 8 + pet.Rarity * 6
	sparkle.Lifetime = NumberRange.new(0.5, 1)
	sparkle.Speed = NumberRange.new(0.5, 1.5)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.LightEmission = 1
	sparkle.Color = ColorSequence.new(pet.Color)
	sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
	sparkle.Parent = body

	-- 눈 두 개 (귀여움)
	for side = -1, 1, 2 do
		local eye = Instance.new("Part")
		eye.Shape = Enum.PartType.Ball
		eye.Size = Vector3.new(0.35, 0.35, 0.35)
		eye.Color = Color3.new(0, 0, 0)
		eye.Material = Enum.Material.SmoothPlastic
		eye.CanCollide = false
		eye.CanQuery = false
		eye.Massless = true
		eye.CFrame = body.CFrame * CFrame.new(side * 0.35, 0.2, -0.75)
		eye.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = body
		weld.Part1 = eye
		weld.Parent = eye
	end

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

	model.PrimaryPart = body
	model.Parent = character
	pcall(function()
		body:SetNetworkOwner(nil)
	end)
end

------------------------------------------------------------
-- 클라이언트로 상태 보내기
------------------------------------------------------------
local function buildPayload(state)
	return { Skills = state.Skills, Owned = state.Owned, Equipped = state.Equipped, Tower = state.Tower, Prestige = state.Prestige }
end

function Meta.Push(player)
	local state = states[player]
	if state and player.Parent then
		Remotes.Meta:FireClient(player, "State", buildPayload(state))
	end
end

------------------------------------------------------------
-- 불러오기 / 저장
------------------------------------------------------------
local function syncSkillAttributes(player, state)
	for _, key in ipairs(Config.Skills.Order) do
		player:SetAttribute("SkillLv_" .. key, state.Skills[key])
	end
end

function Meta.Load(player, saved)
	local state = { Skills = {}, Owned = {}, Equipped = nil, Tower = 0, Prestige = 0, Rift = { Best = 0, Day = 0, Used = 0, Depth = 1, DepthDone = 0, Bests = {}, Hints = {}, LvStats = {} } }
	for _, key in ipairs(Config.Skills.Order) do
		local level = typeof(saved) == "table" and typeof(saved.Skills) == "table" and tonumber(saved.Skills[key]) or 1
		state.Skills[key] = math.clamp(math.floor(level), 1, Config.SkillUpgrade.MaxLevel)
	end
	if typeof(saved) == "table" then
		if typeof(saved.Owned) == "table" then
			for _, key in ipairs(Config.Pets.Order) do
				local level = tonumber(saved.Owned[key])
				if level then
					state.Owned[key] = math.clamp(math.floor(level), 1, Config.Pets.MaxLevel)
				end
			end
		end
		if typeof(saved.Equipped) == "string" and state.Owned[saved.Equipped] then
			state.Equipped = saved.Equipped
		end
		state.Tower = math.max(0, math.floor(tonumber(saved.Tower) or 0))
		state.Prestige = math.clamp(math.floor(tonumber(saved.Prestige) or 0), 0, Config.Prestige.Max)
		if typeof(saved.Rift) == "table" then
			state.Rift = { Best = math.max(0, math.floor(tonumber(saved.Rift.Best) or 0)), Day = math.floor(tonumber(saved.Rift.Day) or 0), Used = math.max(0, math.floor(tonumber(saved.Rift.Used) or 0)), Tip = saved.Rift.Tip == true, DungeonTip = saved.Rift.DungeonTip == true, DungeonDay = math.floor(tonumber(saved.Rift.DungeonDay) or 0), DungeonUsed = math.max(0, math.floor(tonumber(saved.Rift.DungeonUsed) or 0)), KeyDay = math.floor(tonumber(saved.Rift.KeyDay) or 0), KeyDropsTier = typeof(saved.Rift.KeyDropsTier) == "table" and { tonumber(saved.Rift.KeyDropsTier[1]) or 0, tonumber(saved.Rift.KeyDropsTier[2]) or 0, tonumber(saved.Rift.KeyDropsTier[3]) or 0 } or { 0, 0, 0 }, Hints = (function() local list = {} if typeof(saved.Rift.Hints) == "table" then for key, value in pairs(saved.Rift.Hints) do if typeof(key) == "string" and #key <= 24 and value == true then list[key] = true end end end return list end)(), GrowthTip = saved.Rift.GrowthTip == true, Depth = math.clamp(math.floor(tonumber(saved.Rift.Depth) or 1), 1, Config.Rift.MaxDepth), DepthDone = math.clamp(math.floor(tonumber(saved.Rift.DepthDone) or 0), 0, Config.Rift.MaxDepth), Bests = (function() local list = {} if typeof(saved.Rift.Bests) == "table" then for i = 1, Config.Rift.MaxDepth do list[i] = math.max(0, math.floor(tonumber(saved.Rift.Bests[i]) or 0)) end end return list end)(), IdleSeen = math.max(0, math.floor(tonumber(saved.Rift.IdleSeen) or 0)), LvStats = (function() local list = {} for _, key in ipairs(Config.LevelStats.Order) do list[key] = typeof(saved.Rift.LvStats) == "table" and math.clamp(math.floor(tonumber(saved.Rift.LvStats[key]) or 0), 0, 99) or 0 end return list end)() }
		end
	end
	states[player] = state
	syncSkillAttributes(player, state)
	applyPetStats(player, state)
	player:SetAttribute("Prestige", state.Prestige)
	player:SetAttribute("RiftBest", state.Rift.Best)
	Meta.RefreshPetModel(player)
	Meta.Push(player)
end

function Meta.Serialize(player)
	local state = states[player]
	if not state then return nil end
	return { Skills = state.Skills, Owned = state.Owned, Equipped = state.Equipped or "", Tower = state.Tower, Prestige = state.Prestige, Rift = state.Rift }
end

function Meta.Forget(player)
	states[player] = nil
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
		notify(player, "이미 최대 레벨이에요!")
		return
	end
	local cost = Config.GetSkillUpgradeCost(level)
	local gold = player:GetAttribute("Gold") or 0
	if gold < cost then
		notify(player, string.format("골드가 부족해요. (%d G 필요)", cost))
		return
	end
	player:SetAttribute("Gold", gold - cost)
	state.Skills[key] = level + 1
	player:SetAttribute("SkillLv_" .. key, level + 1)
	notify(player, string.format("✨ %s Lv.%d!", Config.Skills[key].Name, level + 1))
	Meta.Push(player)
end

------------------------------------------------------------
-- 펫: 알 부화 / 장착
------------------------------------------------------------
local function rollPet()
	local weights = Config.Pets.RarityWeights
	local total = 0
	for _, w in ipairs(weights) do total += w end
	local roll = math.random() * total
	local rarity = 1
	for i, w in ipairs(weights) do
		roll -= w
		if roll <= 0 then
			rarity = i
			break
		end
	end
	local pool = {}
	for _, key in ipairs(Config.Pets.Order) do
		if Config.Pets[key].Rarity == rarity then
			table.insert(pool, key)
		end
	end
	return pool[math.random(#pool)]
end

local function hatch(player)
	local state = states[player]
	if not state then return end
	if player:GetAttribute("Zone") ~= "Lobby" then
		notify(player, "알 부화는 로비에서만 할 수 있어요.")
		return
	end
	local gold = player:GetAttribute("Gold") or 0
	local cost = Config.Pets.EggCost
	if gold < cost then
		notify(player, string.format("골드가 부족해요. (%d G 필요)", cost))
		return
	end
	player:SetAttribute("Gold", gold - cost)

	local key = rollPet()
	local pet = Config.Pets[key]
	local level = state.Owned[key]
	local message
	if not level then
		state.Owned[key] = 1
		message = string.format("🥚 [%s] %s 부화!", Config.Pets.RarityNames[pet.Rarity], pet.Name)
		if pet.Rarity >= 4 then
			Event.Announce(string.format("📢 %s 님이 전설 펫 [%s]을(를) 부화했어요!", player.DisplayName, pet.Name))
		end
		if not state.Equipped then
			state.Equipped = key
		end
	elseif level < Config.Pets.MaxLevel then
		state.Owned[key] = level + 1
		message = string.format("🥚 %s 또 나왔어요! 펫 레벨 %d!", pet.Name, level + 1)
	else
		player:SetAttribute("Gold", (player:GetAttribute("Gold") or 0) + math.floor(cost * 0.5))
		message = string.format("🥚 %s (최대 레벨) — 골드 %d G 환급", pet.Name, math.floor(cost * 0.5))
	end
	notify(player, message)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		Effects.Burst(root.Position + Vector3.new(0, 3, 0), Config.Pets.RarityColors[pet.Rarity], 25 + pet.Rarity * 15)
	end
	applyPetStats(player, state)
	Meta.RefreshPetModel(player)
	Meta.Push(player)
end

local function equipPet(player, key)
	local state = states[player]
	if not state then return end
	if key == "" then
		state.Equipped = nil
	elseif typeof(key) == "string" and key ~= "Order" and Config.Pets[key] and state.Owned[key] then
		state.Equipped = key
	else
		return
	end
	applyPetStats(player, state)
	Meta.RefreshPetModel(player)
	Meta.Push(player)
end

-- 환생: 최고 레벨에서 레벨을 1로 되돌리고 영구 공격력 보너스를 얻는다 (장비 / 무기 / 돌파 진행은 그대로)
local function prestige(player)
	local state = states[player]
	if not state then return end
	if player:GetAttribute("Zone") ~= "Lobby" then
		notify(player, "환생은 로비에서만 할 수 있어요.")
		return
	end
	if (player:GetAttribute("Level") or 1) < Config.Level.Max then
		notify(player, string.format("레벨 %d 에서 환생할 수 있어요.", Config.Level.Max))
		return
	end
	if state.Prestige >= Config.Prestige.Max then
		notify(player, "이미 최대 환생 단계예요!")
		return
	end
	state.Prestige += 1
	player:SetAttribute("Prestige", state.Prestige)
	Level.Load(player, 1, 0)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		Effects.Burst(root.Position + Vector3.new(0, 3, 0), Color3.fromRGB(255, 230, 120), 120)
	end
	notify(player, string.format("🌟 환생 %d단계! 영구 공격력 +%d%% · 골드 획득량 +%d%% (총 공격력 +%d%%, 골드 +%d%%)", state.Prestige, Config.Prestige.DamagePerRank * 100, Config.Prestige.GoldPerRank * 100, state.Prestige * Config.Prestige.DamagePerRank * 100, state.Prestige * Config.Prestige.GoldPerRank * 100))
	Meta.Push(player)
end

local last = {}
Players.PlayerRemoving:Connect(function(player)
	last[player] = nil
end)

Remotes.Meta.OnServerEvent:Connect(function(player, action, arg)
	local now = os.clock()
	if now - (last[player] or 0) < 0.25 then return end
	last[player] = now
	if action == "Request" then
		Meta.Push(player)
	elseif action == "SkillUp" then
		upgradeSkill(player, arg)
	elseif action == "Prestige" then
		prestige(player)
	elseif action == "Hatch" then
		hatch(player)
	elseif action == "Equip" then
		equipPet(player, arg)
	end
end)

return Meta
