-- AdviceService (ServerScriptService > Modules 안의 ModuleScript, 이름: AdviceService)
-- "상황별 조언": 안내 카드를 미리 잔뜩 띄우는 대신, 플레이어가 막히거나 쓰러졌을 때 지금 부족한 것 / 아직 안 쓴 것을 그때그때 짧게 알려준다.
--   Advice.AfterDefeat(player)  : 쓰러졌을 때 (필드 / 던전) 지금 남은 골드 / 티켓 / 빈 장비 / 빈 훈련 슬롯 등을 최대 2가지 알려준다
--   (막힌 행동의 안내는 각 서비스가 직접 한다: 티켓 없음 / 골드 부족 / 열쇠 없음 등 — 문구에 "어떻게 얻는지"를 같이 적는다)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Inventory = require(script.Parent:WaitForChild("InventoryService"))
local Growth = require(script.Parent:WaitForChild("GrowthService"))

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
		table.insert(tips, "🏋 훈련 슬롯이 비어 있어요! 메뉴(I) → 성장에서 훈련을 걸어 두면 시간이 지나 저절로 강해져요")
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

return Advice
