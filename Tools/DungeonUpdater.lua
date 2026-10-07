-- DungeonUpdater: Roblox Studio 플러그인 (한 번만 설치하면 됨)
-- 툴바의 [던전 업데이트] 버튼을 누르면 GitHub 최신 코드를 받아서 스크립트들을 자동으로 만들고/덮어쓴다.
--
-- 설치: Studio에서 ServerStorage에 Script를 하나 만들고 이 파일 내용을 붙여넣은 뒤
--       Script를 우클릭 -> "로컬 플러그인으로 저장..." -> 저장. (그 다음 만든 Script는 지워도 됨)
-- 처음 버튼을 누르면 "raw.githubusercontent.com 접근 허용" 창이 뜨는데 허용을 누르면 된다.

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

-- 코드를 가져올 GitHub 저장소 / 브랜치 (main 에 합친 뒤에는 BRANCH 를 "main" 으로 바꾸면 됨)
local REPO = "salchion/roblox-dungeon"
local BRANCH = "claude/brave-cannon-x4jyw0"

-- { 저장소 안 파일 경로, Studio 위치, 스크립트 이름, 종류, 이미 있으면 덮어쓸지 }
local FILES = {
	{ "Shared/Config.lua", "ReplicatedStorage", "Config", "ModuleScript", true },
	{ "Shared/Remotes.lua", "ReplicatedStorage", "Remotes", "ModuleScript", true },
	{ "Shared/AudioIds.lua", "ReplicatedStorage", "AudioIds", "ModuleScript", false }, -- 내가 적은 소리 ID 보존
	{ "GameServer.lua", "ServerScriptService", "GameServer", "Script", true },
	{ "Server/Effects.lua", "ServerScriptService/Modules", "Effects", "ModuleScript", true },
	{ "Server/WeaponService.lua", "ServerScriptService/Modules", "WeaponService", "ModuleScript", true },
	{ "Server/PartyService.lua", "ServerScriptService/Modules", "PartyService", "ModuleScript", true },
	{ "Server/LobbyService.lua", "ServerScriptService/Modules", "LobbyService", "ModuleScript", true },
	{ "Server/DungeonService.lua", "ServerScriptService/Modules", "DungeonService", "ModuleScript", true },
	{ "Server/DataService.lua", "ServerScriptService/Modules", "DataService", "ModuleScript", true },
	{ "Server/DummyService.lua", "ServerScriptService/Modules", "DummyService", "ModuleScript", true },
	{ "PlayerClient.lua", "StarterPlayer/StarterPlayerScripts", "PlayerClient", "LocalScript", true },
}

local toolbar = plugin:CreateToolbar("Dungeon")
local button = toolbar:CreateButton("던전 업데이트", "GitHub 최신 코드로 스크립트를 업데이트합니다", "")

-- "ServerScriptService/Modules" 같은 경로의 폴더를 찾고, 없으면 Folder 로 만든다
local function resolveParent(path)
	local parts = string.split(path, "/")
	local current = game:GetService(parts[1])
	for i = 2, #parts do
		local child = current:FindFirstChild(parts[i])
		if not child then
			child = Instance.new("Folder")
			child.Name = parts[i]
			child.Parent = current
		end
		current = child
	end
	return current
end

local function update()
	if RunService:IsRunning() then
		warn("[업데이트] Play 중에는 업데이트할 수 없어요. 정지(■)한 뒤 다시 눌러주세요.")
		return
	end

	-- 1) 전부 먼저 내려받는다 (하나라도 실패하면 아무것도 바꾸지 않음)
	local contents = {}
	for _, file in ipairs(FILES) do
		local url = string.format("https://raw.githubusercontent.com/%s/%s/%s?t=%d", REPO, BRANCH, file[1], os.time())
		local ok, result = pcall(function()
			return HttpService:GetAsync(url, true)
		end)
		if not ok then
			warn("[업데이트] 실패: " .. file[1] .. " -> " .. tostring(result))
			warn("[업데이트] 아무것도 바꾸지 않았어요. 인터넷/허용 창을 확인하고 다시 눌러주세요.")
			return
		end
		contents[file[1]] = result
	end

	-- 2) 스크립트 만들기 / 덮어쓰기
	ChangeHistoryService:SetWaypoint("던전 업데이트 전")
	local created, updated, kept = 0, 0, 0
	for _, file in ipairs(FILES) do
		local parent = resolveParent(file[2])
		local existing = parent:FindFirstChild(file[3])

		if existing and existing.ClassName ~= file[4] then
			existing:Destroy() -- 종류가 다르면(예: Script 대신 ModuleScript) 다시 만든다
			existing = nil
		end

		if existing then
			if file[5] then
				existing.Source = contents[file[1]]
				updated += 1
			else
				kept += 1
			end
		else
			local script = Instance.new(file[4])
			script.Name = file[3]
			script.Source = contents[file[1]]
			script.Parent = parent
			created += 1
		end
	end
	ChangeHistoryService:SetWaypoint("던전 업데이트 후")

	print(string.format("[업데이트] 완료! 새로 만듦 %d / 업데이트 %d / 유지 %d  (Ctrl+S 로 저장하세요)", created, updated, kept))
end

button.Click:Connect(function()
	task.spawn(update)
end)
