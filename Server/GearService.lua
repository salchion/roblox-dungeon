-- GearService (ServerScriptService > Modules 안의 ModuleScript, 이름: GearService)
-- 방어구(갑옷 / 장갑 / 신발): 보스 티켓으로 뽑기 -> 골드로 강화 -> 능력치 + 캐릭터 외형 반영.
--   갑옷: 최대 체력 / 장갑: 치명타 확률 / 신발: 이동 속도
-- 부위별 장비는 플레이어 Attribute 에 들어 있다 (등급 Gear_<부위>_R, 강화 Gear_<부위>_L). 0이면 비어 있음.
-- 합산 효과는 GearHealth / GearCrit / GearSpeed Attribute 로 계산되어 다른 시스템이 읽어 쓴다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Effects = require(script.Parent:WaitForChild("Effects"))

local G = Config.Gear

local Gear = {}

local function rAttr(key) return "Gear_" .. key .. "_R" end
local function lAttr(key) return "Gear_" .. key .. "_L" end

-- 부위별로 외형을 덧씌울 신체 부위 (R15 / R6 이름을 모두 적어둠)
local LIMBS = {
	Armor = { "UpperTorso", "Torso" },
	Gloves = { "LeftHand", "RightHand", "Left Arm", "Right Arm" },
	Boots = { "LeftFoot", "RightFoot", "Left Leg", "Right Leg" },
}

------------------------------------------------------------
-- 능력치 계산
------------------------------------------------------------
local function recompute(player)
	local totals = { Health = 0, Crit = 0, Speed = 0 }
	for _, slot in ipairs(G.Slots) do
		local rarity = player:GetAttribute(rAttr(slot.Key)) or 0
		local level = player:GetAttribute(lAttr(slot.Key)) or 0
		totals[slot.Stat] += Config.GetGearStat(slot.Key, rarity, level)
	end
	player:SetAttribute("GearHealth", math.floor(totals.Health + 0.5))
	player:SetAttribute("GearCrit", totals.Crit)
	player:SetAttribute("GearSpeed", totals.Speed)
end

------------------------------------------------------------
-- 캐릭터 외형: 등급 색 / 재질의 갑옷 조각을 신체 부위에 씌운다
------------------------------------------------------------
function Gear.ApplyVisuals(player)
	local character = player.Character
	if not character then return end

	for _, slot in ipairs(G.Slots) do
		local rarity = player:GetAttribute(rAttr(slot.Key)) or 0
		for _, limbName in ipairs(LIMBS[slot.Key]) do
			local limb = character:FindFirstChild(limbName)
			if limb then
				local old = limb:FindFirstChild("GearVisual_" .. slot.Key)
				if old then
					old:Destroy()
				end

				if rarity > 0 then
					local color = G.RarityColors[rarity]
					local shell = Instance.new("Part")
					shell.Name = "GearVisual_" .. slot.Key
					shell.Size = limb.Size * 1.12 + Vector3.new(0.04, 0.04, 0.04)
					shell.CFrame = limb.CFrame
					shell.Color = color
					shell.Material = G.RarityMaterials[rarity]
					shell.CanCollide = false
					shell.CanQuery = false
					shell.CanTouch = false
					shell.Massless = true

					local weld = Instance.new("WeldConstraint")
					weld.Part0 = limb
					weld.Part1 = shell
					weld.Parent = shell
					shell.Parent = limb

					if rarity >= 4 then
						local sparkle = Instance.new("ParticleEmitter")
						sparkle.Rate = rarity == 5 and 14 or 7
						sparkle.Lifetime = NumberRange.new(0.5, 1)
						sparkle.Speed = NumberRange.new(0.5, 2)
						sparkle.SpreadAngle = Vector2.new(180, 180)
						sparkle.LightEmission = 1
						sparkle.Color = ColorSequence.new(color)
						sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
						sparkle.Parent = shell
					end
				end
			end
		end
	end
end

