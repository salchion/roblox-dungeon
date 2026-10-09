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
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

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

	-- 세트 효과: 구역 세트를 2부위 맞추면 1단계, 3부위면 3단계 (미사일 / 번개 / 칼날 / 폭발 ...). 필드 / 던전 / 심연 어디서나 작동한다.
	local augLevels, bestLevel, auraColor = {}, 0, nil
	for setKey, count in pairs(affix.SetCounts or {}) do
		local def = Config.Sets[setKey]
		if def and def.Aug then
			local level = count >= 3 and Config.Sets.AugLevelByPieces[3] or (count >= 2 and Config.Sets.AugLevelByPieces[2] or 0)
			if level > 0 then
				augLevels[def.Aug] = level
				if level > bestLevel then bestLevel, auraColor = level, Config.AugInfo[def.Aug].Color end
			end
		end
	end
	for attr in pairs(Config.AugInfo) do
		player:SetAttribute(attr, augLevels[attr] or 0)
	end
	for _, synKey in ipairs(Config.AugSynergies.Order) do
		local syn = Config.AugSynergies[synKey]
		local active = true
		for _, need in ipairs(syn.Need) do
			if (augLevels[need] or 0) <= 0 then active = false end
		end
		local before = player:GetAttribute("AugSyn_" .. synKey)
		player:SetAttribute("AugSyn_" .. synKey, active)
		if active and before == false then -- 방금 새로 켜졌다 (접속 직후 첫 계산은 알리지 않는다)
			Remotes.Notify:FireClient(player, string.format("%s 세트 시너지 발동! 『%s』 — %s", syn.Icon, syn.Name, syn.Desc))
		end
	end
	player:SetAttribute("AugAuraColor", auraColor)
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
	-- 네모난 느낌을 줄이기 위해 각진 판은 모서리가 둥근 모양(Head 메시)으로 만든다. 얇은 날 / 띠는 그대로 둔다.
	if not spec.Shape and spec.Round ~= false and math.min(spec.Size.X, spec.Size.Y, spec.Size.Z) >= 0.5 then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Head
		mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
		mesh.Parent = part
	end
	part.CFrame = limb.CFrame * (spec.Offset or CFrame.new())
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = limb
	weld.Part1 = part
	weld.Parent = part
	part.Parent = folder
	return part
end

local CYL = CFrame.Angles(0, 0, math.rad(90)) -- 원기둥을 세운다 (Roblox 원기둥은 X 축이 길이)
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end

-- 등급(= 아이템 이름 단계)마다 소재 / 색이 다르다: main = 본체 색, trim = 장식 색, mat = 재질
local TIERS = {
	Armor = {
		{ main = rgb(150, 105, 65), trim = rgb(95, 62, 38), mat = Enum.Material.Leather },        -- 가죽
		{ main = rgb(168, 172, 182), trim = rgb(105, 110, 122), mat = Enum.Material.Metal },     -- 사슬
		{ main = rgb(196, 202, 214), trim = rgb(70, 105, 175), mat = Enum.Material.Metal },      -- 강철
		{ main = rgb(130, 220, 230), trim = rgb(235, 250, 255), mat = Enum.Material.Foil },      -- 미스릴
		{ main = rgb(150, 30, 40), trim = rgb(255, 200, 70), mat = Enum.Material.DiamondPlate }, -- 용린
	},
	Helmet = {
		{ main = rgb(150, 105, 65), trim = rgb(220, 70, 60), mat = Enum.Material.Leather },
		{ main = rgb(150, 154, 165), trim = rgb(95, 100, 112), mat = Enum.Material.Metal },
		{ main = rgb(196, 202, 214), trim = rgb(70, 105, 175), mat = Enum.Material.Metal },
		{ main = rgb(130, 220, 230), trim = rgb(235, 250, 255), mat = Enum.Material.Foil },
		{ main = rgb(60, 25, 35), trim = rgb(255, 200, 70), mat = Enum.Material.DiamondPlate },
	},
	Gloves = {
		{ main = rgb(225, 220, 205), trim = rgb(150, 140, 120), mat = Enum.Material.Fabric },
		{ main = rgb(150, 105, 65), trim = rgb(95, 62, 38), mat = Enum.Material.Leather },
		{ main = rgb(196, 202, 214), trim = rgb(70, 105, 175), mat = Enum.Material.Metal },
		{ main = rgb(130, 220, 230), trim = rgb(235, 250, 255), mat = Enum.Material.Foil },
		{ main = rgb(60, 25, 35), trim = rgb(255, 200, 70), mat = Enum.Material.DiamondPlate },
	},
	Boots = {
		{ main = rgb(120, 100, 80), trim = rgb(80, 65, 50), mat = Enum.Material.Fabric },
		{ main = rgb(150, 105, 65), trim = rgb(95, 62, 38), mat = Enum.Material.Leather },
		{ main = rgb(196, 202, 214), trim = rgb(70, 105, 175), mat = Enum.Material.Metal },
		{ main = rgb(130, 220, 230), trim = rgb(235, 250, 255), mat = Enum.Material.Foil },
		{ main = rgb(235, 245, 250), trim = rgb(110, 230, 255), mat = Enum.Material.SmoothPlastic },
	},
	Ring = {
		{ main = rgb(184, 115, 51), trim = rgb(220, 150, 80), mat = Enum.Material.Metal },
		{ main = rgb(205, 210, 220), trim = rgb(235, 240, 250), mat = Enum.Material.Metal },
		{ main = rgb(255, 205, 70), trim = rgb(255, 235, 150), mat = Enum.Material.Metal },
		{ main = rgb(255, 205, 70), trim = rgb(90, 220, 255), mat = Enum.Material.Metal },
		{ main = rgb(255, 215, 90), trim = rgb(200, 120, 255), mat = Enum.Material.Metal },
	},
	Necklace = {
		{ main = rgb(120, 85, 55), trim = rgb(200, 190, 170), mat = Enum.Material.Fabric },
		{ main = rgb(205, 210, 220), trim = rgb(240, 245, 255), mat = Enum.Material.Metal },
		{ main = rgb(255, 205, 70), trim = rgb(255, 235, 150), mat = Enum.Material.Metal },
		{ main = rgb(255, 205, 70), trim = rgb(255, 90, 130), mat = Enum.Material.Metal },
		{ main = rgb(255, 215, 90), trim = rgb(255, 240, 150), mat = Enum.Material.Metal },
	},
}

local builders = {}

-- 투구: 1 가죽 모자(깃털) / 2 철 투구(코 보호대) / 3 강철 투구(볼 보호대 + 볏) / 4 미스릴(날개 + 보석) / 5 용뿔 왕관(왕관 + 큰 뿔 + 후광)
builders.Helmet = function(character, folder, tier, glow, t)
	local head = character:FindFirstChild("Head")
	if not head then return end
	local hs = head.Size
	local function band(h, scale, y, color, mat) -- 머리를 두르는 원판
		attach(folder, head, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, hs.X * scale, hs.Z * scale), Offset = CFrame.new(0, y, 0) * CYL, Color = color, Material = mat })
	end
	band(0.36, 1.16, hs.Y * 0.3, t.main, t.mat)
	band(0.3, 1.08, hs.Y * 0.58, t.main, t.mat)
	if tier == 1 then
		attach(folder, head, { Size = Vector3.new(0.1, 0.9, 0.3), Offset = CFrame.new(hs.X * 0.55, hs.Y * 0.8, hs.Z * 0.2) * CFrame.Angles(math.rad(-10), 0, math.rad(-25)), Color = t.trim, Material = Enum.Material.Fabric }) -- 깃털
	elseif tier == 2 then
		attach(folder, head, { Size = Vector3.new(0.16, hs.Y * 0.65, 0.12), Offset = CFrame.new(0, hs.Y * 0.1, -hs.Z * 0.6), Color = t.main, Material = t.mat }) -- 코 보호대
	elseif tier == 3 then
		for _, side in ipairs({ -1, 1 }) do
			attach(folder, head, { Size = Vector3.new(0.14, hs.Y * 0.75, hs.Z * 0.75), Offset = CFrame.new(side * hs.X * 0.58, hs.Y * 0.05, -hs.Z * 0.05), Color = t.main, Material = t.mat }) -- 볼 보호대
		end
		attach(folder, head, { Size = Vector3.new(0.16, 0.45, hs.Z * 1.1), Offset = CFrame.new(0, hs.Y * 0.85, 0), Color = t.trim, Material = t.mat }) -- 낮은 볏
	elseif tier == 4 then
		for _, side in ipairs({ -1, 1 }) do
			attach(folder, head, { Size = Vector3.new(0.08, 0.5, 1.3), Offset = CFrame.new(side * hs.X * 0.62, hs.Y * 0.55, 0.1) * CFrame.Angles(math.rad(-15), 0, math.rad(side * -28)), Color = t.trim, Material = Enum.Material.Neon, Transparency = 0.2 }) -- 날개
		end
		attach(folder, head, { Shape = Enum.PartType.Ball, Size = Vector3.new(0.3, 0.3, 0.3), Offset = CFrame.new(0, hs.Y * 0.4, -hs.Z * 0.62), Color = glow, Material = Enum.Material.Neon })
	else
		for i = 0, 6 do -- 왕관 가시
			local angle = i / 7 * math.pi * 2
			attach(folder, head, { Size = Vector3.new(0.16, 0.7, 0.16), Offset = CFrame.new(math.cos(angle) * hs.X * 0.5, hs.Y * 0.95, math.sin(angle) * hs.Z * 0.5), Color = t.trim, Material = Enum.Material.Neon })
		end
		for _, side in ipairs({ -1, 1 }) do -- 큰 뿔
			attach(folder, head, { Size = Vector3.new(0.3, 1.5, 0.3), Offset = CFrame.new(side * hs.X * 0.7, hs.Y * 0.75, 0.1) * CFrame.Angles(0, 0, math.rad(side * -35)), Color = rgb(235, 225, 205), Material = Enum.Material.SmoothPlastic })
		end
		attach(folder, head, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, hs.X * 1.9, hs.Z * 1.9), Offset = CFrame.new(0, hs.Y * 1.7, 0) * CYL, Color = glow, Material = Enum.Material.Neon, Transparency = 0.2 })
	end
