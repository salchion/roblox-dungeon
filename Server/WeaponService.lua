-- WeaponService (ServerScriptService > Modules 안의 ModuleScript, 이름: WeaponService)
-- 무기(총) 종류(권총 / 샷건 / 저격총) + 강화 + 무기 외형 생성.
-- 무기는 서버에서 만들어 캐릭터에 장착하기 때문에 로비의 모든 플레이어에게 그대로 보인다.
-- 강화 레벨(WeaponLevel)이 오를수록 색상 / 크기 / 재질 / 파티클 / 궤적 / 빛이 달라진다.

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Config"))
local Effects = require(script.Parent:WaitForChild("Effects"))
local Quest = require(script.Parent:WaitForChild("QuestService"))
local Event = require(script.Parent:WaitForChild("EventService"))

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

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

-- 레벨에 맞는 무기(Tool, 총)를 만든다. 총구 방향은 손잡이의 -Z (팔을 뻗은 방향).
local function buildTool(level, typeKey)
	local tier = Config.GetWeaponTier(level)
	local scale = Config.GetWeaponScale(level)
	local weaponType = Config.WeaponTypes[typeKey] or Config.WeaponTypes.Pistol
	local thick = weaponType.BarrelThickness
	local barrelLength = 1.8 * scale * weaponType.BarrelLength
	local colorSeq = tier.Rainbow and RAINBOW or ColorSequence.new(tier.Color)
	local dark = Color3.fromRGB(45, 45, 55)

	local tool = Instance.new("Tool")
	tool.Name = "Weapon"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ToolTip = Config.FormatWeapon(level)

	-- 몸체(손에 쥐는 부분)
	local handle = newPart("Handle", Vector3.new(0.4, 0.6, 1.4), dark, Enum.Material.Metal, tool)

	-- 손잡이 그립
	local grip = newPart("Grip", Vector3.new(0.35, 0.9, 0.4), Color3.fromRGB(80, 55, 35), Enum.Material.Wood, tool)
	grip.CFrame = handle.CFrame * CFrame.new(0, -0.7, 0.4) * CFrame.Angles(math.rad(-12), 0, 0)
	weld(handle, grip)

	-- 총열: 강화할수록 길어지고 색/재질이 변함
	local barrel = newPart("Barrel", Vector3.new(0.3 * scale * thick, 0.3 * scale * thick, barrelLength), tier.Color, tier.Material, tool)
	barrel.CFrame = handle.CFrame * CFrame.new(0, 0.05, -(0.7 + barrelLength / 2))
	weld(handle, barrel)

	-- 몸체 위 장식 띠 (등급 색)
	local stripe = newPart("Stripe", Vector3.new(0.44, 0.12, 0.9), tier.Color, tier.Material, tool)
	stripe.CFrame = handle.CFrame * CFrame.new(0, 0.34, 0.1)
	weld(handle, stripe)

	-- 무기 종류별 모양
	if typeKey == "Shotgun" then
		-- 쌍열 총신 + 펌프 손잡이
		local lower = newPart("BarrelLower", Vector3.new(0.3 * scale * thick, 0.3 * scale * thick, barrelLength), tier.Color, tier.Material, tool)
		lower.CFrame = handle.CFrame * CFrame.new(0, 0.05 - 0.42 * scale * thick, -(0.7 + barrelLength / 2))
		weld(handle, lower)
		local pump = newPart("Pump", Vector3.new(0.5 * scale, 0.5 * scale, 0.9), Color3.fromRGB(80, 55, 35), Enum.Material.Wood, tool)
		pump.CFrame = handle.CFrame * CFrame.new(0, -0.25, -(0.9 + barrelLength * 0.3))
		weld(handle, pump)
	elseif typeKey == "Sniper" then
		-- 조준경 + 개머리판
		local scope = newPart("Scope", Vector3.new(0.4, 0.4, 1.3), dark, Enum.Material.Metal, tool)
		scope.CFrame = handle.CFrame * CFrame.new(0, 0.55, -0.1)
		weld(handle, scope)
		local lens = newPart("Lens", Vector3.new(0.34, 0.34, 0.08), tier.Color, Enum.Material.Neon, tool)
		lens.CFrame = handle.CFrame * CFrame.new(0, 0.55, -0.78)
		weld(handle, lens)
		local stock = newPart("Stock", Vector3.new(0.4, 0.6, 1.2), Color3.fromRGB(80, 55, 35), Enum.Material.Wood, tool)
		stock.CFrame = handle.CFrame * CFrame.new(0, -0.05, 1.2)
		weld(handle, stock)
	end

	-- 진화 단계(Form)별 추가 장식: 단계가 오를수록 총의 실루엣이 확 달라진다
	local form = weaponType.Form
	local function cyl(name, size, color, material, cf)
		local p = newPart(name, size, color, material, tool)
		p.Shape = Enum.PartType.Cylinder
		p.CFrame = cf * CFrame.Angles(0, math.rad(90), 0) -- 원통 축을 총구 방향(Z)으로
		weld(handle, p)
		return p
	end
	local muzzleZ = -(0.7 + barrelLength)
	if form == "Steel" then
		cyl("Cylinder", Vector3.new(0.7, 0.75, 0.75), dark, Enum.Material.Metal, handle.CFrame * CFrame.new(0, 0.05, -0.2))
	elseif form == "Arcane" then
		local crystal = newPart("Crystal", Vector3.new(0.35, 0.35, 0.35) * scale, tier.Color, Enum.Material.Neon, tool)
		crystal.CFrame = handle.CFrame * CFrame.new(0, 0.75, -0.3) * CFrame.Angles(math.rad(45), math.rad(45), 0)
		weld(handle, crystal)
		for side = -1, 1, 2 do
			local fin = newPart("Fin", Vector3.new(0.08, 0.5, 1.1), tier.Color, Enum.Material.Glass, tool)
			fin.CFrame = handle.CFrame * CFrame.new(side * 0.3, 0.1, muzzleZ * 0.45)
			weld(handle, fin)
		end
	elseif form == "Cannon" then
		cyl("MuzzleRing", Vector3.new(0.5, 0.75 * scale * thick, 0.75 * scale * thick), tier.Color, Enum.Material.Neon, handle.CFrame * CFrame.new(0, 0.05, muzzleZ + 0.2))
		cyl("Drum", Vector3.new(0.9, 0.85, 0.85), dark, Enum.Material.Metal, handle.CFrame * CFrame.new(0, 0.55, 0.1))
	elseif form == "Rocket" then
		-- 어깨에 얹는 로켓 발사관 + 앞으로 튀어나온 탄두
		cyl("Tube", Vector3.new(barrelLength * 0.9, 0.95 * scale, 0.95 * scale), dark, Enum.Material.Metal, handle.CFrame * CFrame.new(0, 0.05, -(0.7 + barrelLength * 0.45)))
		local warhead = newPart("Warhead", Vector3.new(0.7, 0.7, 0.9) * scale, tier.Color, Enum.Material.Neon, tool)
		warhead.Shape = Enum.PartType.Ball
		warhead.CFrame = handle.CFrame * CFrame.new(0, 0.05, muzzleZ - 0.1)
		weld(handle, warhead)
		for i = 0, 3 do
			local fin = newPart("RocketFin", Vector3.new(0.08, 0.6, 0.5), tier.Color, tier.Material, tool)
			fin.CFrame = handle.CFrame * CFrame.new(0, 0.05, 0.9) * CFrame.Angles(0, 0, math.rad(i * 90)) * CFrame.new(0, 0.55, 0)
			weld(handle, fin)
		end
	elseif form == "Smg" then
		-- 탄창 + 짧은 개머리판
		local mag = newPart("Magazine", Vector3.new(0.35, 1.1, 0.5), dark, Enum.Material.Metal, tool)
		mag.CFrame = handle.CFrame * CFrame.new(0, -0.95, -0.35) * CFrame.Angles(math.rad(8), 0, 0)
		weld(handle, mag)
		local stock = newPart("SmgStock", Vector3.new(0.3, 0.45, 0.8), dark, Enum.Material.Metal, tool)
		stock.CFrame = handle.CFrame * CFrame.new(0, 0, 1.0)
		weld(handle, stock)
	elseif form == "Rifle" then
		-- 긴 개머리판 + 위쪽 레일
		local stock = newPart("RifleStock", Vector3.new(0.38, 0.55, 1.3), Color3.fromRGB(80, 55, 35), Enum.Material.Wood, tool)
		stock.CFrame = handle.CFrame * CFrame.new(0, -0.05, 1.25)
		weld(handle, stock)
		local rail = newPart("TopRail", Vector3.new(0.18, 0.12, 1.6), tier.Color, Enum.Material.Neon, tool)
		rail.CFrame = handle.CFrame * CFrame.new(0, 0.45, -0.3)
		weld(handle, rail)
	elseif form == "Flamer" then
		-- 연료 탱크 + 노즐
		cyl("Tank", Vector3.new(1.4, 0.7, 0.7), dark, Enum.Material.Metal, handle.CFrame * CFrame.new(0, 0.6, 0.3))
		local nozzle = cyl("Nozzle", Vector3.new(0.35, 0.8 * scale, 0.8 * scale), tier.Color, Enum.Material.Neon, handle.CFrame * CFrame.new(0, 0.05, muzzleZ + 0.1))
		nozzle.Name = "Nozzle"
	elseif form == "Rail" then
		for side = -1, 1, 2 do
			local rail = newPart("Rail", Vector3.new(0.12, 0.12, barrelLength * 1.1), tier.Color, Enum.Material.Neon, tool)
			rail.CFrame = handle.CFrame * CFrame.new(side * 0.38, 0.05, -(0.7 + barrelLength * 0.55))
			weld(handle, rail)
		end
		for i = 1, 3 do
			cyl("Ring" .. i, Vector3.new(0.12, 1.1 * scale, 1.1 * scale), Color3.new(1, 1, 1), Enum.Material.Neon, handle.CFrame * CFrame.new(0, 0.05, -(0.7 + barrelLength * i / 4)))
		end
	end

	-- 강화 단계가 오를수록 총열에 빛나는 링이 하나씩 늘어난다 (강화할 때마다 눈에 보이는 변화)
	local stage = Config.GetWeaponStage(level)
	for i = 1, math.min(stage, 8) do
		local ringPart = newPart("StageRing" .. i, Vector3.new(0.14, 0.62 * scale * thick, 0.62 * scale * thick), tier.Color, Enum.Material.Neon, tool)
		ringPart.Shape = Enum.PartType.Cylinder
		ringPart.CFrame = handle.CFrame * CFrame.new(0, 0.05, -(0.7 + barrelLength * (0.1 + 0.8 * i / 9))) * CFrame.Angles(0, math.rad(90), 0)
		weld(handle, ringPart)
	end

	local tip = Instance.new("Attachment")
	tip.Name = "Tip"
	tip.Position = Vector3.new(0, 0, -barrelLength / 2)
	tip.Parent = barrel

	local base = Instance.new("Attachment")
	base.Name = "Base"
	base.Position = Vector3.new(0, 0, barrelLength / 2)
	base.Parent = barrel

	-- 총구 화염 (발사할 때 Weapon.PlayShot 에서 잠깐 터짐)
	local muzzle = Instance.new("ParticleEmitter")
	muzzle.Name = "Muzzle"
	muzzle.Rate = 0
	muzzle.Lifetime = NumberRange.new(0.06, 0.12)
	muzzle.Speed = NumberRange.new(4, 10)
	muzzle.SpreadAngle = Vector2.new(25, 25)
	muzzle.EmissionDirection = Enum.NormalId.Front
	muzzle.LightEmission = 1
	muzzle.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9 * scale),
		NumberSequenceKeypoint.new(1, 0),
	})
	muzzle.Color = colorSeq
	muzzle.Parent = tip

	local flash = Instance.new("PointLight")
	flash.Name = "MuzzleLight"
	flash.Enabled = false
	flash.Range = 12
	flash.Brightness = 3
	flash.Color = tier.Rainbow and Color3.fromRGB(255, 255, 255) or tier.Color
	flash.Parent = tip

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
		emitter.Parent = barrel
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
		trail.Parent = barrel
	end

	if tier.Light > 0 then
		local light = Instance.new("PointLight")
		light.Range = tier.Light
		light.Brightness = 1.5
		light.Color = tier.Rainbow and Color3.fromRGB(255, 255, 255) or tier.Color
		light.Parent = barrel
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
		gui.Size = UDim2.new(0, 240, 0, 84)
		gui.StudsOffset = Vector3.new(0, 3.2, 0)
		gui.MaxDistance = 150
		gui.Parent = head

		local function addLabel(name, y, height, font)
			local label = Instance.new("TextLabel")
			label.Name = name
			label.Size = UDim2.new(1, 0, height, 0)
			label.Position = UDim2.new(0, 0, y, 0)
			label.BackgroundTransparency = 1
			label.Font = font
			label.TextScaled = true
			label.TextColor3 = Color3.new(1, 1, 1)
			label.TextStrokeTransparency = 0.3
			label.Parent = gui
		end
		addLabel("PlayerName", 0, 0.27, Enum.Font.GothamBold)
		addLabel("Power", 0.27, 0.25, Enum.Font.GothamBlack)
		addLabel("WeaponLevel", 0.52, 0.28, Enum.Font.GothamBlack)
		addLabel("Zone", 0.8, 0.2, Enum.Font.GothamMedium)
	end

	local level = player:GetAttribute("WeaponLevel") or 0
	local tier = Config.GetWeaponTier(level)
	local inParty = (player:GetAttribute("PartyId") or 0) ~= 0
	local maxZone = player:GetAttribute("MaxZone") or 0

	local title = player:GetAttribute("Title") or ""
	gui.PlayerName.Text = (inParty and "[파티] " or "") .. (title ~= "" and ("『" .. title .. "』 ") or "") .. player.DisplayName
	local prestige = player:GetAttribute("Prestige") or 0
	gui.Power.Text = string.format("%sLv.%d  ⚡ 전투력 %d", prestige > 0 and ("🌟" .. prestige .. " ") or "", player:GetAttribute("Level") or 1, player:GetAttribute("Power") or 0)
	gui.Power.TextColor3 = Color3.fromRGB(255, 225, 110)
	gui.WeaponLevel.Text = Config.FormatWeapon(level)
	gui.WeaponLevel.TextColor3 = tier.Rainbow and Color3.fromRGB(255, 120, 255) or tier.Color
	gui.Zone.Text = maxZone > 0 and string.format("🏔 필드 %d구역 돌파", maxZone) or ""
	gui.Zone.TextColor3 = Color3.fromRGB(150, 220, 255)
