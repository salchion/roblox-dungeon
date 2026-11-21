-- AimShare (StarterPlayer > StarterPlayerScripts 안의 ModuleScript, 이름: AimShare)
-- 내 화면 안에서만 쓰는 조준점 공유 칸: PlayerClient 가 쏠 때 조준점을 적고, CharacterMotionClient 가 상체를 그쪽으로 돌린다.
-- (Attribute 대신 모듈 표: 같은 클라이언트에서 require 하면 같은 표라 복제 / 변경 신호 부담이 없다)
return { Point = nil, At = 0 }
