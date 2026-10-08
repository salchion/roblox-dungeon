-- DataService (ServerScriptService > Modules 안의 ModuleScript, 이름: DataService)
-- 골드 / 무기(종류별 강화) / 장비 / 티켓 / 필드 돌파 구역 / 퀘스트·업적·칭호를 DataStore에 저장/불러오기.
-- Studio에서 "Enable Studio Access to API Services"가 꺼져 있으면 저장 없이 기본값으로 동작한다.

local DataStoreService = game:GetService("DataStoreService")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Config"))
local Quest = require(script.Parent:WaitForChild("QuestService"))
local Inventory = require(script.Parent:WaitForChild("InventoryService"))
local Keys = require(script.Parent:WaitForChild("KeyService"))
local Monetization = require(script.Parent:WaitForChild("MonetizationService"))
local Growth = require(script.Parent:WaitForChild("GrowthService"))
local Daily = require(script.Parent:WaitForChild("DailyService"))
local Meta = require(script.Parent:WaitForChild("MetaService"))
local Tutorial = require(script.Parent:WaitForChild("TutorialService"))

local Data = {}

local okStore, store = pcall(function()
	return DataStoreService:GetDataStore("DungeonPlayerData_v1")
end)
if not okStore then
	store = nil
	warn("[Data] DataStore를 사용할 수 없어 저장 없이 진행합니다.")
end

local loaded = {} -- [player] = true  (불러오기에 성공한 플레이어만 저장 -> 실패 시 기존 데이터 덮어쓰기 방지)

local function keyOf(player)
	return "u_" .. player.UserId
end

-- 무기 종류별 레벨 / 보유 / 장착 (예전 저장 데이터는 WeaponLevel 을 권총 레벨로 이어받음)
local function parseWeapons(saved)
	local result = { Type = "Pistol", Unlocked = {}, Levels = {} }
	local weapons = typeof(saved.Weapons) == "table" and saved.Weapons or {}
	for _, key in ipairs(Config.WeaponTypes.Order) do
		local level = weapons.Levels and tonumber(weapons.Levels[key]) or nil
		if level == nil and key == "Pistol" then
			level = tonumber(saved.WeaponLevel)
		end
		result.Levels[key] = math.clamp(math.floor(level or 0), 0, Config.Weapon.MaxLevel)
		result.Unlocked[key] = key == "Pistol" or (weapons.Unlocked ~= nil and weapons.Unlocked[key] == true)
	end
	if typeof(weapons.Type) == "string" and result.Unlocked[weapons.Type] then
		result.Type = weapons.Type
	end
	-- 예전 저장(무기 종류별 레벨)은 가장 높은 레벨을 이어받는다
	result.Best = 0
	for _, level in pairs(result.Levels) do
		result.Best = math.max(result.Best, level)
	end
	return result
end

function Data.Load(player)
	local defaults = {
		Gold = Config.StartGold, WeaponLevel = 0, Tickets = 0, MaxZone = 0, Gear = {}, Level = 1, XP = 0,
		Weapons = { Type = "Pistol", Unlocked = {}, Levels = {} }, Quest = nil,
		Inventory = nil, Keys = nil, Monetization = nil, Growth = nil, Daily = nil, Meta = nil, Tutorial = nil,
	}
	if not store then return defaults end

	for attempt = 1, 3 do
		local ok, saved = pcall(function()
			return store:GetAsync(keyOf(player))
		end)
		if ok then
			loaded[player] = true
			if typeof(saved) == "table" then
				return {
					Gold = tonumber(saved.Gold) or defaults.Gold,
					WeaponLevel = math.clamp(math.max(tonumber(saved.WeaponLevel) or 0, parseWeapons(saved).Best), 0, Config.Weapon.MaxLevel),
					Tickets = math.max(0, math.floor(tonumber(saved.Tickets) or 0)),
					MaxZone = math.clamp(math.floor(tonumber(saved.MaxZone) or 0), 0, Config.Field.ZoneCount),
					Gear = typeof(saved.Gear) == "table" and saved.Gear or {},
					Level = math.clamp(math.floor(tonumber(saved.Level) or 1), 1, Config.Level.Max),
					XP = math.max(0, math.floor(tonumber(saved.XP) or 0)),
					Weapons = parseWeapons(saved),
					Quest = typeof(saved.Quest) == "table" and saved.Quest or nil,
					Inventory = typeof(saved.Inventory) == "table" and saved.Inventory or nil,
					KeysData = typeof(saved.Keys) == "table" and saved.Keys or nil,
					Monetization = typeof(saved.Monetization) == "table" and saved.Monetization or nil,
					Growth = typeof(saved.Growth) == "table" and saved.Growth or nil,
					Daily = typeof(saved.Daily) == "table" and saved.Daily or nil,
					Meta = typeof(saved.Meta) == "table" and saved.Meta or nil,
					Tutorial = typeof(saved.Tutorial) == "table" and saved.Tutorial or nil,
				}
			end
			return defaults
		end
		task.wait(attempt)
	end
	warn("[Data] 데이터 로드 실패:", player.Name)
	return defaults
end

-- 저장 성공 여부를 돌려준다 (결제 영수증 처리가 "저장된 뒤에만 완료"로 쓰려고)
function Data.Save(player)
	if not store then return true end -- DataStore 를 못 쓰는 환경(Studio API 꺼짐)에서는 저장 없이 진행
	if not loaded[player] then return false end
	local weapons = { Type = player:GetAttribute("WeaponType") or "Pistol", Unlocked = {}, Levels = {} } -- (예전 호환용: 지금은 WeaponLevel 하나만 쓴다)
	local payload = {
		Gold = player:GetAttribute("Gold") or 0,
		WeaponLevel = player:GetAttribute("WeaponLevel") or 0,
		Tickets = player:GetAttribute("Tickets") or 0,
		MaxZone = player:GetAttribute("MaxZone") or 0,
		Level = player:GetAttribute("Level") or 1,
		XP = player:GetAttribute("XP") or 0,
		Inventory = Inventory.Serialize(player),
		Keys = Keys.Serialize(player),
		Monetization = Monetization.Serialize(player),
		Growth = Growth.Serialize(player),
		Daily = Daily.Serialize(player),
		Meta = Meta.Serialize(player),
		Tutorial = Tutorial.Serialize(player),
		Weapons = weapons,
		Quest = Quest.Serialize(player),
	}
	local ok, err = pcall(function()
		store:SetAsync(keyOf(player), payload)
	end)
	if not ok then
		warn("[Data] 저장 실패:", player.Name, err)
	end
	return ok
end

function Data.Forget(player)
	loaded[player] = nil
end

return Data