end

-- 갑옷: 1 가죽 조끼(가슴 끈) / 2 사슬(소매 + 치마) / 3 강철(어깨판 + 앞치마) / 4 미스릴(날개 어깨 + 빛 줄무늬 + 망토) / 5 용린(뿔 어깨 + 등 가시 + 찢어진 망토)
builders.Armor = function(character, folder, tier, glow, t)
	local torso = firstOf(character, "UpperTorso", "Torso")
	if not torso then return end
	local ts = torso.Size
	local arms = {}
	for _, name in ipairs({ { "LeftUpperArm", "Left Arm", -1 }, { "RightUpperArm", "Right Arm", 1 } }) do
		local arm = firstOf(character, name[1], name[2])
		if arm then table.insert(arms, { Limb = arm, Side = name[3] }) end
	end
	attach(folder, torso, { Size = Vector3.new(ts.X * 1.1, ts.Y * 0.82, ts.Z * 1.16), Offset = CFrame.new(0, ts.Y * 0.06, 0), Color = t.main, Material = t.mat })
	attach(folder, torso, { Size = Vector3.new(ts.X * 1.14, 0.22, ts.Z * 1.2), Offset = CFrame.new(0, -ts.Y * 0.42, 0), Color = t.trim, Material = Enum.Material.Metal }) -- 허리띠
	attach(folder, torso, { Size = Vector3.new(0.32, 0.32, 0.12), Offset = CFrame.new(0, -ts.Y * 0.42, -ts.Z * 0.62), Color = tier >= 3 and glow or t.trim, Material = tier >= 4 and Enum.Material.Neon or Enum.Material.Metal }) -- 버클
	-- 둥근 어깨 갑옷 / 목 칼라 / 가슴 문장: 네모난 상자처럼 보이지 않게 곡선 장식을 더한다
	if tier >= 2 then
		for _, a in ipairs(arms) do
			local w = a.Limb.Size.X
			attach(folder, a.Limb, { Shape = Enum.PartType.Ball, Size = Vector3.new(w * 1.45, w * 1.2, w * 1.45), Offset = CFrame.new(a.Side * 0.04, a.Limb.Size.Y * 0.38, 0), Color = t.main, Material = t.mat })
			attach(folder, a.Limb, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.16, w * 1.3, w * 1.3), Offset = CFrame.new(0, a.Limb.Size.Y * 0.1, 0) * CYL, Color = t.trim, Material = Enum.Material.Metal })
		end
		attach(folder, torso, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, ts.X * 0.7, ts.Z * 1.0), Offset = CFrame.new(0, ts.Y * 0.46, 0) * CYL, Color = t.trim, Material = Enum.Material.Metal })
		attach(folder, torso, { Size = Vector3.new(0.5, 0.5, 0.12), Offset = CFrame.new(0, ts.Y * 0.14, -ts.Z * 0.64) * CFrame.Angles(0, 0, math.rad(45)), Color = tier >= 3 and glow or t.trim, Material = tier >= 3 and Enum.Material.Neon or Enum.Material.Metal })
		for _, side in ipairs({ -1, 1 }) do
			attach(folder, torso, { Size = Vector3.new(0.1, ts.Y * 0.8, ts.Z * 1.2), Offset = CFrame.new(side * ts.X * 0.55, ts.Y * 0.04, 0), Color = t.trim, Material = Enum.Material.Metal })
		end
	end
	if tier == 1 then
		for _, side in ipairs({ -1, 1 }) do -- X 자 가슴 끈
			attach(folder, torso, { Size = Vector3.new(0.18, ts.Y * 0.95, 0.1), Offset = CFrame.new(side * ts.X * 0.18, ts.Y * 0.05, -ts.Z * 0.6) * CFrame.Angles(0, 0, math.rad(side * 28)), Color = t.trim, Material = Enum.Material.Leather })
		end
	elseif tier == 2 then
		for _, a in ipairs(arms) do -- 사슬 소매
			attach(folder, a.Limb, { Size = Vector3.new(a.Limb.Size.X * 1.12, a.Limb.Size.Y * 0.55, a.Limb.Size.Z * 1.12), Offset = CFrame.new(0, a.Limb.Size.Y * 0.15, 0), Color = t.main, Material = t.mat })
		end
		attach(folder, torso, { Size = Vector3.new(ts.X * 1.12, ts.Y * 0.4, ts.Z * 1.2), Offset = CFrame.new(0, -ts.Y * 0.62, 0), Color = t.trim, Material = t.mat }) -- 치마
	elseif tier == 3 then
		for _, a in ipairs(arms) do -- 어깨판
			attach(folder, a.Limb, { Size = Vector3.new(a.Limb.Size.X * 1.5, 0.3, a.Limb.Size.Z * 1.5), Offset = CFrame.new(a.Side * 0.08, a.Limb.Size.Y * 0.42, 0) * CFrame.Angles(0, 0, math.rad(a.Side * -10)), Color = t.main, Material = t.mat })
		end
		attach(folder, torso, { Size = Vector3.new(ts.X * 0.6, ts.Y * 0.7, 0.1), Offset = CFrame.new(0, -ts.Y * 0.62, -ts.Z * 0.62), Color = t.trim, Material = Enum.Material.Fabric }) -- 앞치마
	elseif tier == 4 then
		for _, a in ipairs(arms) do -- 날개 어깨 (위로 솟은 칼날)
			attach(folder, a.Limb, { Size = Vector3.new(0.1, 1.5, 0.7), Offset = CFrame.new(a.Side * a.Limb.Size.X * 0.7, a.Limb.Size.Y * 0.55, 0.1) * CFrame.Angles(0, 0, math.rad(a.Side * -32)), Color = t.trim, Material = Enum.Material.Neon, Transparency = 0.15 })
		end
		for _, side in ipairs({ -1, 1 }) do -- 빛 줄무늬
			attach(folder, torso, { Size = Vector3.new(0.12, ts.Y * 0.75, 0.1), Offset = CFrame.new(side * ts.X * 0.3, ts.Y * 0.05, -ts.Z * 0.6), Color = glow, Material = Enum.Material.Neon })
		end
		attach(folder, torso, { Size = Vector3.new(ts.X * 1.0, ts.Y * 1.3, 0.12), Offset = CFrame.new(0, -ts.Y * 0.4, ts.Z * 0.64) * CFrame.Angles(math.rad(8), 0, 0), Color = t.main:Lerp(rgb(30, 40, 60), 0.5), Material = Enum.Material.Fabric })
	else
		for _, a in ipairs(arms) do -- 뿔 어깨 (두 갈래)
			for k = 0, 1 do
				attach(folder, a.Limb, { Size = Vector3.new(0.3, 1.2 + k * 0.4, 0.3), Offset = CFrame.new(a.Side * (a.Limb.Size.X * 0.55 + k * 0.25), a.Limb.Size.Y * 0.5, 0) * CFrame.Angles(0, 0, math.rad(a.Side * (-30 - k * 20))), Color = t.trim, Material = Enum.Material.Metal })
			end
		end
		for i = 0, 2 do -- 등 가시
			attach(folder, torso, { Size = Vector3.new(0.22, 0.6 - i * 0.1, 0.5 - i * 0.08), Offset = CFrame.new(0, ts.Y * (0.3 - i * 0.28), ts.Z * 0.66) * CFrame.Angles(math.rad(-20), 0, 0), Color = t.trim, Material = Enum.Material.Neon })
		end
		for i = -1, 1 do -- 찢어진 망토
			attach(folder, torso, { Size = Vector3.new(ts.X * 0.34, ts.Y * (1.5 - math.abs(i) * 0.35), 0.1), Offset = CFrame.new(i * ts.X * 0.36, -ts.Y * 0.45, ts.Z * 0.68) * CFrame.Angles(math.rad(10), 0, math.rad(i * 3)), Color = rgb(70, 15, 25), Material = Enum.Material.Fabric })
		end
		attach(folder, torso, { Shape = Enum.PartType.Ball, Size = Vector3.new(0.5, 0.5, 0.2), Offset = CFrame.new(0, ts.Y * 0.16, -ts.Z * 0.62), Color = glow, Material = Enum.Material.Neon })
	end
