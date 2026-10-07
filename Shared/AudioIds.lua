-- AudioIds (ReplicatedStorage 안의 ModuleScript, 이름: AudioIds)
-- 내가 고른 소리의 Roblox 오디오 ID(숫자)를 여기에 적는다. 0이면 그 소리는 재생하지 않음.
-- 업데이트 플러그인은 이 파일을 덮어쓰지 않는다 (없을 때만 새로 만듦) -> 한 번 적어두면 계속 유지됨.

return {
	Lobby = 0,          -- 로비 배경음악
	Dungeon = 0,        -- 던전(웨이브) 배경음악
	Boss = 0,           -- 보스전 배경음악
	Field = 0,          -- 필드 배경음악 (0이면 로비 음악이 계속 나옴)
	Shot = 0,           -- 총 쏘는 소리
	EnhanceSuccess = 0, -- 강화 성공 소리
}
