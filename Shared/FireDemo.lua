-- FireDemo (ReplicatedStorage 안의 ModuleScript, 이름: FireDemo)
-- 무기 탭의 발사 시연. PlayerClient 가 너무 커져서 따로 뺐다. require(FireDemo)(settings, kit) 로 settings.BuildFireDemo 를 등록한다.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Config = require(ReplicatedStorage:WaitForChild("Config"))

return function(settings, kit)
	local create = kit.create
do
	local SHOT_SPEED_SCALE = 0.25
	settings.BuildFireDemo = function(viewport, shown, classInfo)
		local cam = create("Camera", { FieldOfView = 40 }, viewport)
		viewport.CurrentCamera = cam
		local previews = ReplicatedStorage:FindFirstChild("WeaponPreviews")
		local source = previews and previews:FindFirstChild("W" .. shown.Index)
		if not source then return end

		-- 무대: 바닥 + 슬라임 표적
		local function stagePart(shape, size, position, color, material)
			local part = Instance.new("Part")
			part.Anchored, part.CanCollide, part.CanQuery = true, false, false
			part.Shape = shape
			part.Size = size
			part.Position = position
			part.Color = color
			part.Material = material or Enum.Material.SmoothPlastic
			part.Parent = viewport
			return part
		end
		stagePart(Enum.PartType.Block, Vector3.new(60, 0.4, 24), Vector3.new(8, -2.3, 0), Color3.fromRGB(46, 50, 70), Enum.Material.Slate)
		local targetX = 16
		local slimeColor = Color3.fromRGB(110, 220, 120)
		local slime = stagePart(Enum.PartType.Ball, Vector3.new(4, 3.4, 4), Vector3.new(targetX, -0.4, 0), slimeColor)
		for _, z in ipairs({ -0.7, 0.7 }) do
			stagePart(Enum.PartType.Ball, Vector3.new(0.5, 0.6, 0.5), Vector3.new(targetX - 1.8, 0.2, z), Color3.new(0, 0, 0))
		end

		-- 총: 총구가 +X 를 보게 눕히고 5 스터드 길이로 맞춘다
		local model = source:Clone()
		model.Parent = viewport
		local _, size0 = model:GetBoundingBox()
		model:ScaleTo(5 / math.max(size0.X, size0.Y, size0.Z))
		local pivotBase = CFrame.lookAt(Vector3.new(0, 0, 0), Vector3.new(1, 0, 0))
		model:PivotTo(pivotBase)
		local gcf, gsize = model:GetBoundingBox()
		local muzzle = Vector3.new(gcf.Position.X + gsize.X / 2, gcf.Position.Y, 0)
		cam.CFrame = CFrame.lookAt(Vector3.new(7.8, 1.6, 22), Vector3.new(7.8, -0.2, 0))

		local shot = shown.Shot or { Style = "Ball", Size = 0.6, Speed = 260 }
		-- 실제 전투와 같은 무기 종류별 탄 모양 (서버 Effects.Shot 의 CLASS_LOOK 과 맞춘다)
		local CLASS_LOOK = {
			Flamer = { Style = "Fire", SizeMul = 2.0, Color = Color3.fromRGB(255, 150, 50), Transparency = 0.4 },
			Rocket = { Style = "Rocket", Length = 4.5 },
			Cannon = { Style = "Orb", SizeMul = 1.25 },
			Rail = { Style = "Bolt", Length = 16, SizeMul = 0.7, Color = Color3.fromRGB(150, 230, 255) },
			Sniper = { Style = "Bolt", Length = 8, SizeMul = 0.8 },
			Rifle = { Style = "Bolt", Length = 3.5 },
			Smg = { Style = "Bolt", Length = 2 },
			Shotgun = { Style = "Ball", SizeMul = 0.9 },
		}
		local look = CLASS_LOOK[shown.Class]
		local shownColor = shown.Color
		if look then
			shot = table.clone(shot)
			shot.Style = look.Style or shot.Style
			shot.Length = look.Length or shot.Length or 3
			shot.Size *= look.SizeMul or 1
			shownColor = look.Color or shownColor
		end
		local style = shot.Style
		local bolt = style == "Bolt" or style == "Rocket"
		local speed = math.clamp(shot.Speed * SHOT_SPEED_SCALE, 34, 100)
		local thick = math.clamp(shot.Size * 0.5, 0.3, 1.6)
		local pellets = math.min(classInfo.Pellets, 5)
		local period = math.clamp(classInfo.Cooldown * 0.9, 0.36, 1.3)
		local flamer = style == "Fire"

		local bullets, fx = {}, {}
		local function spawnBullet(offsetAngle, delay)
			local part = Instance.new("Part")
			part.Anchored, part.CanCollide, part.CanQuery = true, false, false
			part.Material = Enum.Material.Neon
			part.Color = shownColor
			part.Transparency = 1
			part.Shape = bolt and Enum.PartType.Block or Enum.PartType.Ball
			part.Size = bolt and Vector3.new(math.clamp((shot.Length or 3) * 0.35, 1, 5.6), thick * 0.5, thick * 0.5) or Vector3.new(thick, thick, thick)
			part.Transparency = 1
			part.Parent = viewport
			local dir = Vector3.new(math.cos(offsetAngle), math.sin(offsetAngle) * 0.5, math.sin(offsetAngle) * 0.9).Unit
			table.insert(bullets, { Part = part, Dir = dir, Pos = muzzle, Delay = delay or 0 })
		end
		local function burst(position, count, color, speedMax)
			for _ = 1, count do
				local p = Instance.new("Part")
				p.Anchored, p.CanCollide, p.CanQuery = true, false, false
				p.Material = Enum.Material.Neon
				p.Color = color
				p.Size = Vector3.new(0.35, 0.35, 0.35)
				p.Position = position
				p.Parent = viewport
				local v = Vector3.new(math.random() * 2 - 1, math.random() * 1.6 - 0.2, math.random() * 2 - 1).Unit * (speedMax * (0.4 + math.random() * 0.6))
				table.insert(fx, { Part = p, Vel = v, Life = 0.45, Max = 0.45 })
			end
		end
		local function splashRing(position, radius, color)
			local p = Instance.new("Part")
			p.Anchored, p.CanCollide, p.CanQuery = true, false, false
			p.Shape = Enum.PartType.Ball
			p.Material = Enum.Material.Neon
			p.Color = color
			p.Transparency = 0.4
			p.Size = Vector3.new(1, 1, 1)
			p.Position = position
			p.Parent = viewport
			table.insert(fx, { Part = p, Vel = Vector3.zero, Life = 0.4, Max = 0.4, Grow = radius * 2 })
		end

		local clock = settings.DemoClock or 0
		local lastShot = -10
		local hitFlash = 0
		local recoil = 0
		local connection
		connection = RunService.RenderStepped:Connect(function(dt)
			if not viewport:IsDescendantOf(game) then
				connection:Disconnect()
				return
			end
			clock += dt
			settings.DemoClock = clock
			-- 발사
			if clock - lastShot >= period then
				lastShot = clock
				recoil = 1
				local flash = stagePart(Enum.PartType.Ball, Vector3.new(1.3, 1.3, 1.3), muzzle + Vector3.new(0.4, 0, 0), Color3.fromRGB(255, 240, 170), Enum.Material.Neon)
				table.insert(fx, { Part = flash, Vel = Vector3.zero, Life = 0.08, Max = 0.08 })
				if flamer then
					for i = 0, 4 do spawnBullet(0, i * 0.05) end
				elseif pellets > 1 then
					for i = 1, pellets do spawnBullet(((i - 1) / (pellets - 1) - 0.5) * 0.28, 0) end
				else
					spawnBullet(0, 0)
				end
			end
			-- 반동
			recoil = math.max(0, recoil - dt * 6)
			model:PivotTo(pivotBase * CFrame.new(0, 0, recoil * 0.35))
			-- 탄 이동 / 명중
			for i = #bullets, 1, -1 do
				local b = bullets[i]
				if b.Delay > 0 then
					b.Delay -= dt
				else
					b.Part.Transparency = 0
					b.Pos += b.Dir * speed * dt
					local color = style == "Rainbow" and Color3.fromHSV((clock * 1.4) % 1, 0.8, 1) or (flamer and Color3.fromRGB(255, 140 + math.random(0, 80), 50) or shownColor)
					b.Part.Color = color
					b.Part.Transparency = look and look.Transparency or 0
					b.Part.CFrame = CFrame.lookAt(b.Pos, b.Pos + b.Dir)
					if style == "Rocket" then -- 연기 꼬리
						table.insert(fx, { Part = stagePart(Enum.PartType.Ball, Vector3.new(0.5, 0.5, 0.5), b.Pos - b.Dir * 1.2, Color3.fromRGB(190, 190, 200), Enum.Material.SmoothPlastic), Vel = Vector3.zero, Life = 0.3, Max = 0.3 })
					end
					if b.Pos.X >= targetX - 2.1 then
						b.Part:Destroy()
						table.remove(bullets, i)
						hitFlash = 1
						burst(Vector3.new(targetX - 2, b.Pos.Y, b.Pos.Z), math.clamp(4 + (shot.Impact or 10) // 6, 4, 14), color, 10)
						if classInfo.Splash then splashRing(slime.Position, classInfo.Splash * 0.5, shownColor) end
					end
				end
			end
			-- 표적 반응 (맞으면 번쩍하고 찌그러진다)
			hitFlash = math.max(0, hitFlash - dt * 7)
			slime.Color = slimeColor:Lerp(Color3.new(1, 1, 1), hitFlash)
			slime.Size = Vector3.new(4 - hitFlash * 0.5, 3.4 + hitFlash * 0.3, 4 - hitFlash * 0.5)
			slime.Position = Vector3.new(targetX + hitFlash * 0.4, -0.4, 0)
			-- 파편 / 효과
			for i = #fx, 1, -1 do
				local e = fx[i]
				e.Life -= dt
				if e.Life <= 0 then
					e.Part:Destroy()
					table.remove(fx, i)
				else
					e.Part.Position += e.Vel * dt
					e.Part.Transparency = math.clamp(1 - e.Life / e.Max, 0, 1)
					if e.Grow then
						local d = 1 + e.Grow * (1 - e.Life / e.Max)
						e.Part.Size = Vector3.new(d, d, d)
					end
				end
			end
		end)
	end
end
end
