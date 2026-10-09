-- Effects (ServerScriptService > Modules 안의 ModuleScript, 이름: Effects)
-- 총알 궤적, 데미지 숫자, 강화 버스트 같은 짧은 시각 효과

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Effects = {}

function Effects.Tracer(from, to, color, thickness)
	local distance = (to - from).Magnitude
	if distance < 0.1 then return end
	local beam = Instance.new("Part")
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.Material = Enum.Material.Neon
	beam.Color = color or Color3.fromRGB(255, 255, 150)
	beam.Size = Vector3.new(thickness or 0.15, thickness or 0.15, distance)
	beam.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -distance / 2)
	beam.Parent = workspace
	Debris:AddItem(beam, 0.08)
end

-- 투사체 모양 만들기 (부모는 호출한 쪽이 정한다). style: Orb(구) / Spear(긴 창) / Dart(가는 침) / Shard(마름모 파편)
function Effects.MakeProjectile(origin, direction, size, color, style)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.Neon
	part.Color = color or Color3.fromRGB(255, 120, 30)
	local look = CFrame.lookAt(origin, origin + direction.Unit)
	if style == "Spear" then
		part.Size = Vector3.new(size * 0.45, size * 0.45, size * 3.6)
		part.CFrame = look
		part.Color = part.Color:Lerp(Color3.new(1, 1, 1), 0.35)
	elseif style == "Dart" then
		part.Size = Vector3.new(size * 0.3, size * 0.3, size * 2.4)
		part.CFrame = look
	elseif style == "Shard" then
		part.Size = Vector3.new(size * 0.9, size * 0.9, size * 1.9)
		part.CFrame = look * CFrame.Angles(0, 0, math.rad(45))
	else
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(size, size, size)
		part.Position = origin
	end
	local light = Instance.new("PointLight")
	light.Range = 8
	light.Brightness = 1.2
	light.Color = part.Color
	light.Parent = part
	return part
end