end

-- 장갑: 1 천 붕대 / 2 가죽 장갑(넓은 손목) / 3 강철 건틀릿(너클 + 판 손목) / 4 미스릴(팔날개) / 5 용발톱(발톱 + 가시)
builders.Gloves = function(character, folder, tier, glow, t)
	for _, names in ipairs({ { "LeftHand", "Left Arm", -1 }, { "RightHand", "Right Arm", 1 } }) do
		local hand = firstOf(character, names[1], names[2])
		if hand then
			local hs = hand.Size
			local side = names[3]
			local drop = hand.Name:find("Arm") and -hs.Y * 0.32 or 0
			local hh = math.min(hs.Y, 1.1)
			attach(folder, hand, { Size = Vector3.new(hs.X * (tier == 1 and 1.08 or 1.18), hh * 1.05, hs.Z * (tier == 1 and 1.08 or 1.18)), Offset = CFrame.new(0, drop, 0), Color = t.main, Material = t.mat })
			if tier == 1 then
				for i = 0, 2 do -- 붕대 감은 줄
					attach(folder, hand, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, hs.X * 1.3, hs.Z * 1.3), Offset = CFrame.new(0, drop + 0.5 + i * 0.18, 0) * CYL, Color = t.trim, Material = Enum.Material.Fabric })
				end
			elseif tier == 2 then
				attach(folder, hand, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, hs.X * 1.75, hs.Z * 1.75), Offset = CFrame.new(0, drop + 0.55, 0) * CYL, Color = t.trim, Material = Enum.Material.Leather }) -- 넓은 손목
			elseif tier == 3 then
				attach(folder, hand, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, hs.X * 1.6, hs.Z * 1.6), Offset = CFrame.new(0, drop + 0.55, 0) * CYL, Color = t.trim, Material = Enum.Material.Metal })
				attach(folder, hand, { Size = Vector3.new(hs.X * 1.1, 0.16, 0.2), Offset = CFrame.new(0, drop - 0.15, -hs.Z * 0.62), Color = t.main, Material = Enum.Material.Metal }) -- 너클 바
			elseif tier == 4 then
				attach(folder, hand, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, hs.X * 1.6, hs.Z * 1.6), Offset = CFrame.new(0, drop + 0.55, 0) * CYL, Color = t.trim, Material = Enum.Material.Metal })
				attach(folder, hand, { Size = Vector3.new(0.08, 1.2, 0.6), Offset = CFrame.new(side * hs.X * 0.7, drop + 0.9, 0.1) * CFrame.Angles(0, 0, math.rad(side * -18)), Color = glow, Material = Enum.Material.Neon, Transparency = 0.15 }) -- 팔날개
			else
				attach(folder, hand, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, hs.X * 1.7, hs.Z * 1.7), Offset = CFrame.new(0, drop + 0.55, 0) * CYL, Color = t.trim, Material = Enum.Material.Metal })
				for i = -1, 1 do -- 용발톱
					attach(folder, hand, { Size = Vector3.new(0.12, 0.12, 0.7), Offset = CFrame.new(i * hs.X * 0.3, drop - 0.1, -hs.Z * 0.9), Color = rgb(240, 230, 210), Material = Enum.Material.SmoothPlastic })
				end
				attach(folder, hand, { Size = Vector3.new(0.2, 0.5, 0.2), Offset = CFrame.new(side * hs.X * 0.65, drop + 0.6, 0) * CFrame.Angles(0, 0, math.rad(side * -35)), Color = glow, Material = Enum.Material.Neon }) -- 손목 가시
			end
		end
	end
end

-- 신발: 1 낡은 신발 / 2 가죽 장화(접힌 목) / 3 강철 부츠(정강이 + 앞코 판) / 4 미스릴(빛 밑창 + 발목 지느러미) / 5 바람의 부츠(날개 + 고리)
builders.Boots = function(character, folder, tier, glow, t)
	for _, names in ipairs({ { "LeftFoot", "Left Leg", "LeftLowerLeg" }, { "RightFoot", "Right Leg", "RightLowerLeg" } }) do
		local foot = firstOf(character, names[1], names[2])
		if foot then
			local fs = foot.Size
			local drop = foot.Name:find("Leg") and -fs.Y * 0.36 or 0
			local hh = math.min(fs.Y, 1)
			local shin = character:FindFirstChild(names[3])
			attach(folder, foot, { Size = Vector3.new(fs.X * 1.14, hh * (tier == 1 and 0.9 or 1.1), fs.Z * 1.2), Offset = CFrame.new(0, drop, -0.04), Color = t.main, Material = t.mat })
			attach(folder, foot, { Size = Vector3.new(fs.X * 1.1, 0.16, fs.Z * 1.24), Offset = CFrame.new(0, drop - hh * 0.5, -0.04), Color = t.trim, Material = Enum.Material.Metal }) -- 밑창
			if tier == 2 and shin and shin ~= foot then
				attach(folder, shin, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, shin.Size.X * 1.5, shin.Size.Z * 1.5), Offset = CFrame.new(0, -shin.Size.Y * 0.25, 0) * CYL, Color = t.trim, Material = Enum.Material.Leather }) -- 접힌 목
			elseif tier >= 3 then
				if shin and shin ~= foot then
					attach(folder, shin, { Size = Vector3.new(shin.Size.X * 1.14, shin.Size.Y * 0.65, shin.Size.Z * 1.14), Offset = CFrame.new(0, -shin.Size.Y * 0.1, 0), Color = t.main, Material = t.mat })
				end
				attach(folder, foot, { Size = Vector3.new(fs.X * 1.0, 0.22, fs.Z * 0.5), Offset = CFrame.new(0, drop + hh * 0.3, -fs.Z * 0.55), Color = t.trim, Material = Enum.Material.Metal }) -- 앞코 판
			end
			if tier == 4 then
				attach(folder, foot, { Size = Vector3.new(fs.X * 1.0, 0.08, fs.Z * 1.2), Offset = CFrame.new(0, drop - hh * 0.5 - 0.1, -0.04), Color = glow, Material = Enum.Material.Neon, Transparency = 0.2 })
				for _, side in ipairs({ -1, 1 }) do
					attach(folder, foot, { Size = Vector3.new(0.08, 0.7, 0.5), Offset = CFrame.new(side * fs.X * 0.62, drop + 0.4, 0.2) * CFrame.Angles(math.rad(-20), 0, math.rad(side * 22)), Color = t.trim, Material = Enum.Material.Neon, Transparency = 0.2 })
				end
			elseif tier == 5 then
				for _, side in ipairs({ -1, 1 }) do
					for k = 0, 2 do -- 깃털 날개
						attach(folder, foot, { Size = Vector3.new(0.06, 0.9 - k * 0.2, 0.3), Offset = CFrame.new(side * (fs.X * 0.6 + k * 0.18), drop + 0.5 + k * 0.12, 0.25) * CFrame.Angles(math.rad(-20), 0, math.rad(side * (24 + k * 12))), Color = t.main, Material = Enum.Material.Neon, Transparency = 0.1 })
					end
				end
				attach(folder, foot, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, fs.X * 1.5, fs.Z * 1.5), Offset = CFrame.new(0, drop + 0.55, 0) * CYL, Color = t.trim, Material = Enum.Material.Neon })
			end
		end
	end
end

