미출고·반송 관리센터 v3.0 (GitHub Pages 개인 시험판)

1. 이 ZIP을 풀어 index.html 파일을 더블클릭하면 PC에서 즉시 테스트할 수 있습니다.
2. GitHub Pages로 사용하려면 GitHub 저장소 루트에 index.html 파일을 업로드합니다.
3. Settings > Pages > Build and deployment > Deploy from a branch > main / (root) > Save
4. 배포 후 예상 주소: https://choi2704.github.io/unshipped-manager/
   (설정 완료 후에만 접속 가능하며 실제 URL은 GitHub Pages 화면에서 확인)
5. '미출고 송장'과 '반송예정'을 선택하고 + 신규 등록으로 시험합니다.
6. CSV 다운로드는 Excel에서 열 수 있습니다. 기록 백업은 '백업/복원' > JSON 백업입니다.

중요: 이 버전은 서버/로그인 없이 브라우저 localStorage에 저장합니다.
PC, 브라우저, 프로필, 시크릿 창이 다르면 데이터가 공유되지 않습니다.
브라우저 데이터 삭제 또는 회사 PC 교체 시 데이터가 유실될 수 있으므로 JSON 백업하세요.
실제 고객의 이름/주문번호 등 개인정보를 GitHub Pages 기반 개인 시험판에 입력하지 마세요.
나중에 여러 팀이 함께 사용하려면 Supabase 인증과 DB 및 접근 권한으로 교체해야 합니다.
GitHub Pages 저장소는 Public이어야 할 수도 있으며 공개 저장소에 개인정보를 커밋하지 마세요.
기존 Vercel 소스의 index.html과 혼합 업로드하지 말고 별도 시험 저장소에 설치하는 것을 권장합니다.