end

Weapon.UpdateNameplate = updateNameplate

------------------------------------------------------------
-- 진화 미리보기: 종류 x 단계별 총 모델을 ReplicatedStorage.WeaponPreviews 에 만들어 둔다
-- (클라이언트가 복제해서 강화창 / 무기 탭의 3D 미리보기에 쓴다. 이름: <종류>_<단계번호>)
------------------------------------------------------------
function Weapon.BuildPreviews()
	local rs = game:GetService("ReplicatedStorage")
	local old = rs:FindFirstChild("WeaponPreviews")
	if old then old:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = "WeaponPreviews"
	do
		for index, tier in ipairs(Config.Weapon.Tiers) do
			local tool = buildTool(tier.MinLevel, tier.Class)
			local model = Instance.new("Model")
			model.Name = "W" .. index
			for _, child in ipairs(tool:GetChildren()) do
				child.Parent = model
			end
			model.PrimaryPart = model:FindFirstChild("Handle")
			tool:Destroy()
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = true
				elseif d:IsA("PointLight") then
					d:Destroy()
				end
			end
			model.Parent = folder
		end
	end
	folder.Parent = rs
end

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

	local tool = buildTool(player:GetAttribute("WeaponLevel") or 0, player:GetAttribute("WeaponType") or "Pistol")
	humanoid:EquipTool(tool)
