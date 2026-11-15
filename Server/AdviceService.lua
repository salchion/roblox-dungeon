-- AdviceService (ServerScriptService > Modules 안의 ModuleScript, 이름: AdviceService)
-- "상황별 조언": 안내 카드를 미리 잔뜩 띄우는 대신, 플레이어가 막히거나 쓰러졌을 때 지금 부족한 것 / 아직 안 쓴 것을 그때그때 짧게 알려준다.
--   Advice.AfterDefeat(player)  : 쓰러졌을 때 (필드 / 던전) 지금 남은 골드 / 티켓 / 빈 장비 / 빈 훈련 슬롯 등을 최대 2가지 알려준다
--   (막힌 행동의 안내는 각 서비스가 직접 한다: 티켓 없음 / 골드 부족 / 열쇠 없음 등 — 문구에 "어떻게 얻는지"를 같이 적는다)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Inventory = require(script.Parent:WaitForChild("InventoryService"))
local Growth = require(script.Parent:WaitForChild("GrowthService"))
local Meta = require(script.Parent:WaitForChild("MetaService"))

local Advice = {}

-- 쓰러졌을 때 보여주는 전투 팁 (한 줄만, 돌아가며): 골드 / 티켓 같은 살림살이 안내는 화면 위쪽이 시끄러워져서 뺐다
local COMBAT_TIPS = {
	"💡 Dash (Q) through enemy attacks at the last moment for a NEAR MISS: your damage stacks up",
	"💡 Use First Aid (C) before your HP gets low, not after",
	"💡 Deadeye (V) hits many enemies at once: save it for crowds and bosses",
	"💡 Keep moving! Enemies that surround you deal a lot of damage",
	"💡 Fight near the camp edge first, then push forward a little at a time",
	"💡 Blade Bloom (F) whirls daggers around you: keep moving and shooting while it spins",
	"💡 Aim for the glowing weak point on bosses for triple damage",
}
local tipIndex = setmetatable({}, { __mode = "k" })

-- 쓰러졌을 때 "지금 바로 할 수 있는 강해지는 방법" 요약 카드 (모바일 게임의 패배 화면처럼). 가능한 것만, 할 수 있는 순서대로 최대 4개
local lastGuide = setmetatable({}, { __mode = "k" })
local function deathSources(player)
	local list = {}
	local gold = player:GetAttribute("Gold") or 0
	local weaponLevel = player:GetAttribute("WeaponLevel") or 0
	if weaponLevel < Config.Weapon.MaxLevel then
		local okCost, cost = pcall(Config.GetEnhanceCost, weaponLevel)
		if okCost and cost and gold >= cost then
			table.insert(list, { Icon = "🔨", Name = "Upgrade your weapon", Desc = "The biggest power boost", Status = string.format("You can afford it now (%d G)", cost) })
		end
	end
	local cheapest
	for _, slot in ipairs(Config.Gear.Slots) do
		local rarity = player:GetAttribute("Gear_" .. slot.Key .. "_R") or 0
		local level = player:GetAttribute("Gear_" .. slot.Key .. "_L") or 0
		if rarity > 0 and level < Config.Gear.MaxLevel then
			local okCost, cost = pcall(Config.GetGearCost, slot.Key, rarity, level)
			if okCost and cost and (not cheapest or cost < cheapest) then cheapest = cost end
		end
	end
	if cheapest and gold >= cheapest then
		table.insert(list, { Icon = "🛡", Name = "Upgrade your gear", Desc = "More HP and damage", Status = string.format("From %d G", cheapest) })
	end
	local points = player:GetAttribute("LvPointsLeft") or 0
	if points > 0 then
		table.insert(list, { Icon = "✨", Name = "Spend stat points", Desc = "Press T", Status = string.format("%d unspent", points) })
	end
	local tickets = player:GetAttribute("Tickets") or 0
	if tickets > 0 then
		table.insert(list, { Icon = "🎰", Name = "Roll for gear", Desc = "Gacha machine in town", Status = string.format("Tickets %d", tickets) })
	end
	local okIdle, idle = pcall(Growth.IdleSlots, player)
	if okIdle and idle and idle > 0 and player:GetAttribute("GrowthUnlocked") == true then
		table.insert(list, { Icon = "🏋", Name = "Start training", Desc = "Grows even while you're away", Status = string.format("%d empty slot(s)", idle) })
	end
	if (player:GetAttribute("DungeonFree") or 0) > 0 then
		table.insert(list, { Icon = "🏰", Name = "Run a dungeon", Desc = "Gear and tickets from the boss chest", Status = string.format("Free entries %d", player:GetAttribute("DungeonFree")) })
	end
	while #list > 4 do table.remove(list) end
	return list
