-- GearService (ServerScriptService > Modules 안의 ModuleScript, 이름: GearService)
-- 방어구(갑옷 / 장갑 / 신발): 보스 티켓으로 뽑기 -> 골드로 강화 -> 능력치 + 캐릭터 외형 반영.
--   갑옷: 최대 체력 / 장갑: 치명타 확률 / 신발: 이동 속도
-- 부위별 장비는 플레이어 Attribute 에 들어 있다 (등급 Gear_<부위>_R, 강화 Gear_<부위>_L). 0이면 비어 있음.
-- 합산 효과는 GearHealth / GearCrit / GearSpeed Attribute 로 계산되어 다른 시스템이 읽어 쓴다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Effects = require(script.Parent:WaitForChild("Effects"))
local Quest = require(script.Parent:WaitForChild("QuestService"))
local Inventory = require(script.Parent:WaitForChild("InventoryService"))

local G = Config.Gear

local Gear = {}

local function rAttr(key) return "Gear_" .. key .. "_R" end
local function lAttr(key) return "Gear_" .. key .. "_L" end

------------------------------------------------------------
-- 능력치 계산
------------------------------------------------------------
local function recompute(player)
	local totals = { Health = 0, Crit = 0, Speed = 0, Damage = 0, Haste = 0, Luck = 0 }
	for _, slot in ipairs(G.Slots) do
		local rarity = player:GetAttribute(rAttr(slot.Key)) or 0
		local level = player:GetAttribute(lAttr(slot.Key)) or 0
		totals[slot.Stat] += Config.GetGearStat(slot.Key, rarity, level)
	end

	-- 장착한 아이템의 랜덤 옵션 (체력 / 치명타 / 속도 / 공격력 / 경험치 / 행운)
	local affix = Inventory.GetTotals(player)
	player:SetAttribute("GearHealth", math.floor(totals.Health + affix.Health + 0.5))
	player:SetAttribute("GearCrit", totals.Crit + affix.Crit)
	player:SetAttribute("GearSpeed", totals.Speed + affix.Speed)
	player:SetAttribute("GearDamage", affix.Damage + totals.Damage)
	player:SetAttribute("GearXp", affix.Xp)
	player:SetAttribute("GearLuck", affix.Luck + totals.Luck)
	player:SetAttribute("GearHaste", math.min(0.6, affix.Haste + totals.Haste))
	player:SetAttribute("GearShot", math.floor(affix.Shot + 0.5))
end

------------------------------------------------------------
-- 캐릭터 외형: 부위마다 모양이 다른 장식을 몸에 붙인다 (R15 / R6 모두)
--   투구: 머리띠 + 윗판 + (뿔 / 볏 / 보석 / 후광)   갑옷: 가슴판 + 어깨 갑옷 + 허리띠 + (망토)
--   장갑: 건틀릿 + 손목 띠 + (징)   신발: 부츠 + 정강이 보호대 + (날개)   반지: 손가락 반지 + 보석   목걸이: 사슬 + 펜던트
-- 등급이 오를수록 장식이 늘어나고 빛난다. 부위별 Folder "GearVisual_<부위>" 에 모아 두었다가 다시 만들 때 통째로 지운다.
------------------------------------------------------------
local function firstOf(character, ...)
	for _, name in ipairs({ ... }) do
		local found = character:FindFirstChild(name)
		if found then return found end
	end
	return nil
end

local function attach(folder, limb, spec)
	local part = Instance.new("Part")
	part.Name = "Gear"
	part.Size = spec.Size
	part.Color = spec.Color
	part.Material = spec.Material or Enum.Material.Metal
	part.Transparency = spec.Transparency or 0
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	if spec.Shape then part.Shape = spec.Shape end
	part.CFrame = limb.CFrame * (spec.Offset or CFrame.new())
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = limb
	weld.Part1 = part
	weld.Parent = part
	part.Parent = folder
	return part
end

local CYL = CFrame.Angles(0, 0, math.rad(90)) -- 원기둥을 세운다 (Roblox 원기둥은 X 축이 길이)

local builders = {}