-- 거대한 군주 외형(뿔 / 날개 / 꼬리 / 눈). 던전 보스와 필드 구역 보스가 같이 쓴다
function Effects.DecorateBoss(part, size, glow)
	local dark = part.Color:Lerp(Color3.new(0, 0, 0), 0.55)
	part.Material = Enum.Material.Slate
	part.Color = dark
	local function piece(shape, sx, sy, sz, x, y, z, color, material, rx, ry, rz, transparency)
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, false, true
		p.Shape = shape
		p.Size = Vector3.new(math.max(0.1, sx), math.max(0.1, sy), math.max(0.1, sz))
		p.Color = color
		p.Material = material
		p.Transparency = transparency or 0
		p.CFrame = part.CFrame * CFrame.new(x, y, z) * CFrame.Angles(math.rad(rx or 0), math.rad(ry or 0), math.rad(rz or 0))
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = part
		weld.Part1 = p
		weld.Parent = p
		p.Parent = part
		return p
	end
	local S = size
	local Ball, Block = Enum.PartType.Ball, Enum.PartType.Block
	local Neon, Metal, Slate = Enum.Material.Neon, Enum.Material.Metal, Enum.Material.Slate
	local bone = Color3.fromRGB(215, 205, 185)
	-- 눈 / 가슴 룬 / 이마의 보석
	for _, side in ipairs({ -1, 1 }) do
		piece(Ball, S * 0.13, S * 0.13, S * 0.13, side * S * 0.2, S * 0.18, -S * 0.45, Color3.fromRGB(255, 240, 120), Neon)
		-- 뿔 (휘어진 두 마디)
		piece(Block, S * 0.1, S * 0.42, S * 0.1, side * S * 0.28, S * 0.52, -S * 0.08, bone, Slate, 0, 0, side * -22)
		piece(Block, S * 0.08, S * 0.3, S * 0.08, side * S * 0.42, S * 0.8, -S * 0.12, bone, Slate, -15, 0, side * -48)
		-- 어깨 갑옷
		piece(Ball, S * 0.34, S * 0.34, S * 0.34, side * S * 0.52, S * 0.2, 0, dark:Lerp(Color3.new(1, 1, 1), 0.12), Metal)
		-- 날개 (뼈대 + 빛나는 막)
		piece(Block, S * 1.0, S * 0.07, S * 0.09, side * S * 0.95, S * 0.52, S * 0.28, bone, Slate, 0, 0, side * 28)
		piece(Block, S * 0.95, S * 0.04, S * 0.65, side * S * 0.92, S * 0.4, S * 0.4, glow, Neon, 0, 0, side * 28, 0.4)
		piece(Block, S * 0.7, S * 0.04, S * 0.5, side * S * 0.78, S * 0.14, S * 0.62, glow, Neon, 0, 0, side * 20, 0.5)
	end
	piece(Ball, S * 0.24, S * 0.24, S * 0.24, 0, S * 0.02, -S * 0.5, glow, Neon)
	piece(Ball, S * 0.12, S * 0.12, S * 0.12, 0, S * 0.36, -S * 0.42, Color3.fromRGB(255, 70, 90), Neon)
	-- 등 가시
	for i = 0, 4 do
		piece(Block, S * 0.09, S * (0.34 - i * 0.04), S * 0.09, 0, S * (0.5 - i * 0.07), S * (0.05 + i * 0.12), bone, Slate, 25 + i * 8, 0, 0)
	end
	-- 꼬리 (뒤쪽으로 점점 가늘어지는 구슬 + 끝의 불꽃)
	for i = 1, 4 do
		piece(Ball, S * (0.32 - i * 0.05), S * (0.32 - i * 0.05), S * (0.32 - i * 0.05), 0, -S * 0.1 * i, S * (0.45 + i * 0.22), dark, Slate)
	end
	local tip = piece(Ball, S * 0.22, S * 0.22, S * 0.22, 0, -S * 0.5, S * 1.45, glow, Neon)
	local fire = Instance.new("ParticleEmitter")
	fire.Rate = 40
	fire.Lifetime = NumberRange.new(0.4, 0.9)
	fire.Speed = NumberRange.new(3, 8)
	fire.SpreadAngle = Vector2.new(35, 35)
	fire.LightEmission = 1
	fire.Color = ColorSequence.new(glow, Color3.fromRGB(255, 240, 160))
	fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, S * 0.12), NumberSequenceKeypoint.new(1, 0) })
	fire.Parent = tip
	local halo = Instance.new("PointLight")
	halo.Range = S * 1.6
	halo.Brightness = 2
	halo.Color = glow
	halo.Parent = part
end

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 60)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 220, 60)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(80, 255, 100)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(60, 220, 255)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(90, 90, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 255)),
})
local FIRE = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 120)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 50, 20)),
})

-- 무기 등급별로 모양이 다른 발사체가 날아가는 연출 (판정은 이미 서버에서 끝난 상태, 보이기만 하는 것)
-- shot = Config.Weapon.Tiers[n].Shot
-- 무기 종류별 탄 모양: 이름과 어울리게 (화염방사기는 불길, 레일건은 가늘고 긴 빛줄기, 로켓은 꼬리 달린 로켓 ...)
local CLASS_LOOK = {
	Flamer = { Style = "Fire", SizeMul = 2.0, Color = Color3.fromRGB(255, 150, 50), Transparency = 0.4, Impact = 2 },
	Rocket = { Style = "Rocket", Length = 4.5, Impact = 20 },
	Cannon = { Style = "Orb", SizeMul = 1.25 },
	Rail = { Style = "Bolt", Length = 16, SizeMul = 0.7, Color = Color3.fromRGB(150, 230, 255), Impact = 8 },
	Sniper = { Style = "Bolt", Length = 8, SizeMul = 0.8, Impact = 6 },
	Rifle = { Style = "Bolt", Length = 3.5 },
	Smg = { Style = "Bolt", Length = 2 },
	Shotgun = { Style = "Ball", SizeMul = 0.9 },
}

