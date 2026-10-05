-- WeaponService (ServerScriptService > Modules 안의 ModuleScript, 이름: WeaponService)
-- 무기 강화 + 무기 외형 생성.
-- 무기는 서버에서 만들어 캐릭터에 장착하기 때문에 로비의 모든 플레이어에게 그대로 보인다.
-- 강화 레벨(WeaponLevel)이 오를수록 색상 / 크기 / 재질 / 파티클 / 궤적 / 빛이 달라진다.

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Config"))
local Effects = require(script.Parent:WaitForChild("Effects"))

local Weapon = {}

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 60)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 220, 60)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(80, 255, 100)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(60, 220, 255)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(90, 90, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 255)),
})

local function weld(part0, part1)
	local w = Instance.new("WeldConstraint")
	w.Part0 = part0
	w.Part1 = part1
	w.Parent = part0
end

local function newPart(name, size, color, material, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- 레벨에 맞는 무기(Tool)를 만든다. 칼날 방향은 손잡이의 -Z (팔을 뻗은 방향).
local function buildTool(level)
	local tier = Config.GetWeaponTier(level)
	local scale = Config.GetWeaponScale(level)
	local bladeLength = 3 * scale
	local colorSeq = tier.Rainbow and RAINBOW or ColorSequence.new(tier.Color)

	local tool = Instance.new("Tool")
	tool.Name = "Weapon"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ToolTip = string.format("+%d %s", level, tier.Name)

	local handle = newPart("Handle", Vector3.new(0.35, 0.35, 1.1), Color3.fromRGB(80, 55, 35), Enum.Material.Wood, tool)

	local guard = newPart("Guard", Vector3.new(1.0 * scale, 0.22, 0.3), tier.Color:Lerp(Color3.new(0, 0, 0), 0.35), Enum.Material.Metal, tool)
	guard.CFrame = handle.CFrame * CFrame.new(0, 0, -0.6)
	weld(handle, guard)

	local blade = newPart("Blade", Vector3.new(0.22 * scale, 0.55 * scale, bladeLength), tier.Color, tier.Material, tool)
	blade.CFrame = handle.CFrame * CFrame.new(0, 0, -(0.7 + bladeLength / 2))
	weld(handle, blade)

	local tip = Instance.new("Attachment")
	tip.Name = "Tip"
	tip.Position = Vector3.new(0, 0, -bladeLength / 2)
	tip.Parent = blade

	local base = Instance.new("Attachment")
	base.Name = "Base"
	base.Position = Vector3.new(0, 0, bladeLength / 2)
	base.Parent = blade

	if tier.Particles > 0 then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Sparkle"
		emitter.Rate = tier.Particles
		emitter.Lifetime = NumberRange.new(0.4, 0.9)
		emitter.Speed = NumberRange.new(0.5, 2)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Shape = Enum.ParticleEmitterShape.Box
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3 * scale),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.LightEmission = 1
		emitter.Color = colorSeq
		emitter.Parent = blade
	end

	if tier.Trail then
		local trail = Instance.new("Trail")
		trail.Attachment0 = base
		trail.Attachment1 = tip
		trail.Lifetime = 0.4
		trail.Color = colorSeq
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.LightEmission = 1
		trail.FaceCamera = true
		trail.Parent = blade
	end

	if tier.Light > 0 then
		local light = Instance.new("PointLight")
		light.Range = tier.Light
		light.Brightness = 1.5
		light.Color = tier.Rainbow and Color3.fromRGB(255, 255, 255) or tier.Color
		light.Parent = blade
	end

	return tool
end