end

function Weapon.Refresh(player)
	Weapon.Attach(player)
	updateNameplate(player)
end

function Weapon.GetTipPosition(player)
	local character = player.Character
	local tool = character and character:FindFirstChild("Weapon")
	local barrel = tool and tool:FindFirstChild("Barrel")
	local tip = barrel and barrel:FindFirstChild("Tip")
	return tip and tip.WorldPosition or nil
end

-- 사운드 재생 (ID가 0이면 아무것도 안 함)
local function playSoundAt(parent, soundId, volume, pitch, name)
	if not soundId or soundId == 0 then return end
	local sound = Instance.new("Sound")
	sound.Name = name or "Sfx" -- 총소리는 "GunShot": 클라이언트가 이 이름을 보고 내 설정 볼륨을 적용한다
	sound.SoundId = "rbxassetid://" .. soundId
	sound.Volume = volume
	sound.PlaybackSpeed = pitch or 1
	sound.RollOffMaxDistance = 90
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, 3)
end

-- 발사 연출: 칼 휘두르기 대신 총구 화염 + 반동(총이 뒤로 살짝 밀림) + 발사음.
-- 팔은 기본 애니메이션의 "무기를 앞으로 든 자세"를 그대로 유지한다.
function Weapon.PlayShot(player)
	local character = player.Character
	local tool = character and character:FindFirstChild("Weapon")
	local barrel = tool and tool:FindFirstChild("Barrel")
	local tip = barrel and barrel:FindFirstChild("Tip")
	if not tip then return end

	local muzzle = tip:FindFirstChild("Muzzle")
	if muzzle then
		muzzle:Emit(6)
	end
	local light = tip:FindFirstChild("MuzzleLight")
	if light then
		light.Enabled = true
		task.delay(0.05, function()
			if light.Parent then
				light.Enabled = false
			end
		end)
	end

	-- 반동: 손과 총을 잇는 RightGrip의 위치를 잠깐 뒤로 밀었다가 되돌림
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	local grip = hand and hand:FindFirstChild("RightGrip")
	if grip then
		local rest = grip:GetAttribute("RestC1")
		if not rest then
			rest = grip.C1
			grip:SetAttribute("RestC1", rest)
		end
		local kick = TweenService:Create(grip, TweenInfo.new(0.04), { C1 = rest * CFrame.Angles(math.rad(6), 0, 0) * CFrame.new(0, 0, -0.35) })
		kick.Completed:Connect(function()
			if grip.Parent then
				TweenService:Create(grip, TweenInfo.new(0.1), { C1 = rest }):Play()
			end
		end)
		kick:Play()
	end

	-- 무기가 강할수록 낮고 묵직한 소리
	local era = Config.GetWeaponTier(player:GetAttribute("WeaponLevel") or 0).Era
	playSoundAt(barrel, Config.Audio.Shot, Config.Audio.ShotVolume, math.max(0.5, 1.25 - 0.08 * (era - 1)), "GunShot")
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
		return false, "마지막 무기를 최대로 강화했어요!"
	end

	-- 튜토리얼 미션 중에는 +3까지 무료 + 100% 성공
	local free = player:GetAttribute("TutorialFree") == true and level < 3
	local cost = free and 0 or Config.GetEnhanceCost(level)
	local gold = player:GetAttribute("Gold") or 0
	if gold < cost then
		return false, string.format("골드가 부족합니다. (%d 필요)", cost)
	end

	player:SetAttribute("Gold", gold - cost)

	if free or math.random() < Config.GetEnhanceChance(level) then
		-- 단계가 오르면 GameServer 가 무기 종류를 맞추고 모델도 갱신한다. 마지막 단계를 넘으면 다음 무기로 진화한다.
		player:SetAttribute("WeaponLevel", level + 1)
		Quest.Add(player, "Enhances", 1)
		local before, after = Config.GetWeaponTier(level), Config.GetWeaponTier(level + 1)
		local evolved = after.Index > before.Index
		-- 무기가 바뀌면 서버 전체에 자랑 (시대가 바뀌거나 10번째 무기마다)
		if evolved and (after.Era > before.Era or after.Index % 10 == 0) and after.Index >= 4 then
			Event.Announce(string.format("📢 %s 님의 무기가 [%s]로 진화했어요! (%d/%d)", player.DisplayName, after.Name, after.Index, Config.Weapon.WeaponCount))
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			playSoundAt(root, Config.Audio.EnhanceSuccess, 0.8, 1)
			Effects.Burst(root.Position, after.Color, evolved and 120 or 30)
			if evolved then
				Effects.FloatText(root.Position + Vector3.new(0, 5, 0), "⭐ " .. after.Name, after.Color)
			end
		end
		if evolved then
			return true, string.format("🎉 진화! %s (%d/%d)", after.Name, after.Index, Config.Weapon.WeaponCount)
		end
		return true, string.format("강화 성공! +%d/%d", Config.GetWeaponStage(level + 1), after.Steps)
	end
	return false, "강화 실패... (골드만 사라졌어요)"
end

-- (예전 무기 종류 구매 / 장착은 없어졌다: 무기는 강화 단계에 따라 자동으로 진화한다)
function Weapon.Equip()
	return false, "무기는 강화하면 자동으로 다음 무기로 진화해요!"
end

function Weapon.Buy()
	return false, "무기는 강화하면 자동으로 다음 무기로 진화해요!"
end

return Weapon