end

-- 막힘 돌파 카드: 같은 벽(아직 못 깬 다음 구역)에서 10분 안에 3번 쓰러지면, "다른 문" 4가지(던전 / 도감·세트 보너스 / 세트 효과 / 파티)를 한 장으로
--   서버 메모리만 (저장 안 함) · 구역마다 세션 1번 · 최소 5분 간격 · 튜토리얼 중 제외. 벌칙이 아니라 안내다
local wallDeaths = setmetatable({}, { __mode = "k" }) -- [player] = { [zone] = { t1, t2, ... } }
local wallShown = setmetatable({}, { __mode = "k" }) -- [player] = { [zone] = true, Last = os.clock() }
local function comma(n) local s = tostring(math.floor(n or 0)) local r repeat s, r = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2") until r == 0 return s end
function Advice.WallCard(player)
	if player:GetAttribute("TutorialActive") == true then return end
	local zone = math.min(Config.Field.ZoneCount, (player:GetAttribute("ClearedZone") or 0) + 1)
	local now = os.clock()
	local byZone = wallDeaths[player] or {}
	wallDeaths[player] = byZone
	local list = byZone[zone] or {}
	byZone[zone] = list
	table.insert(list, now)
	while #list > 0 and now - list[1] > 600 do table.remove(list, 1) end
	local shown = wallShown[player] or {}
	wallShown[player] = shown
	if #list < 3 or shown[zone] or now - (shown.Last or -1e9) < 300 then return end
	shown[zone], shown.Last = true, now
	local setKey = Config.Sets.ZoneKeys[zone]
	local setDef = setKey and Config.Sets[setKey]
	local b2 = {}
	for _, b in ipairs(setDef and setDef.Bonuses[2] or {}) do table.insert(b2, Config.FormatBonus(b.Stat, b.Value)) end
	local augZone, augLv, augCost = nil, 0, nil -- 지금 켜진 세트 효과 중 가장 높은 것의 다음 골드 단계 비용
	for z = 1, Config.Field.ZoneCount do
		if player:GetAttribute("AugOnZ_" .. z) == true then
			local lv = (player:GetAttribute("AugLvZ_" .. z) or 0) + (player:GetAttribute("AugGearZ_" .. z) or 0)
			if lv >= augLv then augZone, augLv = z, lv end
		end
	end
	if augZone then
		local gold = player:GetAttribute("AugLvZ_" .. augZone) or 0
		if gold < 3 then augCost = Config.Sets.AugCost(augZone, gold + 1, player:GetAttribute("MaxZone") or augZone) end
	end
	Remotes.Tutorial:FireClient(player, "Wall", {
		Zone = zone, Deaths = #list,
		Routes = {
			{ Key = "Dungeon", Icon = "🏰", Name = "Dungeon", Info = string.format("Town north gate · boss chest gear + gold · Free %d · Keys %d", player:GetAttribute("DungeonFree") or 0, player:GetAttribute("Keys") or 0) },
			{ Key = "Codex", Icon = "📖", Name = "Zone set", Info = setDef and string.format("%s %s 2 pieces: %s", setDef.Icon or "", setDef.Name, table.concat(b2, " · ")) or "Collect this zone's set gear" },
			{ Key = "Aug", Icon = "✨", Name = "Set effect", Info = augZone and (augCost and string.format("Lv.%d now · next gold level %s G", augLv, comma(augCost)) or string.format("Lv.%d now · gold levels maxed", augLv)) or "No set effect on yet — wear 2+ set pieces" },
			{ Key = "Party", Icon = "🤝", Name = "Party", Info = "Party panel (town, top right) · +4% damage per nearby member (up to +12%)" },
		},
	})
