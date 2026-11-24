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
local function comma(n) local s = tostring(math.floor(n or 0)) local r repeat s, r = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2") until r == 0 return s end
local function deathSources(player)
	local list = {}
	local gold = player:GetAttribute("Gold") or 0
	local weaponLevel = player:GetAttribute("WeaponLevel") or 0
	if weaponLevel < Config.Weapon.MaxLevel then
		local okCost, cost = pcall(Config.GetEnhanceCost, weaponLevel)
		if okCost and cost then -- (돈이 모자라도 보여 준다: 벽에서 "할 게 없는 화면"이 됐다. 모자라는 만큼을 숫자로)
			table.insert(list, { Icon = "🔨", Name = "Upgrade your weapon", Desc = "The biggest power boost", Status = gold >= cost and string.format("You can afford it now (%d G)", cost) or string.format("Need %s G more", comma(cost - gold)) })
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
	if cheapest then
		table.insert(list, { Icon = "🛡", Name = "Upgrade your gear", Desc = "More HP and damage", Status = gold >= cheapest and string.format("From %d G", cheapest) or string.format("Need %s G more", comma(cheapest - gold)) })
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

-- 막힘 돌파 카드: 같은 벽(아직 못 깬 다음 구역)에서 10분 안에 3번 쓰러지면, 세로 성장 4갈래(무기 강화 / 끼고 있는 세트 효과 / 던전 / 스탯·훈련)를 한 장으로
--   (구역 세트 모으기 안내는 뺐다: 세트는 일부러 수평이라 4구역 세트 2부위는 치명 +6% 뿐 — 벽 앞에서 옆으로 새는 안내였다)
--   서버 메모리만 (저장 안 함) · 구역마다 세션 1번 · 최소 5분 간격 · 튜토리얼 중 제외. 벌칙이 아니라 안내다
local wallDeaths = setmetatable({}, { __mode = "k" }) -- [player] = { [zone] = { t1, t2, ... } }
local wallShown = setmetatable({}, { __mode = "k" }) -- [player] = { [zone] = true, Last = os.clock() }
function Advice.WallCard(player)
	if player:GetAttribute("TutorialActive") == true then return end
	local zone = math.min(Config.Field.ZoneCount, (player:GetAttribute("ClearedZone") or 0) + 1)
	local now = os.clock()
	local list = wallDeaths[player] or {} -- (11-18: 10분 창은 구역과 상관없이 하나로 센다: 창 도중 ClearedZone 이 바뀌어도 목록이 갈라지지 않게)
	wallDeaths[player] = list
	table.insert(list, now)
	while #list > 0 and now - list[1] > 600 do table.remove(list, 1) end
	local shown = wallShown[player] or {}
	wallShown[player] = shown
	if #list < 3 or shown[zone] or now - (shown.Last or -1e9) < 300 then return end
	shown[zone], shown.Last = true, now
	local augZone, augLv, augCost = nil, 0, nil -- 지금 켜진 세트 효과 중 가장 높은 것의 다음 골드 단계 비용
	for z = 1, Config.Field.ZoneCount do
		if player:GetAttribute("AugOnZ_" .. z) == true then
			local lv = (player:GetAttribute("AugLvZ_" .. z) or 0) + (player:GetAttribute("AugGearZ_" .. z) or 0)
			if lv >= augLv then augZone, augLv = z, lv end
		end
	end
	-- (11-24: 세트 효과는 골드로 올리지 않는다 -> 골드 비용 안내 없음. augCost 는 nil 로 둔다)
	-- 4루트 = 세로 성장 (구역 세트 모으기는 뺐다: 세트는 일부러 수평이라 4구역 세트 2부위는 치명 +6% 뿐, 옆으로 새는 안내였다)
	local gold = player:GetAttribute("Gold") or 0
	local wl = player:GetAttribute("WeaponLevel") or 0
	local upInfo
	if wl >= Config.Weapon.MaxLevel then
		upInfo = "Weapon maxed"
	else
		local okC, cost = pcall(Config.GetEnhanceCost, wl)
		local okM, mile = pcall(Config.GetNextMilestone, wl)
		cost = okC and cost or 0
		upInfo = string.format("<font>+%d · next %s G · you have %s G</font>", wl, comma(cost), comma(gold)) -- (조각마다 <font>: 번역이 조각 단위라)
		if okM and mile and mile.Level then upInfo ..= string.format(" → <font>%s</font> +%d", mile.Name or "", mile.Level) end -- 다음 진화(새 무기 형 / 시대)
	end
	local points = player:GetAttribute("LvPointsLeft") or 0
	local okIdle, idle = pcall(Growth.IdleSlots, player)
	local statsRoute
	if points > 0 then
		statsRoute = { Key = "Stats", Icon = "📊", Name = "Stats", Info = string.format("<font>%d unspent</font> · <font>Lv %d</font>", points, player:GetAttribute("LvTotal") or 0) }
	elseif okIdle and idle and idle > 0 and player:GetAttribute("GrowthUnlocked") == true then
		statsRoute = { Key = "Train", Icon = "🏋", Name = "Training", Info = string.format("<font>%d empty slot(s)</font> · <font>Grows even while you're away</font>", idle) }
	else
		statsRoute = { Key = "Train", Icon = "🏋", Name = "Training", Info = "<font>Grows even while you're away</font>" }
	end
	-- 필드 2축 신호 (11-19, FieldSignalService): 이 구역 군주 한 방 % (받는 피해 배율 TakenMult 반영) / 내 예상 처치 시간
	local hitPct, lordSec
	do
		local okS, SignalService = pcall(function() return require(script.Parent:WaitForChild("FieldSignalService")) end)
		if okS then
			local pct, sec = SignalService.HitPct(player, zone, "Lord"), SignalService.LordSec(player, zone)
			hitPct = pct and math.floor(pct + 0.5) or nil
			lordSec = sec and math.max(1, math.floor(sec + 0.5)) or nil
		end
	end
	local routeUpgrade = { Key = "Upgrade", Icon = "🔨", Name = "Weapon upgrade", Info = upInfo }
	local routeAug = { Key = "Aug", Icon = "✨", Name = "Set effect", Info = augZone and string.format("Set you're wearing Lv.%d · 3 pieces = Lv.6, Guard Stones for defense", augLv) or "No set effect on yet — wear set pieces" } -- (11-24: 골드 단계 안내 없음)
	local routeDungeon = { Key = "Dungeon", Icon = "🏰", Name = "Dungeon", Info = string.format("Best depth %d · Free %d · Keys %d", player:GetAttribute("DepthBest_All") or 0, player:GetAttribute("DungeonFree") or 0, player:GetAttribute("Keys") or 0) }
	-- 돌파 경로: 생존이 막혔으면(한 방 35% 이상) 세트 효과(방어 효과) · 훈련(체력)을 먼저, 아니면 화력(무기 강화 · 세트 효과)을 먼저
	local survival = hitPct and hitPct >= 35
	Remotes.Tutorial:FireClient(player, "Wall", {
		Zone = zone, Deaths = #list, HitPct = hitPct, LordSec = lordSec,
		Routes = survival and { routeAug, statsRoute, routeUpgrade, routeDungeon } or { routeUpgrade, routeAug, routeDungeon, statsRoute },
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