-- 반지: 1 구리 / 2 은 / 3 금 / 4 보석 반지 / 5 시간의 반지(쌍 고리 + 빛나는 보석)
builders.Ring = function(character, folder, tier, glow, t)
	local hand = firstOf(character, "RightHand", "Right Arm")
	if not hand then return end
	local hs = hand.Size
	local drop = hand.Name:find("Arm") and -hs.Y * 0.3 or 0
	local function ring(y, scale)
		attach(folder, hand, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.14, hs.X * scale, hs.Z * scale), Offset = CFrame.new(0, drop + y, 0) * CYL, Color = t.main, Material = t.mat })
	end
	ring(-0.12, 1.28)
	if tier >= 3 then
		attach(folder, hand, { Size = Vector3.new(0.3, 0.1, 0.3), Offset = CFrame.new(hs.X * 0.66, drop - 0.12, 0), Color = t.trim, Material = Enum.Material.Metal }) -- 받침
	end
	if tier == 5 then
		ring(0.12, 1.4)
		attach(folder, hand, { Shape = Enum.PartType.Ball, Size = Vector3.new(0.55, 0.55, 0.55), Offset = CFrame.new(hs.X * 0.75, drop, 0), Color = t.trim, Material = Enum.Material.Neon })
		attach(folder, hand, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.05, 1.1, 1.1), Offset = CFrame.new(hs.X * 0.75, drop, 0) * CFrame.Angles(0, math.rad(90), 0), Color = glow, Material = Enum.Material.Neon, Transparency = 0.3 }) -- 시계 고리
	elseif tier >= 2 then
		attach(folder, hand, { Shape = Enum.PartType.Ball, Size = Vector3.new(0.18, 0.18, 0.18) * (tier == 4 and 2.2 or 1.4), Offset = CFrame.new(hs.X * 0.7, drop - 0.12, 0), Color = t.trim, Material = tier == 4 and Enum.Material.Neon or Enum.Material.Metal })
	end
end

-- 목걸이: 1 끈 + 구슬 / 2 은 사슬 + 작은 펜던트 / 3 금 사슬 + 메달 / 4 보석 펜던트 / 5 별빛(빛나는 별 모양)
builders.Necklace = function(character, folder, tier, glow, t)
	local torso = firstOf(character, "UpperTorso", "Torso")
	if not torso then return end
	local ts = torso.Size
	attach(folder, torso, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(tier == 1 and 0.08 or 0.14, ts.X * 0.92, ts.Z * 1.12), Offset = CFrame.new(0, ts.Y * 0.4, 0) * CYL, Color = t.main, Material = t.mat })
	local front = CFrame.new(0, ts.Y * 0.16, -ts.Z * 0.62)
	if tier == 1 then
		attach(folder, torso, { Shape = Enum.PartType.Ball, Size = Vector3.new(0.26, 0.26, 0.26), Offset = front, Color = t.trim, Material = Enum.Material.SmoothPlastic })
	elseif tier == 2 then
		attach(folder, torso, { Shape = Enum.PartType.Ball, Size = Vector3.new(0.3, 0.4, 0.2), Offset = front, Color = t.trim, Material = Enum.Material.Metal })
	elseif tier == 3 then
		attach(folder, torso, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 0.6, 0.6), Offset = front * CFrame.Angles(0, math.rad(90), 0), Color = t.main, Material = Enum.Material.Metal })
	elseif tier == 4 then
		attach(folder, torso, { Size = Vector3.new(0.55, 0.12, 0.12), Offset = front * CFrame.new(0, 0.28, 0), Color = t.main, Material = Enum.Material.Metal })
		attach(folder, torso, { Shape = Enum.PartType.Ball, Size = Vector3.new(0.5, 0.6, 0.3), Offset = front, Color = t.trim, Material = Enum.Material.Neon })
	else
		for k = 0, 1 do -- 별: 겹친 마름모 두 개
			attach(folder, torso, { Size = Vector3.new(0.12, 0.8, 0.8), Offset = front * CFrame.Angles(math.rad(45 * k), 0, math.rad(0)), Color = glow, Material = Enum.Material.Neon })
		end
		attach(folder, torso, { Shape = Enum.PartType.Ball, Size = Vector3.new(0.3, 0.3, 0.3), Offset = front, Color = t.trim, Material = Enum.Material.Neon })
	end
end

------------------------------------------------------------
-- 구역 세트 외형: 세트(Zone1~8)마다 색 / 재질 / 실루엣 / 발광 / 입자가 다르다.
--   기본 등급 장식 위에 세트 색을 입히고(tint) 부위별 고유 장식을 덧붙인다.
--   같은 세트 2부위 이상: 빛나는 띠 + 머리 위 떠 있는 상징 / 3부위 이상: 몸 둘레의 작은 상징 + 입자 한 줄 더.
--   모두 정적인 용접 부품이다 (서버에서 매 프레임 움직이지 않는다).
------------------------------------------------------------
local BALL, CYLS, NEON = Enum.PartType.Ball, Enum.PartType.Cylinder, Enum.Material.Neon

local function ang(x, y, z) return CFrame.Angles(math.rad(x or 0), math.rad(y or 0), math.rad(z or 0)) end

local SET_STYLE = {
	Zone1 = { main = rgb(110, 190, 80), accent = rgb(255, 225, 120), glow = rgb(190, 255, 140), mat = Enum.Material.Grass },
	Zone2 = { main = rgb(45, 115, 65), accent = rgb(120, 85, 50), glow = rgb(170, 255, 190), mat = Enum.Material.Wood },
	Zone3 = { main = rgb(150, 135, 115), accent = rgb(95, 85, 75), glow = rgb(255, 215, 140), mat = Enum.Material.Slate },
	Zone4 = { main = rgb(235, 190, 90), accent = rgb(255, 245, 215), glow = rgb(255, 200, 60), mat = Enum.Material.Sandstone },
	Zone5 = { main = rgb(165, 225, 255), accent = rgb(240, 252, 255), glow = rgb(140, 230, 255), mat = Enum.Material.Ice },
	Zone6 = { main = rgb(48, 32, 30), accent = rgb(130, 40, 20), glow = rgb(255, 130, 40), mat = Enum.Material.Basalt },
	Zone7 = { main = rgb(42, 26, 72), accent = rgb(110, 60, 190), glow = rgb(200, 140, 255), mat = Enum.Material.Slate },
	Zone8 = { main = rgb(22, 10, 40), accent = rgb(120, 40, 160), glow = rgb(255, 90, 190), mat = Enum.Material.Glass },
}

-- 세트마다 은은한 입자 한 줄 (낮은 Rate)
local SET_FX = {
	Zone1 = { Rate = 4, Life = NumberRange.new(1.5, 2.5), Speed = NumberRange.new(0.3, 1), Accel = Vector3.new(0.4, -1.5, 0), Size = 0.32, Light = 0.2 }, -- 떨어지는 잎
	Zone2 = { Rate = 4, Life = NumberRange.new(1.5, 2.5), Speed = NumberRange.new(0.2, 0.8), Accel = Vector3.new(0, 0.8, 0), Size = 0.22, Light = 1 },   -- 반딧불
	Zone3 = { Rate = 4, Life = NumberRange.new(1, 1.8), Speed = NumberRange.new(0.2, 0.8), Accel = Vector3.new(0, -2.5, 0), Size = 0.25, Light = 0 },    -- 돌가루
	Zone4 = { Rate = 5, Life = NumberRange.new(1, 1.8), Speed = NumberRange.new(1, 2.5), Accel = Vector3.new(2, 0.3, 0), Size = 0.22, Light = 0.6 },     -- 모래 바람
	Zone5 = { Rate = 5, Life = NumberRange.new(1.5, 2.5), Speed = NumberRange.new(0.2, 0.8), Accel = Vector3.new(0, -1.8, 0), Size = 0.26, Light = 0.8 }, -- 눈송이
	Zone6 = { Rate = 6, Life = NumberRange.new(0.8, 1.4), Speed = NumberRange.new(1, 3), Accel = Vector3.new(0, 6, 0), Size = 0.2, Light = 1 },           -- 불씨
	Zone7 = { Rate = 4, Life = NumberRange.new(1.2, 2), Speed = NumberRange.new(0.3, 1), Accel = Vector3.new(0, 2, 0), Size = 0.4, Light = 0.5 },        -- 그림자 연기
	Zone8 = { Rate = 5, Life = NumberRange.new(1.2, 2), Speed = NumberRange.new(0.5, 1.5), Accel = Vector3.new(0, 1, 0), Size = 0.28, Light = 1 },       -- 공허 입자
}

