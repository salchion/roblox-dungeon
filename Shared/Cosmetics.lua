-- Cosmetics (ReplicatedStorage 안의 ModuleScript, 이름: Cosmetics)
-- 꾸미기(오라 / 깃발 / 탈것) 외형을 만든다. 서버(실제 장착)와 클라이언트(상점 미리보기)가 같은 함수를 써서 똑같이 보인다.
--   Cosmetics.Build(kind, key, character, preview) -> 만든 Folder   kind: "Aura" | "Banner" | "Mount"
--   Cosmetics.Clear(character, kind, preview)                          기존 것 지우기
-- 능력치는 전혀 없고 보이기만 한다 (다른 플레이어에게도 보임).

local Config = require(script.Parent:WaitForChild("Config"))

local Cosmetics = {}

local function folderName(kind, preview)
	return (preview and "CosPreview_" or "Cos_") .. kind
end

function Cosmetics.Clear(character, kind, preview)
	local old = character and character:FindFirstChild(folderName(kind, preview))
	if old then old:Destroy() end
end

local function newPart(parent, root, name, size, offset, color, material, shape)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	if shape then part.Shape = shape end
	part.CanCollide, part.CanQuery, part.CanTouch, part.Massless = false, false, false, true
	part.CFrame = root.CFrame * offset
	part.Parent = parent
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
	return part
end

local function sparkle(parent, color, rate, speed, size)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = rate
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Speed = NumberRange.new(speed * 0.5, speed)
	emitter.SpreadAngle = Vector2.new(40, 40)
	emitter.LightEmission = 1
	emitter.Color = ColorSequence.new(color)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	emitter.Parent = parent
	return emitter
end

local builders = {}

-- 오라: 몸 주위로 솟아오르는 빛 + 발밑에 퍼지는 고리 + 은은한 조명
builders.Aura = function(folder, root, key)
	local aura = Config.Auras[key]
	local base = newPart(folder, root, "AuraCore", Vector3.new(0.4, 0.4, 0.4), CFrame.new(0, 0, 0), aura.Color, Enum.Material.Neon)
	base.Transparency = 1
	local up = sparkle(base, aura.Color, 22, 4, 0.8)
	up.Shape = Enum.ParticleEmitterShape.Cylinder
	up.EmissionDirection = Enum.NormalId.Top
	up.SpreadAngle = Vector2.new(20, 20)
	up.Lifetime = NumberRange.new(1.2, 1.8)
	local ring = newPart(folder, root, "AuraRing", Vector3.new(0.2, 7, 7), CFrame.new(0, -3, 0) * CFrame.Angles(0, 0, math.rad(90)), aura.Color, Enum.Material.Neon, Enum.PartType.Cylinder)
	ring.Transparency = 0.55
	local light = Instance.new("PointLight")
	light.Range = 14
	light.Brightness = 1
	light.Color = aura.Color
	light.Parent = base
end

-- 깃발: 등 뒤에 꽂은 장대 + 천 + 네온 테두리 + 문장
builders.Banner = function(folder, root, key)
	local banner = Config.Banners[key]
	local color = banner.Color
	local back = CFrame.new(0, 1.6, 1.15)
	newPart(folder, root, "Pole", Vector3.new(0.25, 7.5, 0.25), back * CFrame.new(0, 1.2, 0), Color3.fromRGB(70, 60, 55), Enum.Material.Metal)
	newPart(folder, root, "PoleTip", Vector3.new(0.7, 0.7, 0.7), back * CFrame.new(0, 5.1, 0), color:Lerp(Color3.new(1, 1, 1), 0.4), Enum.Material.Neon, Enum.PartType.Ball)
	local cloth = newPart(folder, root, "Cloth", Vector3.new(0.12, 3.6, 2.6), back * CFrame.new(0, 3.0, 1.45), color, Enum.Material.Fabric)
	newPart(folder, root, "TrimTop", Vector3.new(0.2, 0.25, 2.7), back * CFrame.new(0, 4.85, 1.45), color:Lerp(Color3.new(1, 1, 1), 0.5), Enum.Material.Neon)
	newPart(folder, root, "TrimBottom", Vector3.new(0.2, 0.25, 2.7), back * CFrame.new(0, 1.2, 1.45), color:Lerp(Color3.new(1, 1, 1), 0.5), Enum.Material.Neon)
	local emblem = newPart(folder, root, "Emblem", Vector3.new(0.2, 1.3, 1.3), back * CFrame.new(0, 3.1, 1.45) * CFrame.Angles(math.rad(45), 0, 0), Color3.new(1, 1, 1), Enum.Material.Neon)
	emblem.Transparency = 0.1
	if banner.Sparks then
		sparkle(cloth, banner.Color:Lerp(Color3.new(1, 1, 1), 0.3), 14, 3, 0.5)
	end