------------------------------------------------------------
-- 머리 위 이름표: 이름 + 무기 강화 레벨 (다른 플레이어에게 과시)
------------------------------------------------------------
local function updateNameplate(player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then return end

	local gui = head:FindFirstChild("Nameplate")
	if not gui then
		gui = Instance.new("BillboardGui")
		gui.Name = "Nameplate"
		gui.Size = UDim2.new(0, 220, 0, 56)
		gui.StudsOffset = Vector3.new(0, 2.8, 0)
		gui.MaxDistance = 140
		gui.Parent = head

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "PlayerName"
		nameLabel.Size = UDim2.new(1, 0, 0.45, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextScaled = true
		nameLabel.TextColor3 = Color3.new(1, 1, 1)
		nameLabel.TextStrokeTransparency = 0.3
		nameLabel.Parent = gui

		local weaponLabel = Instance.new("TextLabel")
		weaponLabel.Name = "WeaponLevel"
		weaponLabel.Size = UDim2.new(1, 0, 0.55, 0)
		weaponLabel.Position = UDim2.new(0, 0, 0.45, 0)
		weaponLabel.BackgroundTransparency = 1
		weaponLabel.Font = Enum.Font.GothamBlack
		weaponLabel.TextScaled = true
		weaponLabel.TextStrokeTransparency = 0
		weaponLabel.Parent = gui
	end

	local level = player:GetAttribute("WeaponLevel") or 0
	local tier = Config.GetWeaponTier(level)
	local inParty = (player:GetAttribute("PartyId") or 0) ~= 0

	gui.PlayerName.Text = (inParty and "[파티] " or "") .. player.DisplayName
	gui.WeaponLevel.Text = string.format("+%d %s", level, tier.Name)
	gui.WeaponLevel.TextColor3 = tier.Rainbow and Color3.fromRGB(255, 120, 255) or tier.Color
end

Weapon.UpdateNameplate = updateNameplate

------------------------------------------------------------
-- 장착 / 갱신
------------------------------------------------------------
function Weapon.Attach(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local old = character:FindFirstChild("Weapon")
	if old then
		old:Destroy()
	end

	local tool = buildTool(player:GetAttribute("WeaponLevel") or 0)
	humanoid:EquipTool(tool)
end

function Weapon.Refresh(player)
	Weapon.Attach(player)
	updateNameplate(player)
end

function Weapon.GetTipPosition(player)
	local character = player.Character
	local tool = character and character:FindFirstChild("Weapon")
	local blade = tool and tool:FindFirstChild("Blade")
	local tip = blade and blade:FindFirstChild("Tip")
	return tip and tip.WorldPosition or nil
end

-- 기본 애니메이터의 휘두르기 모션을 재생
function Weapon.PlaySwing(player)
	local character = player.Character
	local tool = character and character:FindFirstChild("Weapon")
	if not tool then return end
	local anim = Instance.new("StringValue")
	anim.Name = "toolanim"
	anim.Value = "Slash"
	anim.Parent = tool
end

------------------------------------------------------------
-- 강화: 골드를 내고 확률적으로 +1. 실패해도 레벨은 내려가지 않음.
-- 반환: ok(성공 여부), message
------------------------------------------------------------
function Weapon.Enhance(player)
	if player:GetAttribute("Zone") ~= "Lobby" then
		return false, "무기 강화는 로비에서만 할 수 있어요."
	end

	local level = player:GetAttribute("WeaponLevel") or 0
	if level >= Config.Weapon.MaxLevel then
		return false, "이미 최대 강화 단계입니다!"
	end

	local cost = Config.GetEnhanceCost(level)
	local gold = player:GetAttribute("Gold") or 0
	if gold < cost then
		return false, string.format("골드가 부족합니다. (%d 필요)", cost)
	end

	player:SetAttribute("Gold", gold - cost)

	if math.random() < Config.GetEnhanceChance(level) then
		player:SetAttribute("WeaponLevel", level + 1) -- 외형 갱신은 WeaponLevel 변경 감지에서 처리
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			Effects.Burst(root.Position, Config.GetWeaponTier(level + 1).Color, 30 + level * 4)
		end
		return true, string.format("강화 성공! +%d", level + 1)
	end
	return false, "강화 실패... (골드만 사라졌어요)"
end

return Weapon