-- 머리 위에 떠 있는 세트 상징 (2부위 이상) : 모양 / 크기 / 재질 / 기울기
local SET_MOTIF = {
	Zone1 = { Size = Vector3.new(0.12, 0.8, 0.45), Rot = ang(0, 0, 25), Mat = Enum.Material.Grass },        -- 잎
	Zone2 = { Shape = BALL, Size = Vector3.new(0.5, 0.5, 0.5), Mat = NEON },                                -- 반딧불 구슬
	Zone3 = { Size = Vector3.new(0.45, 0.45, 0.45), Rot = ang(45, 45, 0), Mat = Enum.Material.Slate },     -- 룬 돌
	Zone4 = { Shape = CYLS, Size = Vector3.new(0.08, 0.95, 0.95), Rot = ang(0, 90, 0), Mat = NEON },        -- 태양 원반
	Zone5 = { Size = Vector3.new(0.3, 0.8, 0.3), Rot = ang(20, 0, 20), Mat = Enum.Material.Ice },          -- 얼음 결정
	Zone6 = { Shape = BALL, Size = Vector3.new(0.55, 0.55, 0.55), Mat = NEON },                             -- 용암 구슬
	Zone7 = { Shape = BALL, Size = Vector3.new(0.5, 0.65, 0.5), Mat = NEON, Trans = 0.45 },                -- 그림자 도깨비불
	Zone8 = { Shape = BALL, Size = Vector3.new(0.6, 0.6, 0.6), Mat = Enum.Material.Glass, Ring = true },   -- 공허 구슬
}

local function A(folder, limb, size, off, color, mat, shape, trans)
	return attach(folder, limb, { Size = size, Offset = off, Color = color, Material = mat, Shape = shape, Transparency = trans, Round = false })
end

-- 둘레에 비스듬히 벌어진 날 n 개 (왕관 / 잎 / 결정): vary 만큼 길이가 들쭉날쭉
local function spikes(folder, limb, n, rx, rz, y, size, tilt, color, mat, trans, vary)
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		local sz = Vector3.new(size.X, size.Y * (1 + (vary or 0) * math.sin(i * 2.3)), size.Z)
		A(folder, limb, sz, CFrame.new(math.cos(a) * rx, y + sz.Y * 0.4, math.sin(a) * rz) * CFrame.Angles(0, -a, 0) * ang(0, 0, -tilt), color, mat, nil, trans)
	end
end

local SetDecor = {}

SetDecor.Helmet = function(character, folder, z, st)
	local head = character:FindFirstChild("Head")
	if not head then return end
	local hs = head.Size
	local top = hs.Y * 0.9
	if z == 1 then -- 잎 왕관
		spikes(folder, head, 7, hs.X * 0.5, hs.Z * 0.5, top, Vector3.new(0.08, 0.9, 0.5), 35, st.main, st.mat, nil, 0.2)
		A(folder, head, Vector3.new(0.22, 0.22, 0.22), CFrame.new(hs.X * 0.28, hs.Y * 0.62, -hs.Z * 0.62), st.accent, NEON, BALL) -- 작은 꽃
	elseif z == 2 then -- 가지 뿔 + 빛나는 새순
		for _, side in ipairs({ -1, 1 }) do
			A(folder, head, Vector3.new(0.14, 1.4, 0.14), CFrame.new(side * hs.X * 0.45, top + 0.4, 0) * ang(0, 0, side * -22), st.accent, st.mat)
			A(folder, head, Vector3.new(0.1, 0.7, 0.1), CFrame.new(side * hs.X * 0.85, top + 0.7, 0) * ang(0, 0, side * -55), st.accent, st.mat)
			A(folder, head, Vector3.new(0.22, 0.22, 0.22), CFrame.new(side * hs.X * 1.05, top + 1.0, 0), st.glow, NEON, BALL)
		end
	elseif z == 3 then -- 부서진 돌 왕관 + 룬
		for i = 0, 4 do
			local a = i / 5 * math.pi * 2
			A(folder, head, Vector3.new(0.4, 0.3 + 0.2 * (i % 3), 0.4), CFrame.new(math.cos(a) * hs.X * 0.55, top + 0.1, math.sin(a) * hs.Z * 0.55) * ang(0, i * 20, i * 7 - 10), st.main, st.mat)
		end
		A(folder, head, Vector3.new(0.32, 0.1, 0.06), CFrame.new(0, hs.Y * 0.62, -hs.Z * 0.62), st.glow, NEON)
	elseif z == 4 then -- 터번 + 뒤의 태양 원반
		A(folder, head, Vector3.new(hs.X * 1.25, hs.Y * 0.7, hs.Z * 1.25), CFrame.new(0, hs.Y * 0.75, 0), st.accent, Enum.Material.Fabric, BALL)
		A(folder, head, Vector3.new(0.26, 0.26, 0.26), CFrame.new(0, hs.Y * 0.75, -hs.Z * 0.65), st.glow, NEON, BALL)
		A(folder, head, Vector3.new(0.1, 2.6, 2.6), CFrame.new(0, hs.Y * 1.0, hs.Z * 0.9) * ang(0, 90, 0), st.glow, NEON, CYLS, 0.3)
		for i = 0, 5 do -- 햇살
			local a = i / 6 * math.pi * 2 + 0.26
			A(folder, head, Vector3.new(0.14, 0.7, 0.1), CFrame.new(math.cos(a) * 1.75, hs.Y * 1.0 + math.sin(a) * 1.75, hs.Z * 0.9) * ang(0, 0, math.deg(a) - 90), st.glow, NEON)
		end
	elseif z == 5 then -- 얼음 결정 왕관
		spikes(folder, head, 6, hs.X * 0.52, hs.Z * 0.52, top, Vector3.new(0.18, 1.0, 0.18), 18, st.main, st.mat, 0.15, 0.35)
		A(folder, head, Vector3.new(0.26, 1.5, 0.26), CFrame.new(0, top + 0.7, 0), st.accent, st.mat, nil, 0.1)
	elseif z == 6 then -- 용암 뿔 + 이마 균열
		for _, side in ipairs({ -1, 1 }) do
			A(folder, head, Vector3.new(0.32, 1.1, 0.32), CFrame.new(side * hs.X * 0.55, top + 0.35, 0.05) * ang(0, 0, side * -38), st.main, st.mat)
			A(folder, head, Vector3.new(0.2, 0.7, 0.2), CFrame.new(side * hs.X * 0.95, top + 0.85, 0.05) * ang(0, 0, side * -12), st.glow, NEON)
		end
		A(folder, head, Vector3.new(0.08, 0.5, 0.06), CFrame.new(0, hs.Y * 0.7, -hs.Z * 0.62) * ang(0, 0, 12), st.glow, NEON)
	elseif z == 7 then -- 박쥐 귀 뿔 + 도깨비불
		for _, side in ipairs({ -1, 1 }) do
			A(folder, head, Vector3.new(0.42, 1.4, 0.1), CFrame.new(side * hs.X * 0.5, top + 0.5, 0.05) * ang(0, 0, side * -16), st.main, st.mat)
			A(folder, head, Vector3.new(0.3, 0.3, 0.3), CFrame.new(side * hs.X * 0.8, top + 1.4, 0), st.glow, NEON, BALL, 0.5)
		end
	else -- 8: 공허 왕관 (검은 구슬 + 분홍 고리)
		A(folder, head, Vector3.new(0.95, 0.95, 0.95), CFrame.new(0, hs.Y * 0.9 + 0.85, 0), st.main, Enum.Material.Glass, BALL, 0.1)
		A(folder, head, Vector3.new(0.07, 1.5, 1.5), CFrame.new(0, hs.Y * 0.9 + 0.85, 0) * ang(0, 0, 70), st.glow, NEON, CYLS, 0.15)
		A(folder, head, Vector3.new(0.4, 0.4, 0.4), CFrame.new(0, hs.Y * 0.9 + 0.85, 0), st.glow, NEON, BALL, 0.3)
	end
end