end

-- 탈것: 발밑에 떠 있는 탈것 (걷는 건 그대로, 보이는 것만 바뀐다)
builders.Mount = function(folder, root, key)
	local mount = Config.Mounts[key]
	local color = mount.Color
	local foot = CFrame.new(0, -3.15, 0)
	if mount.Style == "Board" then
		newPart(folder, root, "Deck", Vector3.new(2.6, 0.4, 6), foot, Color3.fromRGB(35, 38, 52), Enum.Material.Metal)
		local glow = newPart(folder, root, "Glow", Vector3.new(2.2, 0.2, 5.4), foot * CFrame.new(0, -0.3, 0), color, Enum.Material.Neon)
		sparkle(glow, color, 30, 6, 0.7).EmissionDirection = Enum.NormalId.Bottom
		local light = Instance.new("PointLight")
		light.Range = 14
		light.Color = color
		light.Parent = glow
	elseif mount.Style == "Cloud" then
		for index, data in ipairs({ { 0, 0, 0, 3.2 }, { 1.8, -0.2, 0.6, 2.4 }, { -1.8, -0.2, 0.4, 2.5 }, { 0.6, -0.3, -1.6, 2.2 }, { -0.8, -0.3, 1.7, 2.1 } }) do
			local puff = newPart(folder, root, "Puff" .. index, Vector3.new(data[4], data[4] * 0.55, data[4]), foot * CFrame.new(data[1], data[2] - 0.2, data[3]), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
			puff.Transparency = 0.15
		end
		sparkle(folder:FindFirstChild("Puff1"), color, 12, 2, 0.6).EmissionDirection = Enum.NormalId.Bottom
	elseif mount.Style == "Carpet" then
		newPart(folder, root, "Carpet", Vector3.new(4.2, 0.25, 6), foot, color, Enum.Material.Fabric)
		newPart(folder, root, "Border", Vector3.new(4.5, 0.2, 6.3), foot * CFrame.new(0, -0.08, 0), Color3.fromRGB(255, 215, 90), Enum.Material.Neon)
		for _, z in ipairs({ -3.3, 3.3 }) do
			for x = -1.8, 1.8, 0.9 do
				newPart(folder, root, "Tassel", Vector3.new(0.25, 0.7, 0.25), foot * CFrame.new(x, -0.3, z), Color3.fromRGB(255, 215, 90), Enum.Material.Neon)
			end
		end
		sparkle(folder:FindFirstChild("Carpet"), Color3.fromRGB(255, 230, 140), 16, 3, 0.5).EmissionDirection = Enum.NormalId.Bottom
	else -- Phoenix: 불꽃 날개 달린 불사조
		newPart(folder, root, "Body", Vector3.new(2, 1.2, 4.2), foot * CFrame.new(0, 0.1, 0), color, Enum.Material.Neon, Enum.PartType.Ball)
		for _, side in ipairs({ -1, 1 }) do
			newPart(folder, root, "Wing", Vector3.new(5, 0.2, 2.6), foot * CFrame.new(side * 3.3, 0.5, 0.4) * CFrame.Angles(0, 0, math.rad(side * -18)), color:Lerp(Color3.fromRGB(255, 220, 90), 0.4), Enum.Material.Neon).Transparency = 0.2
		end
		local tail = newPart(folder, root, "Tail", Vector3.new(0.8, 0.4, 3.2), foot * CFrame.new(0, 0.2, 3.2), Color3.fromRGB(255, 200, 80), Enum.Material.Neon)
		sparkle(tail, Color3.fromRGB(255, 150, 50), 40, 5, 1.1)
		local light = Instance.new("PointLight")
		light.Range = 16
		light.Color = color
		light.Parent = tail
	end
end

function Cosmetics.Build(kind, key, character, preview)
	if not character then return nil end
	local root = character:FindFirstChild("HumanoidRootPart")
	local builder = builders[kind]
	if not root or not builder then return nil end
	Cosmetics.Clear(character, kind, preview)
	local folder = Instance.new("Folder")
	folder.Name = folderName(kind, preview)
	folder.Parent = character
	local ok, err = pcall(builder, folder, root, key)
	if not ok then
		warn("[Cosmetics] " .. tostring(err))
		folder:Destroy()
		return nil
	end
	return folder
end

return Cosmetics
