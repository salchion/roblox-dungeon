-- Effects (ServerScriptService > Modules 안의 ModuleScript, 이름: Effects)
-- 총알 궤적, 데미지 숫자, 강화 버스트 같은 짧은 시각 효과

local Debris = game:GetService("Debris")

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