SetDecor.Armor = function(character, folder, z, st)
	local torso = firstOf(character, "UpperTorso", "Torso")
	if not torso then return end
	local ts = torso.Size
	local arms = {}
	for _, name in ipairs({ { "LeftUpperArm", "Left Arm", -1 }, { "RightUpperArm", "Right Arm", 1 } }) do
		local arm = firstOf(character, name[1], name[2])
		if arm then table.insert(arms, { Limb = arm, Side = name[3] }) end
	end
	local front, back = -ts.Z * 0.66, ts.Z * 0.68
	if z == 1 then -- 덩굴 + 꽃 + 잎 어깨
		for _, side in ipairs({ -1, 1 }) do
			A(folder, torso, Vector3.new(0.14, ts.Y * 1.0, 0.1), CFrame.new(0, 0, front) * ang(0, 0, side * 35), st.main, st.mat)
		end
		for i = -1, 1 do
			A(folder, torso, Vector3.new(0.24, 0.24, 0.24), CFrame.new(i * ts.X * 0.22, i * i * 0.2 + ts.Y * 0.05, front - 0.04), st.accent, NEON, BALL)
		end
		for _, a in ipairs(arms) do
			for k = 0, 1 do
				A(folder, a.Limb, Vector3.new(0.5, 0.9, 0.08), CFrame.new(a.Side * (a.Limb.Size.X * 0.6 + k * 0.2), a.Limb.Size.Y * 0.5, 0) * ang(0, 0, a.Side * (-35 - k * 25)), st.main, st.mat)
			end
		end
	elseif z == 2 then -- 나무껍질 어깨 + 이끼 + 빛나는 버섯
		for _, a in ipairs(arms) do
			local w = a.Limb.Size.X
			A(folder, a.Limb, Vector3.new(w * 1.8, w * 1.4, w * 1.8), CFrame.new(a.Side * 0.05, a.Limb.Size.Y * 0.42, 0), st.accent, st.mat, BALL)
			A(folder, a.Limb, Vector3.new(w * 1.2, w * 0.6, w * 1.2), CFrame.new(a.Side * 0.05, a.Limb.Size.Y * 0.62, 0), st.main, Enum.Material.Grass, BALL)
			A(folder, a.Limb, Vector3.new(0.24, 0.24, 0.24), CFrame.new(a.Side * w * 0.6, a.Limb.Size.Y * 0.72, 0), st.glow, NEON, BALL)
		end
		A(folder, torso, Vector3.new(0.18, ts.Y * 1.2, 0.18), CFrame.new(ts.X * 0.3, -ts.Y * 0.1, back) * ang(0, 0, 6), st.accent, st.mat)
	elseif z == 3 then -- 거대한 돌 견갑 + 룬 가슴판
		for _, a in ipairs(arms) do
			local w = a.Limb.Size.X
			A(folder, a.Limb, Vector3.new(w * 1.9, 0.9, w * 1.9), CFrame.new(a.Side * 0.1, a.Limb.Size.Y * 0.5, 0) * ang(0, a.Side * 15, a.Side * -8), st.main, st.mat)
			A(folder, a.Limb, Vector3.new(w * 0.9, 0.6, w * 0.9), CFrame.new(a.Side * w * 0.55, a.Limb.Size.Y * 0.2, 0.1) * ang(10, 0, a.Side * -20), st.accent, st.mat)
		end
		A(folder, torso, Vector3.new(ts.X * 0.9, ts.Y * 0.5, 0.18), CFrame.new(0, ts.Y * 0.12, front), st.main, st.mat)
		A(folder, torso, Vector3.new(0.12, ts.Y * 0.32, 0.06), CFrame.new(0, ts.Y * 0.12, front - 0.1), st.glow, NEON)
	elseif z == 4 then -- 사선 띠 + 망토 + 등의 태양
		A(folder, torso, Vector3.new(0.45, ts.Y * 1.25, 0.12), CFrame.new(0, 0, front) * ang(0, 0, 38), st.accent, Enum.Material.Fabric)
		A(folder, torso, Vector3.new(ts.X * 1.0, ts.Y * 1.5, 0.1), CFrame.new(0, -ts.Y * 0.35, back + 0.1) * ang(8, 0, 0), st.main, Enum.Material.Fabric)
		A(folder, torso, Vector3.new(0.1, 1.9, 1.9), CFrame.new(0, ts.Y * 0.1, back + 0.3) * ang(0, 90, 0), st.glow, NEON, CYLS, 0.25)
		for _, a in ipairs(arms) do
			A(folder, a.Limb, Vector3.new(0.18, a.Limb.Size.X * 1.5, a.Limb.Size.X * 1.5), CFrame.new(0, a.Limb.Size.Y * 0.35, 0) * CYL, st.glow, NEON, CYLS, 0.1)
		end
	elseif z == 5 then -- 어깨 얼음 파편 + 가슴 결정 + 서리 칼라
		for _, a in ipairs(arms) do
			for k = 0, 2 do
				A(folder, a.Limb, Vector3.new(0.2, 0.9 + k * 0.25, 0.2), CFrame.new(a.Side * (a.Limb.Size.X * 0.4 + k * 0.22), a.Limb.Size.Y * 0.55, (k - 1) * 0.2) * ang(0, 0, a.Side * (-15 - k * 20)), st.main, st.mat, nil, 0.15)
			end
		end
		for i = -1, 1 do
			A(folder, torso, Vector3.new(0.2, 0.8 - math.abs(i) * 0.2, 0.2), CFrame.new(i * ts.X * 0.25, ts.Y * 0.1, front - 0.05) * ang(-15, 0, i * -18), st.accent, st.mat, nil, 0.15)
		end
		A(folder, torso, Vector3.new(ts.X * 0.95, 0.35, ts.Z * 1.2), CFrame.new(0, ts.Y * 0.46, 0), st.accent, Enum.Material.Fabric, BALL)
	elseif z == 6 then -- 흑요석 갑옷에 용암 균열 + 가슴 핵 + 어깨 가시
		local cracks = { { -0.25, 0.1, 25 }, { 0.2, -0.05, -20 }, { 0, 0.3, 5 }, { 0.3, 0.25, 40 } }
		for _, c in ipairs(cracks) do
			A(folder, torso, Vector3.new(0.09, ts.Y * 0.4, 0.05), CFrame.new(c[1] * ts.X, c[2] * ts.Y, front - 0.04) * ang(0, 0, c[3]), st.glow, NEON)
		end
		A(folder, torso, Vector3.new(0.5, 0.5, 0.25), CFrame.new(0, ts.Y * 0.14, front - 0.05), st.glow, NEON, BALL)
		for _, a in ipairs(arms) do
			A(folder, a.Limb, Vector3.new(0.34, 1.0, 0.34), CFrame.new(a.Side * a.Limb.Size.X * 0.6, a.Limb.Size.Y * 0.6, 0) * ang(0, 0, a.Side * -30), st.main, st.mat)
			A(folder, a.Limb, Vector3.new(0.1, 0.5, 0.1), CFrame.new(a.Side * a.Limb.Size.X * 1.0, a.Limb.Size.Y * 0.95, 0) * ang(0, 0, a.Side * -30), st.glow, NEON)
		end
		A(folder, torso, Vector3.new(0.09, ts.Y * 0.8, 0.05), CFrame.new(0, 0, back + 0.04) * ang(0, 0, 10), st.glow, NEON)
	elseif z == 7 then -- 박쥐 날개 + 어깨 도깨비불
		for _, side in ipairs({ -1, 1 }) do
			local base = CFrame.new(side * ts.X * 0.7, ts.Y * 0.3, back + 0.1) * ang(-12, side * 18, side * -50)
			A(folder, torso, Vector3.new(0.1, 2.4, 0.1), base * CFrame.new(0, 1.0, 0), st.accent, st.mat)
			A(folder, torso, Vector3.new(0.05, 1.9, 1.3), base * CFrame.new(side * -0.1, 0.8, 0.5) * ang(0, 0, side * 14), st.main, Enum.Material.Fabric, nil, 0.1)
			A(folder, torso, Vector3.new(0.05, 1.3, 1.0), base * CFrame.new(side * -0.15, 0.4, -0.2) * ang(0, 0, side * 14), st.main, Enum.Material.Fabric, nil, 0.1)
		end
		for _, a in ipairs(arms) do
			A(folder, a.Limb, Vector3.new(0.4, 0.5, 0.4), CFrame.new(a.Side * a.Limb.Size.X * 0.7, a.Limb.Size.Y * 0.7, 0), st.glow, NEON, BALL, 0.45)
		end
	else -- 8: 공허 구슬 견갑 + 가슴 핵 + 등 뒤 고리
		for _, a in ipairs(arms) do
			local w = a.Limb.Size.X
			A(folder, a.Limb, Vector3.new(w * 1.7, w * 1.7, w * 1.7), CFrame.new(a.Side * 0.1, a.Limb.Size.Y * 0.5, 0), st.main, Enum.Material.Glass, BALL, 0.1)
			A(folder, a.Limb, Vector3.new(0.07, w * 2.2, w * 2.2), CFrame.new(a.Side * 0.1, a.Limb.Size.Y * 0.5, 0) * ang(0, 0, 90 + a.Side * 25), st.glow, NEON, CYLS, 0.2)
		end
		A(folder, torso, Vector3.new(0.7, 0.7, 0.3), CFrame.new(0, ts.Y * 0.14, front - 0.04), st.main, Enum.Material.Glass, BALL, 0.1)
		A(folder, torso, Vector3.new(0.3, 0.3, 0.2), CFrame.new(0, ts.Y * 0.14, front - 0.1), st.glow, NEON, BALL)
		A(folder, torso, Vector3.new(0.08, 2.6, 2.6), CFrame.new(0, ts.Y * 0.1, back + 0.5) * ang(0, 90, 0), st.glow, NEON, CYLS, 0.45)
	end
