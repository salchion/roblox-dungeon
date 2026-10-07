-- DataService (ServerScriptService > Modules 안의 ModuleScript, 이름: DataService)
-- 골드 / 무기 강화 / 장비 / 티켓 / 필드 돌파 구역을 DataStore에 저장/불러오기.
-- Studio에서 "Enable Studio Access to API Services"가 꺼져 있으면 저장 없이 기본값으로 동작한다.

local DataStoreService = game:GetService("DataStoreService")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Config"))

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

function Data.Load(player)
	local defaults = { Gold = Config.StartGold, WeaponLevel = 0, Tickets = 0, MaxZone = 0, Gear = {} }
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
					WeaponLevel = math.clamp(tonumber(saved.WeaponLevel) or 0, 0, Config.Weapon.MaxLevel),
					Tickets = math.max(0, math.floor(tonumber(saved.Tickets) or 0)),
					MaxZone = math.clamp(math.floor(tonumber(saved.MaxZone) or 0), 0, Config.Field.ZoneCount),
					Gear = typeof(saved.Gear) == "table" and saved.Gear or {},
				}
			end
			return defaults
		end
		task.wait(attempt)
	end
	warn("[Data] 데이터 로드 실패:", player.Name)
	return defaults
end

function Data.Save(player)
	if not store or not loaded[player] then return end
	local gear = {}
	for _, slot in ipairs(Config.Gear.Slots) do
		gear[slot.Key] = {
			R = player:GetAttribute("Gear_" .. slot.Key .. "_R") or 0,
			L = player:GetAttribute("Gear_" .. slot.Key .. "_L") or 0,
		}
	end
	local payload = {
		Gold = player:GetAttribute("Gold") or 0,
		WeaponLevel = player:GetAttribute("WeaponLevel") or 0,
		Tickets = player:GetAttribute("Tickets") or 0,
		MaxZone = player:GetAttribute("MaxZone") or 0,
		Gear = gear,
	}
	local ok, err = pcall(function()
		store:SetAsync(keyOf(player), payload)
	end)
	if not ok then
		warn("[Data] 저장 실패:", player.Name, err)
	end
end

function Data.Forget(player)
	loaded[player] = nil
end

return Data
