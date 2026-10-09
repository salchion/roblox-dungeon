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

return Effects
