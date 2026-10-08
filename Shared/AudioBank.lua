-- AudioBank (ReplicatedStorage 안의 ModuleScript, 이름: AudioBank)
-- 항목별 효과음 ID 목록. 이 파일은 "던전 업데이트"로 갱신된다 (소리 ID 를 알려주면 여기에 적어서 올려 준다).
-- 0 이거나 없는 항목은 기본 소리를 가공해서 쓴다. 항목 이름과 설명은 Shared/SoundBank.lua 참고.
-- (ReplicatedStorage > AudioIds 의 Bank = { ... } 에 직접 적은 값이 있으면 그쪽이 우선한다.)

return {
	Shot_Smg = 133095953198600, -- 기관단총 발사
	Skill_Heal = 136612911524402, -- 응급 치료 스킬
}