builders.Helmet = function(character, folder, r, color, material)
	local head = character:FindFirstChild("Head")
	if not head then return end
	local hs = head.Size
	local dark = color:Lerp(Color3.fromRGB(30, 30, 40), 0.55)
	-- 머리띠 + 윗판
	attach(folder, head, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.38, hs.X * 1.18, hs.Z * 1.18), Offset = CFrame.new(0, hs.Y * 0.3, 0) * CYL, Color = color, Material = material })
	attach(folder, head, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, hs.X * 1.1, hs.Z * 1.1), Offset = CFrame.new(0, hs.Y * 0.58, 0) * CYL, Color = dark, Material = material })
	if r >= 2 then -- 양옆 뿔 (등급이 오르면 커진다)
		local horn = 0.6 + r * 0.25
		for _, side in ipairs({ -1, 1 }) do
			attach(folder, head, { Size = Vector3.new(0.25, horn, 0.25), Offset = CFrame.new(side * hs.X * 0.62, hs.Y * 0.5 + horn * 0.3, 0) * CFrame.Angles(0, 0, math.rad(side * -28)), Color = color, Material = material })
		end
	end
	if r >= 3 then -- 앞뒤로 달리는 볏
		attach(folder, head, { Size = Vector3.new(0.18, 0.7 + r * 0.12, hs.Z * 1.25), Offset = CFrame.new(0, hs.Y * 0.8, 0), Color = color, Material = Enum.Material.Neon })
	end
	if r >= 4 then -- 이마 보석
		attach(folder, head, { Shape = Enum.PartType.Ball, Size = Vector3.new(0.34, 0.34, 0.34), Offset = CFrame.new(0, hs.Y * 0.36, -hs.Z * 0.62), Color = color, Material = Enum.Material.Neon })
	end
	if r >= 5 then -- 후광
		attach(folder, head, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, hs.X * 1.9, hs.Z * 1.9), Offset = CFrame.new(0, hs.Y * 1.5, 0) * CYL, Color = color, Material = Enum.Material.Neon, Transparency = 0.15 })
	end
end

builders.Armor = function(character, folder, r, color, material)
	local torso = firstOf(character, "UpperTorso", "Torso")
	if not torso then return end
	local ts = torso.Size
	local dark = color:Lerp(Color3.fromRGB(30, 30, 40), 0.5)
	-- 가슴판 (몸통보다 살짝 크고, 위쪽이 넓다) + 중앙 보석
	attach(folder, torso, { Size = Vector3.new(ts.X * 1.12, ts.Y * 0.82, ts.Z * 1.18), Offset = CFrame.new(0, ts.Y * 0.06, 0), Color = color, Material = material })
	attach(folder, torso, { Size = Vector3.new(ts.X * 1.16, 0.22, ts.Z * 1.22), Offset = CFrame.new(0, -ts.Y * 0.42, 0), Color = dark, Material = Enum.Material.Metal }) -- 허리띠
	attach(folder, torso, { Shape = Enum.PartType.Ball, Size = Vector3.new(0.42, 0.42, 0.2), Offset = CFrame.new(0, ts.Y * 0.14, -ts.Z * 0.62), Color = color, Material = Enum.Material.Neon })
	if r >= 2 then -- 어깨 갑옷
		for _, name in ipairs({ { "LeftUpperArm", "Left Arm" }, { "RightUpperArm", "Right Arm" } }) do
			local arm = firstOf(character, name[1], name[2])
			if arm then
				attach(folder, arm, { Shape = Enum.PartType.Ball, Size = Vector3.new(arm.Size.X * 1.3, arm.Size.X * 0.95, arm.Size.X * 1.3), Offset = CFrame.new(0, arm.Size.Y * 0.4, 0), Color = color, Material = material })
				if r >= 3 then -- 어깨 가시
					attach(folder, arm, { Size = Vector3.new(0.22, 0.6 + r * 0.12, 0.22), Offset = CFrame.new(0, arm.Size.Y * 0.4 + 0.65, 0), Color = color, Material = Enum.Material.Neon })
				end
			end
		end
	end
	if r >= 4 then -- 망토
		attach(folder, torso, { Size = Vector3.new(ts.X * 1.05, ts.Y * 1.7, 0.14), Offset = CFrame.new(0, -ts.Y * 0.55, ts.Z * 0.66) * CFrame.Angles(math.rad(8), 0, 0), Color = dark, Material = Enum.Material.Fabric })
		attach(folder, torso, { Size = Vector3.new(ts.X * 1.05, 0.18, 0.18), Offset = CFrame.new(0, ts.Y * 0.32, ts.Z * 0.64), Color = color, Material = Enum.Material.Neon })
	end
