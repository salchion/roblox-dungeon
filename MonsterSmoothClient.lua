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
							print(string.format("[몬스터 어긋남] 본체 X=%d 겉모양 부품 '%s' 이(가) %d 스터드 떨어짐 (본체 크기 %.0f)",
								math.floor(body.Position.X), decor.Name, math.floor((decor.Position - body.Position).Magnitude), body.Size.Magnitude))
							break
						end
					end
				end
			end
		end
	end
end)
