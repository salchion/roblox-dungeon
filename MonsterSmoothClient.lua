-- MonsterSmoothClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript)
-- 예전의 몬스터 위치 보정은 보스 움직임과 충돌해서 껐다. 지금은 Studio 에서만 도는 진단용이다:
--   몬스터의 겉모양(장식 부품)이 판정용 본체(체력바 / 피격 기준)에서 너무 멀리 떨어져 보이면 출력창에 한 줄 찍는다.
--   (게임 서버에서는 아무것도 안 한다.)

local RunService = game:GetService("RunService")
if not RunService:IsStudio() then return end

local reportedAt = setmetatable({}, { __mode = "k" })

task.spawn(function()
	while true do
		task.wait(0.5)
		local folder = workspace:FindFirstChild("FieldMonsters")
		if folder then
			local now = os.clock()
			for _, body in ipairs(folder:GetChildren()) do
				if body:IsA("BasePart") and now - (reportedAt[body] or -10) > 5 then
					local limit = body.Size.Magnitude * 2 + 6
					for _, decor in ipairs(body:GetChildren()) do
						if decor:IsA("BasePart") and (decor.Position - body.Position).Magnitude > limit then
							reportedAt[body] = now
							print(string.format("[Monster desync] Body '%s' X=%d, visual part '%s' (%s, anchored=%s) is %d studs away (body size %.0f) · decor path: %s",
								body.Name, math.floor(body.Position.X), decor.Name, decor.ClassName, tostring(decor.Anchored), math.floor((decor.Position - body.Position).Magnitude), body.Size.Magnitude, decor:GetFullName()))
							break
						end
					end
				end
			end
		end
	end
end)
