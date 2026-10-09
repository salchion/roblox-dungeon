-- PetModel (ServerScriptService > Modules 안의 ModuleScript, 이름: PetModel)
-- 펫 외형 9종: 색을 입혀서 캐릭터 옆에 둥둥 떠 있는 작은 모델을 만든다. (MetaService 가 따라다니게 한다)
--   Build(lookKey, color) -> Model (PrimaryPart = Body)

local PetModel = {}

local Ball, Block, Cylinder = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
local Neon, Plastic, Slate = Enum.Material.Neon, Enum.Material.SmoothPlastic, Enum.Material.Slate

local function newPart(model, shape, size, color, material, transparency)
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = material
	p.Transparency = transparency or 0
	p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
	p.Parent = model
	return p
end

function PetModel.Build(look, color)
	local model = Instance.new("Model")
	model.Name = "PetModel"
	local dark = color:Lerp(Color3.new(0, 0, 0), 0.45)
	local bright = color:Lerp(Color3.new(1, 1, 1), 0.4)

	local body
	if look == "Slime" then
		body = newPart(model, Ball, Vector3.new(2.2, 1.7, 2.2), color, Plastic, 0.12)
	elseif look == "Golem" then
		body = newPart(model, Block, Vector3.new(1.9, 1.9, 1.9), color:Lerp(Color3.fromRGB(110, 105, 100), 0.6), Slate)
	elseif look == "Star" then
		body = newPart(model, Block, Vector3.new(2.4, 0.5, 0.5), color, Neon)
	elseif look == "Spirit" then
		body = newPart(model, Ball, Vector3.new(1.5, 1.5, 1.5), bright, Neon, 0.15)
	else
		body = newPart(model, Ball, Vector3.new(1.8, 1.8, 1.8), color, look == "Orb" and Neon or Plastic)
	end
	body.Name = "Body"
	body.CFrame = CFrame.new(0, 100, 0) -- MetaService 가 위치를 다시 맞춘다
	model.PrimaryPart = body

	local function attach(part, offset, rotation)
		part.CFrame = body.CFrame * CFrame.new(offset) * (rotation or CFrame.new())
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = body, part
		weld.Parent = part
		return part
	end

	local function eyes(y, z, size)
		for side = -1, 1, 2 do
			attach(newPart(model, Ball, Vector3.new(size, size, size), Color3.new(0.05, 0.05, 0.08), Plastic), Vector3.new(side * size * 1.1, y, z))
		end
	end

	if look == "Orb" then
		eyes(0.2, -0.78, 0.34)
	elseif look == "Slime" then
		eyes(0.15, -0.95, 0.36)
		attach(newPart(model, Ball, Vector3.new(0.5, 0.5, 0.5), bright, Plastic, 0.2), Vector3.new(0.5, 0.55, -0.4)) -- 반짝이는 하이라이트
	elseif look == "Fox" then
		eyes(0.2, -0.78, 0.3)
		for side = -1, 1, 2 do
			attach(newPart(model, Block, Vector3.new(0.45, 0.9, 0.3), color, Plastic), Vector3.new(side * 0.6, 1.1, 0), CFrame.Angles(0, 0, math.rad(-side * 18))) -- 뾰족한 귀
			attach(newPart(model, Block, Vector3.new(0.2, 0.5, 0.2), dark, Plastic), Vector3.new(side * 0.6, 1.0, -0.08), CFrame.Angles(0, 0, math.rad(-side * 18)))
		end
		attach(newPart(model, Ball, Vector3.new(1.0, 1.0, 1.6), bright, Plastic), Vector3.new(0, -0.2, 1.4)) -- 풍성한 꼬리
	elseif look == "Bat" then
		eyes(0.2, -0.78, 0.3)
		for side = -1, 1, 2 do
			attach(newPart(model, Block, Vector3.new(1.8, 0.1, 1.0), dark, Plastic, 0.1), Vector3.new(side * 1.5, 0.3, 0.2), CFrame.Angles(0, 0, math.rad(side * 15)))
			attach(newPart(model, Block, Vector3.new(0.3, 0.6, 0.3), dark, Plastic), Vector3.new(side * 0.5, 1.0, 0))
		end
	elseif look == "Golem" then
		for side = -1, 1, 2 do
			attach(newPart(model, Block, Vector3.new(0.45, 1.3, 0.45), color:Lerp(Color3.fromRGB(110, 105, 100), 0.4), Slate), Vector3.new(side * 1.2, -0.2, 0))
			attach(newPart(model, Block, Vector3.new(0.5, 0.15, 0.1), Color3.fromRGB(255, 170, 70), Neon), Vector3.new(side * 0.4, 0.3, -0.96))
		end
		attach(newPart(model, Block, Vector3.new(0.5, 0.5, 0.1), Color3.fromRGB(255, 150, 60), Neon), Vector3.new(0, -0.3, -0.96))
	elseif look == "Spirit" then
		eyes(0.1, -0.7, 0.26)
		local halo = newPart(model, Cylinder, Vector3.new(0.1, 1.3, 1.3), color, Neon, 0.1)
		attach(halo, Vector3.new(0, 1.2, 0), CFrame.Angles(0, 0, math.rad(90)))
		for side = -1, 1, 2 do
			attach(newPart(model, Block, Vector3.new(1.3, 0.05, 0.8), color, Neon, 0.45), Vector3.new(side * 1.1, 0.4, 0.3), CFrame.Angles(0, 0, math.rad(side * 20)))
		end
	elseif look == "Dragon" then
		eyes(0.25, -0.78, 0.3)
		for side = -1, 1, 2 do
			attach(newPart(model, Block, Vector3.new(0.2, 0.7, 0.2), Color3.fromRGB(235, 225, 200), Plastic), Vector3.new(side * 0.45, 1.0, -0.1), CFrame.Angles(math.rad(-15), 0, math.rad(-side * 14))) -- 뿔
			attach(newPart(model, Block, Vector3.new(1.5, 0.08, 1.1), dark, Plastic, 0.1), Vector3.new(side * 1.4, 0.4, 0.4), CFrame.Angles(0, 0, math.rad(side * 22))) -- 날개
		end
		attach(newPart(model, Block, Vector3.new(0.4, 0.4, 1.4), color, Plastic), Vector3.new(0, -0.3, 1.3)) -- 꼬리
	elseif look == "Phoenix" then
		eyes(0.25, -0.78, 0.28)
		for side = -1, 1, 2 do
			attach(newPart(model, Block, Vector3.new(2.2, 0.06, 1.3), Color3.fromRGB(255, 150, 50), Neon, 0.3), Vector3.new(side * 1.8, 0.6, 0.3), CFrame.Angles(0, 0, math.rad(side * 28)))
		end
		for i = -1, 1 do
			attach(newPart(model, Block, Vector3.new(0.2, 0.08, 1.8), Color3.fromRGB(255, 110, 40), Neon, 0.2), Vector3.new(i * 0.35, -0.2, 1.5), CFrame.Angles(0, math.rad(i * 15), 0))
		end
	elseif look == "Star" then
		attach(newPart(model, Block, Vector3.new(2.4, 0.5, 0.5), color, Neon), Vector3.new(0, 0, 0), CFrame.Angles(0, 0, math.rad(60)))
		attach(newPart(model, Block, Vector3.new(2.4, 0.5, 0.5), color, Neon), Vector3.new(0, 0, 0), CFrame.Angles(0, 0, math.rad(120)))
		attach(newPart(model, Ball, Vector3.new(0.9, 0.9, 0.9), bright, Neon), Vector3.new(0, 0, 0))
	end

	local light = Instance.new("PointLight")
	light.Range = 10
	light.Brightness = 1.2
	light.Color = color
	light.Parent = body
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Rate = 10
	sparkle.Lifetime = NumberRange.new(0.5, 1)
	sparkle.Speed = NumberRange.new(0.5, 1.5)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.LightEmission = 1
	sparkle.Color = ColorSequence.new(color)
	sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	sparkle.Parent = body
	return model
end

return PetModel