------------------------------------------------------------
-- 불러오기 / 저장용 / 변경 감시
------------------------------------------------------------
-- saved = { Armor = { R = 등급, L = 강화 }, Gloves = ..., Boots = ... } (없으면 전부 빈 칸)
function Gear.Load(player, saved)
	for _, slot in ipairs(G.Slots) do
		local entry = saved and saved[slot.Key]
		local rarity = entry and math.clamp(math.floor(tonumber(entry.R) or 0), 0, #G.RarityNames) or 0
		local level = entry and math.clamp(math.floor(tonumber(entry.L) or 0), 0, G.MaxLevel) or 0
		player:SetAttribute(rAttr(slot.Key), rarity)
		player:SetAttribute(lAttr(slot.Key), level)
	end
	recompute(player)
end

-- 장비 Attribute 가 바뀌면 능력치를 다시 계산하고 외형을 갱신
function Gear.Watch(player)
	local queued = false
	player.AttributeChanged:Connect(function(name)
		if string.sub(name, 1, 5) ~= "Gear_" then return end
		recompute(player)
		if queued then return end
		queued = true
		task.defer(function()
			queued = false
			Gear.ApplyVisuals(player)
		end)
	end)
end

------------------------------------------------------------
-- 강화: 골드를 내고 확률적으로 +1. 실패해도 레벨은 유지.
-- 반환: ok, message
------------------------------------------------------------
function Gear.Enhance(player, slotKey)
	if player:GetAttribute("Zone") ~= "Lobby" then
		return false, "장비 강화는 로비에서만 할 수 있어요."
	end
	local slot = Config.GetGearSlot(slotKey)
	if not slot then
		return false, "알 수 없는 부위예요."
	end

	local rarity = player:GetAttribute(rAttr(slotKey)) or 0
	if rarity <= 0 then
		return false, slot.Name .. " 장비가 없어요. 먼저 뽑기로 얻어주세요."
	end

	local level = player:GetAttribute(lAttr(slotKey)) or 0
	if level >= G.MaxLevel then
		return false, "이미 최대 강화 단계예요!"
	end

	local cost = Config.GetGearCost(slotKey, rarity, level)
	local gold = player:GetAttribute("Gold") or 0
	if gold < cost then
		return false, string.format("골드가 부족해요. (%d 필요)", cost)
	end
	player:SetAttribute("Gold", gold - cost)

	if math.random() < Config.GetGearEnhanceChance(level) then
		player:SetAttribute(lAttr(slotKey), level + 1)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			Effects.Burst(root.Position, G.RarityColors[rarity], 30)
		end
		return true, string.format("%s 강화 성공! +%d", slot.Name, level + 1)
	end
	return false, "강화 실패... (골드만 사라졌어요)"
end

------------------------------------------------------------
-- 뽑기: 티켓 1장 -> 무작위 부위 + 무작위 등급.
--   현재 장비보다 등급이 높으면 교체 (강화 레벨은 그대로 이어받음)
--   같거나 낮으면 골드로 교환
-- 반환: ok, message, roll = { Slot, Rarity, Equipped, Gold }
------------------------------------------------------------
function Gear.Roll(player)
	if player:GetAttribute("Zone") ~= "Lobby" then
		return false, "뽑기는 로비에서만 할 수 있어요."
	end
	local tickets = player:GetAttribute("Tickets") or 0
	if tickets < 1 then
		return false, "티켓이 없어요. 보스를 잡으면 얻을 수 있어요!"
	end
	player:SetAttribute("Tickets", tickets - 1)

	local roll = math.random() * 100
	local rarity = 1
	local acc = 0
	for index, rate in ipairs(Config.Gacha.Rates) do
		acc += rate
		if roll < acc then
			rarity = index
			break
		end
	end

	local slot = G.Slots[math.random(#G.Slots)]
	local current = player:GetAttribute(rAttr(slot.Key)) or 0
	local itemName = slot.Names[rarity]
	local rarityName = G.RarityNames[rarity]

	local result = { Slot = slot.Key, Rarity = rarity, Equipped = false, Gold = 0 }
	local message
	if rarity > current then
		player:SetAttribute(rAttr(slot.Key), rarity)
		result.Equipped = true
		message = string.format("[%s] %s 획득! 장착했어요.", rarityName, itemName)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			Effects.Burst(root.Position, G.RarityColors[rarity], 20 + rarity * 12)
		end
	else
		local gold = Config.Gacha.DuplicateGold[rarity]
		player:SetAttribute("Gold", (player:GetAttribute("Gold") or 0) + gold)
		result.Gold = gold
		message = string.format("[%s] %s... 이미 더 좋은 장비가 있어 +%d G 로 교환!", rarityName, itemName, gold)
	end
	return true, message, result
end

return Gear
