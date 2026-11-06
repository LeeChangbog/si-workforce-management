# SI Workforce Management

데이터베이스설계 수업의 SI 기업 사원·프로젝트·평가·휴가·경쟁 발주처 정보 차단벽 프로젝트입니다. IntelliJ IDEA에서 열어 실행할 수 있는 Spring Boot 기반을 제공합니다.

## 현재 구현

- Spring Boot 4.1.2, Java 21 호환 소스, Gradle Wrapper
- Spring MVC + Thymeleaf 한국어 홈 화면
- JdbcTemplate으로 사원·프로젝트·평가·휴가 신청 집계 및 프로젝트·발주처 조인 조회
- Flyway: 26개 테이블, 33개 FK(일반 관계 28 + 하위 유형 상속 5), PK·UK·CHECK
- 경쟁 발주처의 동일 개발자 동시 투입 탐지 SQL, 선택 적재 데모(경쟁 3쌍·위반 3건), ERD
- 로컬 H2 개발 설정, PostgreSQL 운영 설정, Dockerfile·Compose 및 GitHub Actions

회원가입·로그인·권한, 업무별 CRUD, 휴가 승인·차감 트랜잭션, 투입 등록 시 경쟁 관계 사전 경고와 경영진 전용 조회 화면은 후속 구현 범위입니다. 현재는 DB 구조와 실행 기반, SQL로 실행하는 정보 차단벽 시나리오를 마련한 단계입니다.

## IntelliJ에서 실행

1. 이 폴더를 IntelliJ IDEA의 **Open**으로 열고 Gradle 프로젝트를 불러옵니다.
2. Project SDK와 Gradle JVM을 JDK 21 이상으로 지정합니다. 빌드 결과는 Java 21을 대상으로 합니다.
3. `kr.ac.dbdesign.workforce.WorkforceApplication`을 실행합니다.
4. <http://localhost:8080>을 엽니다. 기본 `dev` 프로필은 메모리 H2를 사용하며 앱을 종료하면 업무 데이터가 사라집니다.

PowerShell에서도 실행할 수 있습니다. `JAVA_HOME`에 설치된 JDK 경로가 필요합니다.

```powershell
.\gradlew.bat bootRun
```

## 테스트와 패키징

```powershell
.\gradlew.bat test bootJar
```

총 19개 테스트가 고아 FK, 로그인·참여 중복, 양수 연차 부여분, 평가상세 복합 PK, 휴가 처리자 선택성 및 경쟁 관계 제약·기간 경계·정상 겹침 허용·데모 위반 3건을 확인합니다. GitHub Actions는 PostgreSQL 17에서도 실제 마이그레이션, HTTP 기동, 정보 차단벽 데모 SQL과 탐지 결과를 확인합니다.

정보 차단벽 데모 실행과 성능 실험 계획은 [대표 시나리오](docs/scenarios/client-competition.md)를 참고합니다. 요청에 따라 V1에 테이블을 추가했으므로 새 DB 기준입니다. 이전 V1을 적용한 영속 DB는 Flyway checksum 불일치가 발생하며 별도 업그레이드 마이그레이션이 필요합니다.

## PostgreSQL 연결과 배포 준비

IntelliJ 실행 설정에 다음 환경변수를 지정하면 외부 PostgreSQL에 연결할 수 있습니다.

```text
SPRING_PROFILES_ACTIVE=prod
DB_URL=jdbc:postgresql://localhost:5432/workforce
DB_USERNAME=workforce
DB_PASSWORD=실제_DB_비밀번호
PORT=8080
```

DB와 앱을 Docker로 함께 실행하려면 `.env.example`을 `.env`로 복사하고 비밀번호를 바꾼 뒤 실행합니다.

```powershell
Copy-Item .env.example .env
docker compose up --build
```

서버의 컨테이너 실행 환경과 PostgreSQL이 있으면 같은 이미지를 배포할 수 있습니다. 현재 외부 서버 배포는 하지 않았습니다. 배포 전 인증·접근권한 기능을 구현해야 합니다.

## 설계 자료

- [요구사항과 구현 범위](docs/requirements-mapping.md)
- [시스템 구조](docs/architecture.md)
- [실행·배포 설정](docs/deployment.md)
- [확정 데이터 모델](docs/model/schema.json)
- [업무 규칙과 구현 책임](docs/model/business-rules.md)
- [ERD 자료](docs/erd/)
- [정보 차단벽 대표 시나리오·성능 실험 계획](docs/scenarios/client-competition.md)

원본 강의 PDF·조 요구사항 엑셀·설치 파일·실제 인사정보·로컬 비밀번호는 이 저장소에 포함하지 않습니다.
