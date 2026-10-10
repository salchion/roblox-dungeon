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

-- 지금 가장 도움이 되는 조언 목록 (우선순위 순)
local function collect(player)
	local tips = {}
	local gold = player:GetAttribute("Gold") or 0
	local level = player:GetAttribute("WeaponLevel") or 0
	local cost = Config.GetEnhanceCost(level)
	if gold >= cost * 2 then
		table.insert(tips, string.format("💰 골드 %d G가 남아 있어요! 마을 모루에서 무기를 강화하면 훨씬 강해져요", gold))
	end
	local tickets = player:GetAttribute("Tickets") or 0
	if tickets >= 1 then
		table.insert(tips, string.format("🎫 장비 티켓 %d장이 남아 있어요! 뽑기 머신에서 장비를 뽑아요", tickets))
	end
	local empty = {}
	for _, slot in ipairs(Config.Gear.Slots) do
		if not Inventory.GetEquipped(player, slot.Key) then
			table.insert(empty, slot.Name)
		end
	end
	if #empty > 0 then
		table.insert(tips, string.format("🛡 %s 장비가 비어 있어요! 던전 보스 상자나 뽑기로 얻어서 장착해요", table.concat(empty, " · ")))
	end
	if Growth.IdleSlots(player) > 0 then
		table.insert(tips, "🏋 훈련 슬롯이 비어 있어요! 메뉴(B) → 성장에서 훈련을 걸어 두면 시간이 지나 저절로 강해져요")
	end
	if (player:GetAttribute("DungeonFree") or 0) > 0 then
		table.insert(tips, string.format("🏰 던전 무료 입장 %d회가 남아 있어요! 던전에서 장비와 티켓을 얻어요", player:GetAttribute("DungeonFree")))
	end
	return tips
end

function Advice.AfterDefeat(player)
	local tips = collect(player)
	if #tips == 0 then return end
	local text = "💡 " .. tips[1]
	if tips[2] then
		text ..= "\n💡 " .. tips[2]
	end
	Remotes.Notify:FireClient(player, text)
end

-- 처음 던전을 마치고 마을로 돌아왔을 때 딱 한 번: "다음 목표(전투력)"와 "무엇으로 강해지는가"를 한 장으로 보여준다 (저장됨)
function Advice.GrowthGuide(player)
	local rift = Meta.GetRift(player)
	if not rift or rift.GrowthTip then return end
	rift.GrowthTip = true
	local power = player:GetAttribute("Power") or 0
	local zone = math.min(#Config.Field.BossPower, (player:GetAttribute("ClearedZone") or 0) + 1)
	local need = Config.Field.BossPower[zone]
	local keys = (player:GetAttribute("Keys") or 0) + (player:GetAttribute("KeysNormal") or 0) + (player:GetAttribute("KeysHard") or 0)
	local tickets, gold = player:GetAttribute("Tickets") or 0, player:GetAttribute("Gold") or 0
	Remotes.Tutorial:FireClient(player, "Growth", {
		Power = power, Zone = zone, Need = need,
		Sources = {
			{ Icon = "🏰", Name = "던전", Desc = "보스 상자에서 장비 · 티켓", Status = string.format("무료 입장 %d회 · 열쇠 %d개", player:GetAttribute("DungeonFree") or 0, keys) },
			{ Icon = "👑", Name = "필드 군주", Desc = "구역 세트 장비 · 열쇠", Status = string.format("다음: 구역 %d", zone) },
			{ Icon = "🎰", Name = "뽑기", Desc = "티켓으로 새 장비", Status = string.format("티켓 %d장", tickets) },
			{ Icon = "🔨", Name = "강화 · 진화", Desc = "골드로 무기를 키운다", Status = string.format("골드 %d G", gold) },
			{ Icon = "🏋", Name = "훈련", Desc = "자리를 비워도 영구 성장", Status = Growth.IdleSlots(player) > 0 and string.format("빈 슬롯 %d개!", Growth.IdleSlots(player)) or "진행 중" },
			{ Icon = "🌀", Name = "심연 도전", Desc = "내 기록에 도전 · 점수 보상", Status = "마을 포털" },
		},
	})
end

return Advice