function Effects.Shot(from, to, shot, color, rainbow, class, era)
	local distance = (to - from).Magnitude
	if distance < 0.5 then return end
	era = era or 1
	local eraStyle = shot.Style -- 시대(등급)가 정하는 탄의 "성격": 불꽃 / 얼음 / 번개 / 암흑 / 용 / 무지개 ... (모양은 무기 종류가 정한다)
	local look = class and CLASS_LOOK[class]
	if look then
		shot = table.clone(shot)
		shot.Style = look.Style or shot.Style
		shot.Length = look.Length or shot.Length or 3
		shot.Size *= look.SizeMul or 1
		shot.Impact = look.Impact or shot.Impact
		color = look.Color or color
	end

	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.Neon
	part.Color = color
	if look and look.Transparency then part.Transparency = look.Transparency end
	if shot.Style == "Bolt" or shot.Style == "Rocket" then
		part.Size = Vector3.new(shot.Size, shot.Size, shot.Length) -- 길쭉한 탄
	else
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(shot.Size, shot.Size, shot.Size)
	end
	part.CFrame = CFrame.lookAt(from, to)
	part.Parent = workspace

	local colorSeq = rainbow and RAINBOW or ColorSequence.new(color)
	if shot.Style == "Fire" or shot.Style == "Rocket" or eraStyle == "Fire" or eraStyle == "Rocket" then
		colorSeq = rainbow and RAINBOW or FIRE
	end

	-- 꼬리(궤적)
	local trailWidth = shot.Size * (1 + 0.12 * era) -- 시대가 높을수록 꼬리가 굵고 길다
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, trailWidth / 2, 0)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -trailWidth / 2, 0)
	a1.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = math.min(0.55, (shot.Style == "Ball" and 0.08 or 0.14) + 0.03 * era)
	trail.Color = colorSeq
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Parent = part

	-- 등급별 입자: 불꽃은 불길, 마법은 반짝이, 무지개는 무지개 가루
	local rate = ({ Orb = 40, Cannon = 25, Fire = 90, Rocket = 110, Rainbow = 80 })[eraStyle] or ({ Orb = 40, Cannon = 25, Fire = 90, Rocket = 110 })[shot.Style]
	if not rate and era >= 2 then
		rate = 6 + era * 4 -- 시대가 올라가면 평범한 탄에도 점점 더 많은 반짝임이 붙는다
	end
	if rate then
		rate = rate * (0.6 + 0.1 * era)
		local emitter = Instance.new("ParticleEmitter")
		emitter.Rate = rate
		emitter.Lifetime = NumberRange.new(0.3, 0.6)
		emitter.Speed = NumberRange.new(1, (shot.Style == "Fire" or shot.Style == "Rocket") and 6 or 3)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, shot.Size * 0.6), NumberSequenceKeypoint.new(1, 0) })
		emitter.LightEmission = 1
		emitter.Color = colorSeq
		emitter.Parent = part
	end

	if era >= 3 then -- 3시대부터 탄이 스스로 빛난다 (밤에도 눈에 띈다)
		local light = Instance.new("PointLight")
		light.Range = 5 + era * 2
		light.Brightness = 0.7 + 0.1 * era
		light.Color = color
		light.Parent = part
	end
	if era >= 2 then -- 발사하는 순간 총구에서 시대 색의 불꽃이 터진다 (높은 시대일수록 크게)
		Effects.Burst(from, color, 2 + era)
	end

	local duration = math.clamp(distance / shot.Speed, 0.03, 1.2)
	local tween = TweenService:Create(part, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
		CFrame = CFrame.lookAt(to, to + (to - from)),
	})
	tween.Completed:Connect(function()
		part.Transparency = 1
		for _, child in ipairs(part:GetChildren()) do
			if child:IsA("ParticleEmitter") then
				child.Enabled = false
			end
		end
		if shot.Impact > 0 then
			Effects.Burst(to, color, shot.Impact)
		end
		Debris:AddItem(part, 0.5)
	end)
	tween:Play()
end

-- 타격감: 맞은 몬스터가 하얗게 번쩍이고, 쏜 사람에게는 적중 표시(Hit)를 보낸다 (치명타 / 처치는 더 크게)
function Effects.Hit(player, part, isCrit, killed)
	if player and player.Parent then
		local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
		Remotes.Hit:FireClient(player, isCrit == true, killed == true)
	end
	if killed or not part or not part.Parent then return end
	local original = part.Color
	if original == Color3.new(1, 1, 1) then return end
	part.Color = Color3.new(1, 1, 1)
	task.delay(0.06, function()
		if part.Parent and part.Color == Color3.new(1, 1, 1) then
			part.Color = original
		end
	end)
