# 실행과 배포 준비

이 문서는 저장소의 로컬 실행 설정과 Docker·PostgreSQL 구성을 설명한다. Dockerfile과 Compose 파일이 있다는 사실은 서버 배포가 완료되었다는 의미가 아니다. 실제 배포 결과는 대상 서버에서 별도로 확인해야 한다.

## IntelliJ에서 실행

1. 프로젝트 폴더의 `build.gradle`을 IntelliJ IDEA에서 열고 Gradle 프로젝트로 불러온다.
2. Project SDK와 Gradle JVM에 JDK 21 이상의 지원 버전을 지정한다. 소스 컴파일 기준은 프로젝트의 `release = 21` 설정을 사용한다.
3. `kr.ac.dbdesign.workforce.WorkforceApplication`의 `main`을 실행한다.
4. 기본 프로필은 `dev`이며, 별도의 DB 설치 없이 H2 메모리 DB를 사용한다.
5. [홈 화면](http://localhost:8080/)과 [상태 확인](http://localhost:8080/actuator/health)을 연다.

Flyway가 최초 스키마와 기준 데이터를 적재한다. 사원·프로젝트 등 실제 업무 데이터는 기본으로 넣지 않으므로 홈의 0건·빈 목록이 정상적인 첫 화면이다. `dev`의 데이터는 JVM 종료 후 유지되지 않는다.

PowerShell에서는 프로젝트 루트에서 다음과 같이 빌드·실행할 수 있다.

```powershell
.\gradlew.bat test bootJar
.\gradlew.bat bootRun
```

macOS·Linux에서는 같은 작업에 `./gradlew`를 사용한다. IntelliJ 실행과 `bootRun` 모두 `.env` 파일을 자동으로 읽도록 구현되어 있지 않다. 외부 DB를 연결할 때는 실행 구성 또는 셸에 환경변수를 지정한다.

## 외부 PostgreSQL 연결

`prod` 프로필로 실행할 때 다음 값을 지정한다.

| 환경변수 | 용도 | 예시·기본값 |
|---|---|---|
| `SPRING_PROFILES_ACTIVE` | 프로필 선택 | `prod` |
| `DB_URL` | PostgreSQL JDBC 주소 | `jdbc:postgresql://localhost:5432/workforce` |
| `DB_USERNAME` | DB 사용자 | 환경의 DB 계정 |
| `DB_PASSWORD` | DB 비밀번호 | 환경에서 주입 |
| `PORT` | 애플리케이션 HTTP 포트 | 미지정 시 `8080` |

이 프로젝트의 운영 대상은 PostgreSQL 17이다. DB와 계정이 준비되어 있어야 하고, Flyway 최초 적용 시에는 테이블을 생성할 권한이 필요하다. H2 호환 모드의 테스트 성공은 PostgreSQL에서의 실제 연결·마이그레이션 검증을 대신하지 않는다.

PowerShell에서 외부 DB로 실행하는 예시다. 비밀번호는 해당 환경의 비밀값 관리 방식으로 설정한다.

```powershell
$env:SPRING_PROFILES_ACTIVE = 'prod'
$env:DB_URL = 'jdbc:postgresql://localhost:5432/workforce'
$env:DB_USERNAME = 'workforce'
# DB_PASSWORD는 실행 환경에 설정
$env:PORT = '8080'
.\gradlew.bat bootRun
```

JAR를 실행할 때도 같은 환경변수를 사용한다. 현재 프로젝트명·버전 기준 결과물은 `build/libs/workforce-0.0.1-SNAPSHOT.jar`이며, 프로젝트 루트에서 다음과 같이 실행한다.

```powershell
java -jar build/libs/workforce-0.0.1-SNAPSHOT.jar
```

## Docker Compose로 실행

Docker Engine과 Compose가 실행되는 환경에서 프로젝트 루트의 `compose.yml`을 사용한다.

1. `.env.example`을 `.env`로 복사한다.
2. `.env`의 `DB_PASSWORD`를 본인 환경의 값으로 바꾼다. 예시 문자열을 그대로 사용하지 않는다.
3. 필요한 경우 `DB_USERNAME`과 `APP_PORT`를 바꾼다.
4. Compose를 빌드·실행하고 로그와 health 응답을 확인한다.

```powershell
Copy-Item .env.example .env
# .env 값을 편집한 다음 실행
docker compose up --build -d
docker compose ps
docker compose logs app
```

| 구성 | 동작 |
|---|---|
| `db` | `postgres:17` 이미지, DB 이름 `workforce`, `postgres-data` 볼륨에 저장 |
| `app` | Dockerfile로 빌드, `prod` 프로필, `jdbc:postgresql://db:5432/workforce`로 연결 |
| DB 준비 확인 | `pg_isready` healthcheck가 정상인 뒤 앱 시작 |
| 앱 포트 | 컨테이너 내부 `PORT=8080`, 호스트에서 `${APP_PORT:-8080}`으로 접근 |

`APP_PORT`는 Compose의 호스트 포트 매핑이고, `PORT`는 Spring 애플리케이션 자체 포트다. Compose에서는 내부 포트를 8080으로 고정하므로 외부 접근 포트만 바꾸려면 `.env`의 `APP_PORT`를 변경한다. 기본 접근 주소는 [홈 화면](http://localhost:8080/)이다.

`.env`는 Compose 설정값을 전달하기 위한 파일이며 Git에서 제외되어 있다. 저장소에는 자리표시자가 있는 `.env.example`만 포함한다. 컨테이너를 중지할 때는 `docker compose down`을 사용한다. DB 데이터가 들어 있는 볼륨은 별도로 관리한다.

Dockerfile은 JDK 21 빌드 단계와 JRE 21 실행 단계로 나뉘고, 컨테이너에서 일반 사용자로 애플리케이션을 실행한다. 이미지는 준비된 실행 경로이며, 이 문서만으로 이미지 빌드·서버 배포·외부 접속 성공을 주장하지 않는다.

## 배포 확인 범위

서버에 배포할 때는 PostgreSQL 연결 정보와 `SPRING_PROFILES_ACTIVE=prod`, 서버가 제공하는 `PORT`를 지정한다. 프록시·도메인·TLS는 선택한 호스팅 환경에서 설정한다.

- 앱 기동 로그에서 Flyway 마이그레이션과 웹 서버 기동 성공을 확인한다.
- `GET /actuator/health`의 정상 응답을 확인한다.
- `GET /`에서 화면이 렌더링되고 DB의 실제 집계·프로젝트 목록이 표시되는지 확인한다.
- 애플리케이션 재시작 후에도 PostgreSQL 데이터가 유지되는지 확인한다.

현재 업무 엔드포인트는 조회용 `GET /`이다. 회원가입·인증·권한·등록·수정·평가 작성·휴가 승인 기능은 아직 구현하지 않았으므로 이 기능들의 공개 시연이나 운영 완료 상태로 해석하지 않는다.

GitHub Actions의 `Build and verify` 워크플로는 JDK 21에서 `test bootJar`를 실행하도록 구성되어 있다. 이 CI는 배포 워크플로가 아니며, H2 기반 테스트와 빌드 결과만 확인한다. PostgreSQL 17 실제 연결과 대상 서버 검증은 별도다.

## 저장소에 포함할 자료

직접 작성한 애플리케이션·DDL·ERD·실행 문서만 공개한다. 과제 원본·강의 PDF, 원본 Excel, DA# 설치 파일과 비밀값을 공개 저장소나 이미지 빌드 문맥에 추가하지 않는다. 실제 DB 비밀번호·개인정보는 저장소 대신 실행 환경에서 관리한다.