end

SetDecor.Gloves = function(character, folder, z, st)
	for _, names in ipairs({ { "LeftHand", "Left Arm", -1 }, { "RightHand", "Right Arm", 1 } }) do
		local hand = firstOf(character, names[1], names[2])
		if hand then
			local hs, side = hand.Size, names[3]
			local drop = hand.Name:find("Arm") and -hs.Y * 0.32 or 0
			if z == 1 then
				for k = 0, 1 do A(folder, hand, Vector3.new(0.4, 0.7, 0.06), CFrame.new(side * hs.X * 0.6, drop + 0.55, (k - 0.5) * 0.5) * ang(0, 0, side * -40), st.main, st.mat) end
			elseif z == 2 then
				A(folder, hand, Vector3.new(0.5, hs.X * 1.7, hs.Z * 1.7), CFrame.new(0, drop + 0.5, 0) * CYL, st.accent, st.mat, CYLS)
				A(folder, hand, Vector3.new(0.2, 0.2, 0.2), CFrame.new(side * hs.X * 0.9, drop + 0.5, 0), st.glow, NEON, BALL)
			elseif z == 3 then
				A(folder, hand, Vector3.new(hs.X * 1.45, math.min(hs.Y, 1.1) * 1.1, hs.Z * 1.45), CFrame.new(0, drop, 0), st.main, st.mat)
				A(folder, hand, Vector3.new(0.3, 0.06, 0.06), CFrame.new(0, drop + 0.1, -hs.Z * 0.76), st.glow, NEON)
			elseif z == 4 then
				A(folder, hand, Vector3.new(0.45, hs.X * 1.65, hs.Z * 1.65), CFrame.new(0, drop + 0.5, 0) * CYL, st.main, Enum.Material.Metal, CYLS)
				A(folder, hand, Vector3.new(0.2, 1.0, 0.08), CFrame.new(side * hs.X * 0.75, drop + 0.1, 0.2) * ang(0, 0, side * -10), st.accent, Enum.Material.Fabric)
			elseif z == 5 then
				for i = -1, 1 do A(folder, hand, Vector3.new(0.12, 0.65, 0.12), CFrame.new(i * hs.X * 0.3, drop + 0.15, -hs.Z * 0.75) * ang(-50, 0, 0), st.accent, st.mat, nil, 0.15) end
				A(folder, hand, Vector3.new(0.16, 0.9, 0.16), CFrame.new(side * hs.X * 0.75, drop + 0.7, 0) * ang(0, 0, side * -25), st.main, st.mat, nil, 0.15)
			elseif z == 6 then
				A(folder, hand, Vector3.new(0.45, hs.X * 1.6, hs.Z * 1.6), CFrame.new(0, drop + 0.5, 0) * CYL, st.main, st.mat, CYLS)
				A(folder, hand, Vector3.new(0.08, hs.X * 1.68, hs.Z * 1.68), CFrame.new(0, drop + 0.5, 0) * CYL, st.glow, NEON, CYLS)
				A(folder, hand, Vector3.new(0.3, 0.3, 0.3), CFrame.new(0, drop - 0.1, -hs.Z * 0.7), st.glow, NEON, BALL)
			elseif z == 7 then
				A(folder, hand, Vector3.new(0.4, 0.4, 0.4), CFrame.new(side * hs.X * 0.5, drop - 0.3, -hs.Z * 0.5), st.glow, NEON, BALL, 0.45)
				for i = -1, 1, 2 do A(folder, hand, Vector3.new(0.08, 0.1, 0.7), CFrame.new(i * hs.X * 0.25, drop - 0.05, -hs.Z * 0.95), st.accent, st.mat) end
			else
				A(folder, hand, Vector3.new(0.55, 0.55, 0.55), CFrame.new(0, drop - 0.2, -hs.Z * 1.0), st.main, Enum.Material.Glass, BALL, 0.1)
				A(folder, hand, Vector3.new(0.07, 0.95, 0.95), CFrame.new(0, drop - 0.2, -hs.Z * 1.0) * ang(0, 0, 90), st.glow, NEON, CYLS, 0.25)
			end
		end
	end
end

SetDecor.Boots = function(character, folder, z, st)
	for _, names in ipairs({ { "LeftFoot", "Left Leg" }, { "RightFoot", "Right Leg" } }) do
		local foot = firstOf(character, names[1], names[2])
		if foot then
			local fs = foot.Size
			local drop = foot.Name:find("Leg") and -fs.Y * 0.36 or 0
			for _, side in ipairs({ -1, 1 }) do
				if z == 1 then -- 잎 장식
					A(folder, foot, Vector3.new(0.06, 0.6, 0.3), CFrame.new(side * fs.X * 0.62, drop + 0.4, 0.1) * ang(0, 0, side * -35), st.main, st.mat)
				elseif z == 5 then -- 얼음 가시
					A(folder, foot, Vector3.new(0.1, 0.8, 0.2), CFrame.new(side * fs.X * 0.62, drop + 0.5, 0.15) * ang(0, 0, side * -22), st.accent, st.mat, nil, 0.15)
				elseif z == 7 then -- 작은 날개
					A(folder, foot, Vector3.new(0.05, 0.6, 0.3), CFrame.new(side * fs.X * 0.6, drop + 0.4, 0.2) * ang(-20, 0, side * -30), st.main, Enum.Material.Fabric, nil, 0.1)
				elseif side == 1 then
					if z == 2 then -- 이끼 덩어리
						A(folder, foot, Vector3.new(fs.X * 1.3, 0.4, fs.Z * 1.3), CFrame.new(0, drop + 0.45, 0), st.main, Enum.Material.Grass, BALL)
					elseif z == 3 then -- 돌 앞코
						A(folder, foot, Vector3.new(fs.X * 1.25, 0.5, fs.Z * 0.8), CFrame.new(0, drop + 0.3, -fs.Z * 0.45), st.main, st.mat)
					elseif z == 4 then -- 천 감기 + 금 발찌
						A(folder, foot, Vector3.new(0.3, fs.X * 1.4, fs.Z * 1.4), CFrame.new(0, drop + 0.5, 0) * CYL, st.accent, Enum.Material.Fabric, CYLS)
						A(folder, foot, Vector3.new(0.06, fs.X * 1.5, fs.Z * 1.5), CFrame.new(0, drop + 0.7, 0) * CYL, st.glow, NEON, CYLS)
					elseif z == 6 then -- 용암 밑창 + 불씨
						A(folder, foot, Vector3.new(fs.X * 0.9, 0.1, fs.Z * 1.2), CFrame.new(0, drop - 0.45, -0.04), st.glow, NEON)
						A(folder, foot, Vector3.new(0.2, 0.2, 0.2), CFrame.new(0, drop + 0.55, fs.Z * 0.55), st.glow, NEON, BALL)
					elseif z == 8 then -- 공허 구슬 + 고리
						A(folder, foot, Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, drop + 0.7, 0), st.main, Enum.Material.Glass, BALL, 0.1)
						A(folder, foot, Vector3.new(0.06, fs.X * 1.7, fs.Z * 1.7), CFrame.new(0, drop + 0.4, 0) * CYL, st.glow, NEON, CYLS, 0.2)
					end
				end
				if z == 7 and side == 1 then -- 발목 도깨비불
					A(folder, foot, Vector3.new(0.4, 0.4, 0.4), CFrame.new(0, drop + 0.6, 0), st.glow, NEON, BALL, 0.5)
				end
			end
		end
	end
end

-- 기존 등급 장식에 세트 색 / 재질을 입힌다: 발광 부품은 세트 발광색으로, 나머지는 세트 본색 + 재질로.
local function setTint(folder, st)
	for _, p in ipairs(folder:GetChildren()) do
		if p:IsA("BasePart") then
			if p.Material == NEON then
				p.Color = p.Color:Lerp(st.glow, 0.6)
			else
				p.Color = p.Color:Lerp(st.main, 0.6)
				p.Material = st.mat
			end
		end
	end
end

local function setEmitter(parent, z, st)
	local fx = SET_FX["Zone" .. z]
	if not fx or not parent then return end
	local e = Instance.new("ParticleEmitter")
	e.Name = "SetFx"
	e.Rate = fx.Rate
	e.Lifetime = fx.Life
	e.Speed = fx.Speed
	e.Acceleration = fx.Accel
	e.SpreadAngle = Vector2.new(180, 180)
	e.LightEmission = fx.Light
	e.Color = ColorSequence.new(st.glow)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, fx.Size), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.Parent = parent
end