end

-- 소리 한 번 재생 (soundId 가 0 이면 아무것도 안 함)
function Effects.PlaySound(parent, soundId, volume, pitch)
	if not soundId or soundId == 0 then return end
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. soundId
	sound.Volume = volume or 0.8
	sound.PlaybackSpeed = pitch or 1
	sound.RollOffMaxDistance = 90
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, 5)
end

-- 임의 색의 떠오르는 글자 (골드 획득 등)
function Effects.FloatText(position, text, color)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = position
	anchor.Parent = workspace

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 140, 0, 36)
	gui.AlwaysOnTop = true
	gui.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextStrokeTransparency = 0
	label.Text = text
	label.TextColor3 = color
	label.Parent = gui

	TweenService:Create(anchor, TweenInfo.new(0.7), { Position = position + Vector3.new(0, 3, 0) }):Play()
	Debris:AddItem(anchor, 0.7)
end

function Effects.DamageNumber(position, amount, isCrit)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = position
	anchor.Parent = workspace

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 90, 0, 40)
	gui.AlwaysOnTop = true
	gui.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextStrokeTransparency = 0
	label.Text = isCrit and (amount .. "!") or tostring(amount)
	label.TextColor3 = isCrit and Color3.fromRGB(255, 220, 60) or Color3.new(1, 1, 1)
	label.Parent = gui

	Debris:AddItem(anchor, 0.5)
end

-- 강화 성공 시 캐릭터 주변에 터지는 빛 입자
function Effects.Burst(position, color, count)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Position = position
	anchor.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Speed = NumberRange.new(12, 24)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.LightEmission = 1
	emitter.Color = ColorSequence.new(color)
	emitter.Parent = anchor
	emitter:Emit(count or 40)

	Debris:AddItem(anchor, 1.5)
end

-- 약점 구슬 표시 / 숨김 (약점이 "노출"되는 동안에는 구슬이 사라진다)
function Effects.SetWeakVisible(orb, visible)
	if not orb then return end
	for _, item in ipairs(orb:GetDescendants()) do
		if item:IsA("BasePart") then
			if item:GetAttribute("T0") == nil then item:SetAttribute("T0", item.Transparency) end
			item.Transparency = visible and item:GetAttribute("T0") or 1
		elseif item:IsA("BillboardGui") or item:IsA("PointLight") or item:IsA("ParticleEmitter") then
			item.Enabled = visible
		end
	end
	if orb:IsA("BasePart") then
		if orb:GetAttribute("T0") == nil then orb:SetAttribute("T0", orb.Transparency) end
		orb.Transparency = visible and orb:GetAttribute("T0") or 1
		orb.CanQuery = visible -- 숨은 동안에는 조준 / 판정에 잡히지 않는다
	end
end

-- 약점 노출: duration 초 동안 보스가 받는 피해가 x3 (data.ExposedUntil 을 각 서비스의 피해 계산이 읽는다). 보스에 노란 윤곽 + 글자.
function Effects.ExposeBoss(part, data, duration)
	data.ExposedUntil = os.clock() + duration
	if data.WeakPart then
		data.WeakHidden = true
		Effects.SetWeakVisible(data.WeakPart, false)
	end
	local outline = Instance.new("Highlight")
	outline.Name = "ExposedOutline"
	outline.Adornee = part
	outline.FillColor = Color3.fromRGB(255, 220, 60)
	outline.FillTransparency = 0.7
	outline.OutlineColor = Color3.fromRGB(255, 240, 120)
	outline.OutlineTransparency = 0
	outline.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	outline.Parent = part
	Effects.FloatText(part.Position + Vector3.new(0, part.Size.Y / 2 + 6, 0), string.format("💥 약점 노출! %d초간 피해 x3", duration), Color3.fromRGB(255, 240, 90))
	task.delay(duration, function()
		if outline.Parent then outline:Destroy() end
		if data.WeakPart and data.WeakPart.Parent then
			data.WeakHidden = nil
			Effects.SetWeakVisible(data.WeakPart, true)
		end
	end)
end

return Effects