end

builders.Gloves = function(character, folder, r, color, material)
	local dark = color:Lerp(Color3.fromRGB(30, 30, 40), 0.5)
	for _, names in ipairs({ { "LeftHand", "Left Arm" }, { "RightHand", "Right Arm" } }) do
		local hand = firstOf(character, names[1], names[2])
		if hand then
			local hs = hand.Size
			local drop = hand.Name:find("Arm") and -hs.Y * 0.32 or 0 -- R6 는 팔 아래쪽이 손
			attach(folder, hand, { Size = Vector3.new(hs.X * 1.18, math.min(hs.Y, 1.1) * 1.05, hs.Z * 1.18), Offset = CFrame.new(0, drop, 0), Color = color, Material = material })
			attach(folder, hand, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, hs.X * 1.45, hs.Z * 1.45), Offset = CFrame.new(0, drop + 0.5, 0) * CYL, Color = dark, Material = Enum.Material.Metal })
			if r >= 3 then -- 손등 징
				for i = -1, 1 do
					attach(folder, hand, { Shape = Enum.PartType.Ball, Size = Vector3.new(0.2, 0.2, 0.2), Offset = CFrame.new(i * hs.X * 0.3, drop - 0.1, -hs.Z * 0.6), Color = color, Material = Enum.Material.Neon })
				end
			end
		end
	end
end

builders.Boots = function(character, folder, r, color, material)
	local dark = color:Lerp(Color3.fromRGB(30, 30, 40), 0.5)
	for _, names in ipairs({ { "LeftFoot", "Left Leg", "LeftLowerLeg" }, { "RightFoot", "Right Leg", "RightLowerLeg" } }) do
		local foot = firstOf(character, names[1], names[2])
		if foot then
			local fs = foot.Size
			local drop = foot.Name:find("Leg") and -fs.Y * 0.36 or 0 -- R6 는 다리 아래쪽이 발
			attach(folder, foot, { Size = Vector3.new(fs.X * 1.18, math.min(fs.Y, 1) * 1.1, fs.Z * 1.22), Offset = CFrame.new(0, drop, -0.04), Color = color, Material = material })
			attach(folder, foot, { Size = Vector3.new(fs.X * 1.1, 0.16, fs.Z * 1.26), Offset = CFrame.new(0, drop - 0.42, -0.04), Color = dark, Material = Enum.Material.Metal }) -- 밑창
			if r >= 2 then -- 정강이 보호대 (R15 만)
				local shin = character:FindFirstChild(names[3])
				if shin and shin ~= foot then
					attach(folder, shin, { Size = Vector3.new(shin.Size.X * 1.14, shin.Size.Y * 0.62, shin.Size.Z * 1.14), Offset = CFrame.new(0, -shin.Size.Y * 0.1, 0), Color = color, Material = material })
				end
			end
			if r >= 4 then -- 발목 날개
				for _, side in ipairs({ -1, 1 }) do
					attach(folder, foot, { Size = Vector3.new(0.1, 0.9, 0.5), Offset = CFrame.new(side * fs.X * 0.62, drop + 0.5, 0.25) * CFrame.Angles(math.rad(-25), 0, math.rad(side * 24)), Color = color, Material = Enum.Material.Neon })
				end
			end
		end
	end
end

builders.Ring = function(character, folder, r, color, material)
	local hand = firstOf(character, "RightHand", "Right Arm")
	if not hand then return end
	local hs = hand.Size
	local drop = hand.Name:find("Arm") and -hs.Y * 0.3 or 0
	attach(folder, hand, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.16, hs.X * 1.28, hs.Z * 1.28), Offset = CFrame.new(0, drop - 0.12, 0) * CYL, Color = color, Material = Enum.Material.Metal })
	attach(folder, hand, { Shape = Enum.PartType.Ball, Size = Vector3.new(0.34, 0.34, 0.34) * (0.8 + r * 0.12), Offset = CFrame.new(hs.X * 0.66, drop - 0.12, 0), Color = color, Material = Enum.Material.Neon })
end