end

function Advice.AfterDefeat(player)
	pcall(Advice.WallCard, player) -- (필드 / 던전 패배 모두 여기를 지난다)
	if player:GetAttribute("TutorialActive") == true then return end -- (튜토리얼 중의 패배는 연출(최후의 군주)이라 조언 / 팁을 띄우지 않는다: 미션 안내와 겹쳐 복잡했다)
	local index = (tipIndex[player] or 0) % #COMBAT_TIPS + 1
	tipIndex[player] = index
	Remotes.Notify:FireClient(player, COMBAT_TIPS[index])
	-- 성장 요약 카드: 튜토리얼 중이 아니고, 2분에 한 번만
	if player:GetAttribute("TutorialActive") == true or os.clock() - (lastGuide[player] or -1000) < 120 then return end
	local sources = deathSources(player)
	if #sources == 0 then return end
	lastGuide[player] = os.clock()
	local zone = math.min(#Config.Field.RecommendPower, (player:GetAttribute("ClearedZone") or 0) + 1)
	Remotes.Tutorial:FireClient(player, "Growth", {
		Death = true, Power = player:GetAttribute("Power") or 0, Zone = zone, Need = Config.Field.RecommendPower[zone], Sources = sources,
	})
end

-- 처음 던전을 마치고 마을로 돌아왔을 때 딱 한 번: "다음 목표(전투력)"와 "무엇으로 강해지는가"를 한 장으로 보여준다 (저장됨)
function Advice.GrowthGuide(player)
	local rift = Meta.GetRift(player)
	if not rift or rift.GrowthTip then return end
	-- 튜토리얼 중이면 끝난 뒤에 보여 준다 (미션 카드 / 안내 카드와 한꺼번에 떠서 무엇을 할지 헷갈렸다)
	if player:GetAttribute("TutorialActive") == true then
		local conn
		conn = player:GetAttributeChangedSignal("TutorialActive"):Connect(function()
			if player:GetAttribute("TutorialActive") ~= true then
				conn:Disconnect()
				task.delay(4, function() if player.Parent then Advice.GrowthGuide(player) end end)
			end
		end)
		return
	end
	rift.GrowthTip = true
	local power = player:GetAttribute("Power") or 0
	local zone = math.min(#Config.Field.RecommendPower, (player:GetAttribute("ClearedZone") or 0) + 1)
	local need = Config.Field.RecommendPower[zone]
	local keys = (player:GetAttribute("Keys") or 0) + (player:GetAttribute("KeysNormal") or 0) + (player:GetAttribute("KeysHard") or 0)
	local tickets, gold = player:GetAttribute("Tickets") or 0, player:GetAttribute("Gold") or 0
	Remotes.Tutorial:FireClient(player, "Growth", {
		Power = power, Zone = zone, Need = need,
		Sources = {
			{ Icon = "🏰", Name = "Dungeon", Desc = "Gear & tickets from boss chests", Status = string.format("Free entries %d · Keys %d", player:GetAttribute("DungeonFree") or 0, keys) },
			{ Icon = "👑", Name = "Field Lord", Desc = "Zone set gear & keys", Status = string.format("Next: Zone %d", zone) },
			{ Icon = "🎰", Name = "Gacha", Desc = "New gear with tickets", Status = string.format("Tickets %d", tickets) },
			{ Icon = "🔨", Name = "Upgrade · Evolve", Desc = "Power up your weapon with gold", Status = string.format("Gold %d G", gold) },
			{ Icon = "🏋", Name = "Training", Desc = "Permanent growth, even while away", Status = Growth.IdleSlots(player) > 0 and string.format("%d empty slot(s)!", Growth.IdleSlots(player)) or "In progress" },
			{ Icon = "🌀", Name = "Boss Rush", Desc = "Weekly ranking · tier rewards", Status = "Town portal" },
		},
	})
end

return Advice