local function setZone(setKey)
	return tonumber(string.match(setKey or "", "^Zone(%d+)$"))
end

-- 한 부위의 세트 외형을 입힌다 (folder 는 이미 등급 장식이 만들어진 상태). 반환: 세트 번호 또는 nil
local function applySetLook(character, folder, slotKey, setKey)
	local z = setZone(setKey)
	local st = z and SET_STYLE["Zone" .. z]
	if not st then return nil end
	setTint(folder, st)
	local decor = SetDecor[slotKey]
	if decor then decor(character, folder, z, st) end
	return z
end

-- 같은 세트 2부위 이상: 빛나는 띠 + 머리 위 상징 / 3부위 이상: 몸 둘레 작은 상징 + 입자
local function applySetBonus(character, counts, slotSets)
	local old = character:FindFirstChild("GearVisual_SetBonus")
	if old then old:Destroy() end
	local bestKey, bestCount = nil, 0
	for key, n in pairs(counts) do
		if n >= 2 and n > bestCount and SET_STYLE[key] then bestKey, bestCount = key, n end
	end
	if not bestKey then return end
	local z = setZone(bestKey)
	local st = SET_STYLE[bestKey]
	local folder = Instance.new("Folder")
	folder.Name = "GearVisual_SetBonus"
	folder.Parent = character

	-- 빛나는 띠: 같은 세트를 낀 부위마다 한 줄
	local head = character:FindFirstChild("Head")
	local torso = firstOf(character, "UpperTorso", "Torso")
	local hand = firstOf(character, "RightHand", "Right Arm")
	local foot = firstOf(character, "RightFoot", "Right Leg")
	local function trim(limb, y, scale)
		if limb then A(folder, limb, Vector3.new(0.07, limb.Size.X * scale, limb.Size.Z * scale), CFrame.new(0, y, 0) * CYL, st.glow, NEON, CYLS, 0.2) end
	end
	if slotSets.Helmet == bestKey and head then trim(head, head.Size.Y * 0.44, 1.2) end
	if slotSets.Armor == bestKey and torso then trim(torso, -torso.Size.Y * 0.2, 1.18) end
	if slotSets.Gloves == bestKey and hand then trim(hand, hand.Name:find("Arm") and -hand.Size.Y * 0.2 or 0.35, 1.3) end
	if slotSets.Boots == bestKey and foot then trim(foot, foot.Name:find("Leg") and -foot.Size.Y * 0.2 or 0.35, 1.3) end

	-- 떠 있는 상징: 머리 위에 하나, 3부위 이상이면 몸 둘레에 작은 것 셋
	local motif = SET_MOTIF["Zone" .. z]
	local function floatMotif(limb, off, scale)
		attach(folder, limb, { Size = motif.Size * scale, Offset = off * (motif.Rot or CFrame.new()), Color = st.glow, Material = motif.Mat, Shape = motif.Shape, Transparency = motif.Trans, Round = false })
		if motif.Ring then
			A(folder, limb, Vector3.new(0.05, scale, scale), off * ang(0, 0, 90), st.glow, NEON, CYLS, 0.25)
		end
	end
	if head then
		floatMotif(head, CFrame.new(0, head.Size.Y * 0.5 + 2.2, 0), 1)
	end
	if bestCount >= 3 and torso then
		for i = 0, 2 do
			local a = i / 3 * math.pi * 2
			floatMotif(torso, CFrame.new(math.cos(a) * 2.3, -torso.Size.Y * 0.2 + math.sin(i * 2) * 0.3, math.sin(a) * 2.3), 0.55)
		end
		setEmitter(head or torso, z, st)
	end
end

function Gear.ApplyVisuals(player)
	local character = player.Character
	if not character then return end

	local slotSets, setCounts, setFxHost, setFxZone = {}, {}, nil, nil
	for _, slot in ipairs(G.Slots) do
		local old = character:FindFirstChild("GearVisual_" .. slot.Key)
		if old then
			old:Destroy()
		end

		local rarity = player:GetAttribute(rAttr(slot.Key)) or 0
		local build = builders[slot.Key]
		if rarity > 0 and build then
			local glow = G.RarityColors[rarity]
			local color = glow
			local folder = Instance.new("Folder")
			folder.Name = "GearVisual_" .. slot.Key
			folder.Parent = character
			local palette = TIERS[slot.Key] and TIERS[slot.Key][rarity]
			build(character, folder, rarity, glow, palette)
			local setKey = player:GetAttribute("Gear_" .. slot.Key .. "_Set")
			if setKey and setKey ~= "" then
				if applySetLook(character, folder, slot.Key, setKey) then
					slotSets[slot.Key] = setKey
					setCounts[setKey] = (setCounts[setKey] or 0) + 1
					if not setFxHost and (slot.Key == "Armor" or slot.Key == "Helmet") then
						setFxHost = folder:FindFirstChildWhichIsA("BasePart")
						setFxZone = setZone(setKey)
					end
				end
			end

			if rarity >= 4 then -- 전설 이상: 윤곽 빛
				local outline = Instance.new("Highlight")
				outline.Adornee = folder
				outline.FillTransparency = 1
				outline.OutlineColor = glow
				outline.OutlineTransparency = rarity == 5 and 0.1 or 0.35
				outline.DepthMode = Enum.HighlightDepthMode.Occluded
				outline.Parent = folder
			end

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

	-- 구역 세트 보너스 외형 + 입자 한 줄 (몸통 / 투구 부품에 붙인다)
	applySetBonus(character, setCounts, slotSets)
	if setFxHost and setFxZone then
		local bonusKey = "Zone" .. setFxZone
		if (setCounts[bonusKey] or 0) >= 1 then setEmitter(setFxHost, setFxZone, SET_STYLE[bonusKey]) end
	end

	-- 세트 효과: 고급(3등급) 이상 장비를 3개 이상 끼면 몸 전체에 은은한 기운
	local oldAura = character:FindFirstChild("GearAura", true)
	if oldAura then oldAura:Destroy() end
	local count, best = 0, 0
	for _, slot in ipairs(G.Slots) do
		local r = player:GetAttribute(rAttr(slot.Key)) or 0
		if r >= 3 then count += 1 end
		best = math.max(best, r)
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if count >= 3 and root then
		local color = G.RarityColors[best]
		local aura = Instance.new("Attachment")
		aura.Name = "GearAura"
		aura.Parent = root
		local fx = Instance.new("ParticleEmitter")
		fx.Rate = 10 + count * 4
		fx.Lifetime = NumberRange.new(0.8, 1.4)
		fx.Speed = NumberRange.new(1, 3)
		fx.Acceleration = Vector3.new(0, 4, 0)
		fx.SpreadAngle = Vector2.new(180, 180)
		fx.LightEmission = 1
		fx.Color = ColorSequence.new(color)
		fx.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
		fx.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		fx.Parent = aura
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 8 + count
		light.Brightness = 1.2
		light.Parent = aura
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
		return false, string.format("💰 골드가 부족해요. (%d 필요) 허수아비 훈련장 / 필드 사냥 / 던전 / 심연 소탕으로 골드를 벌어요", cost)
	end
	player:SetAttribute("Gold", gold - cost)

	if math.random() < Config.GetGearEnhanceChance(level) then
		Inventory.SetLevel(player, slotKey, level + 1) -- 아이템의 강화 레벨 + 능력치 / 외형 갱신
		Quest.Add(player, "Enhances", 1)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			Effects.Burst(root.Position, G.RarityColors[rarity], 30)
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
function Gear.Roll(player, forced)
	if player:GetAttribute("Zone") ~= "Lobby" then
		return false, "뽑기는 로비에서만 할 수 있어요."
	end
	local tickets = player:GetAttribute("Tickets") or 0
	if tickets < 1 then
		return false, "🎫 티켓이 없어요! 던전을 클리어하거나, 필드 군주·엘리트를 잡거나, 일일 퀘스트를 하면 얻을 수 있어요"
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

	-- 튜토리얼 뽑기 보정: 첫 뽑기는 무조건 일반, 10연은 영웅 1개 확정 + 전설 / 신화 없음
	local mode = player:GetAttribute("TutorialRoll")
	if mode == "Lowest" then
		rarity = 1
	elseif mode == "Hero" then
		local count = (player:GetAttribute("TutorialRollCount") or 0) + 1
		player:SetAttribute("TutorialRollCount", count)
		rarity = math.min(rarity, 3)
		if forced then
			rarity = forced
		elseif not player:GetAttribute("TutorialHero") and count >= 10 then
			rarity = 3 -- 낱개로 뽑아도 열 번째까지 영웅이 안 나왔으면 마지막에 확정
		end
		if rarity >= 3 then player:SetAttribute("TutorialHero", true) end
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