builders.Necklace = function(character, folder, r, color, material)
	local torso = firstOf(character, "UpperTorso", "Torso")
	if not torso then return end
	local ts = torso.Size
	attach(folder, torso, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.14, ts.X * 0.92, ts.Z * 1.12), Offset = CFrame.new(0, ts.Y * 0.4, 0) * CYL, Color = color, Material = Enum.Material.Metal })
	attach(folder, torso, { Shape = Enum.PartType.Ball, Size = Vector3.new(0.46, 0.5, 0.3) * (0.8 + r * 0.1), Offset = CFrame.new(0, ts.Y * 0.18, -ts.Z * 0.62), Color = color, Material = Enum.Material.Neon })
end

function Gear.ApplyVisuals(player)
	local character = player.Character
	if not character then return end

	for _, slot in ipairs(G.Slots) do
		local old = character:FindFirstChild("GearVisual_" .. slot.Key)
		if old then
			old:Destroy()
		end

		local rarity = player:GetAttribute(rAttr(slot.Key)) or 0
		local build = builders[slot.Key]
		if rarity > 0 and build then
			local color = G.RarityColors[rarity]
			local folder = Instance.new("Folder")
			folder.Name = "GearVisual_" .. slot.Key
			folder.Parent = character
			-- 큰 부품까지 Neon 이면 번쩍이는 덩어리처럼 보이니, 본체는 금속으로 하고 빛나는 건 작은 장식(보석 / 띠)만 Neon 으로 쓴다
			local material = G.RarityMaterials[rarity]
			if material == Enum.Material.Neon then
				material = Enum.Material.Metal
			end
			build(character, folder, rarity, color, material)

			if rarity >= 4 then -- 전설 이상: 반짝이는 입자
				local first = folder:FindFirstChildWhichIsA("BasePart")
				if first then
					local sparkle = Instance.new("ParticleEmitter")
					sparkle.Rate = rarity == 5 and 14 or 7
					sparkle.Lifetime = NumberRange.new(0.5, 1)
					sparkle.Speed = NumberRange.new(0.5, 2)
					sparkle.SpreadAngle = Vector2.new(180, 180)
					sparkle.LightEmission = 1
					sparkle.Color = ColorSequence.new(color)
					sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
					sparkle.Parent = first
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

	local equipped = Inventory.GetEquipped(player, slotKey)
	if not equipped then
		return false, slot.Name .. " 장비가 없어요. 필드에서 얻거나 뽑기로 얻어주세요."
	end
	local rarity = equipped.Rarity

	local level = equipped.Level
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
		Inventory.SetLevel(player, slotKey, level + 1) -- 아이템의 강화 레벨 + 능력치 / 외형 갱신
		Quest.Add(player, "Enhances", 1)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			Effects.Burst(root.Position, G.RarityColors[rarity], 30)
			Effects.PlaySound(root, Config.Audio.EnhanceSuccess, 0.8, 1)
		end
		return true, string.format("%s 강화 성공! +%d", slot.Name, level + 1)
	end
	return false, "강화 실패... (골드만 사라졌어요)"
end

------------------------------------------------------------
-- 뽑기: 티켓 1장 -> 무작위 부위 + 무작위 등급의 장비 아이템(랜덤 옵션 포함)
--   빈 부위면 바로 장착, 아니면 가방에 들어간다 (자동 분해 설정이면 분해)
-- 반환: ok, message, roll = { Slot, Rarity, Equipped, Status, Gold }
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
	Quest.Add(player, "Rolls", 1)

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
	local item = Inventory.NewItem(slot.Key, rarity, 0)
	local status, _, essence, gold = Inventory.Add(player, item)

	local name = string.format("[%s] %s", G.RarityNames[rarity], slot.Names[rarity])
	local message
	if status == "Equipped" then
		message = name .. " 획득! 장착했어요."
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			Effects.Burst(root.Position, G.RarityColors[rarity], 20 + rarity * 12)
		end
	elseif status == "Bag" then
		message = name .. " 획득! 가방에 넣었어요. (I → 가방에서 장착)"
	else
		message = string.format("%s... 자동 분해! 에센스 +%d, %d G", name, essence or 0, gold or 0)
	end
	return true, message, { Slot = slot.Key, Rarity = rarity, Name = slot.Names[rarity], Equipped = status == "Equipped", Status = status, Gold = gold or 0 }
end

return Gear
