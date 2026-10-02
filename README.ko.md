# Offline Coding Agent Pack

Windows PC에서 인터넷 없이 Roo Code 기반 코딩 에이전트를 설치하고, 사용자가 별도로 넣은 Qwen GGUF 모델로 로컬 코딩 작업을 수행하기 위한 패키지입니다.

## 구성

- VSCodium 또는 기존 VS Code
- Roo Code VSIX 확장
- llama.cpp `llama-server.exe`
- Qwen GGUF 모델은 사용자가 직접 `models/`에 복사
- C#/WPF, C++ 프로젝트용 빌드 프로파일 자동 생성
- Git 로컬 저장소 기준 작업
- 빌드 실패 자동 수정 재시도 기본 2회

## 온라인 PC에서 패키지 만들기

인터넷이 되는 PC에서 PowerShell을 열고 실행합니다.

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\Build-OfflineBundle.ps1
```

완료되면 `dist\LocalCodingAgentOfflinePack.zip`이 생성됩니다. 이 ZIP을 오프라인 PC로 옮기면 됩니다.

## 오프라인 PC에서 설치

ZIP을 풀고 다음을 실행합니다.

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\Install-Offline.ps1
```

기존 VS Code 또는 VSCodium이 있으면 그 환경에 Roo Code VSIX를 설치합니다. 없으면 `vendor\vscodium`에 포함된 설치 파일을 실행합니다.

## 모델 넣기

Qwen GGUF 모델을 `models\` 폴더에 복사합니다.

추천:

- `Qwen3-Coder-30B-A3B-Instruct Q4_K_M`
- 저사양: `Qwen2.5-Coder-14B-Instruct Q4_K_M`
- 더 저사양: `Qwen2.5-Coder-7B-Instruct Q5_K_M`

## 모델 서버 시작

```powershell
.\scripts\Start-LocalModel.ps1
```

기본 API 주소:

```text
http://127.0.0.1:8080/v1
```

Roo Code에서는 provider를 `OpenAI Compatible`로 선택하고 다음처럼 설정합니다.

```text
Base URL: http://127.0.0.1:8080/v1
API Key: none
Model: local-qwen-coder
```

## 프로젝트 설정

작업할 C#/WPF 또는 C++ 프로젝트 폴더에 빌드 설정과 Roo Code 규칙을 넣습니다.

```powershell
.\scripts\Configure-Workspace.ps1 -ProjectPath "D:\Work\MyProject" -InitGitIfMissing
```

생성되는 파일:

- `.vscode\tasks.json`
- `.roo\rules\10-local-coding-agent.md`
- `.clinerules\10-local-coding-agent.md`
- `local-agent.build-profiles.json`
- `.rooignore`

## 사용 흐름

1. `Start-LocalModel.ps1`로 Qwen GGUF 서버 실행
2. VS Code 또는 VSCodium에서 프로젝트 열기
3. Roo Code에서 OpenAI Compatible provider 설정
4. 작업 지시
5. 에이전트가 Git 저장소 안에서 자동 수정
6. 설정된 빌드 명령 실행
7. 빌드 실패 시 최대 2회 자동 수정 재시도
8. 마지막에 Git diff와 빌드 결과 확인

## 오프라인 범위

이 패키지는 모델 파일을 제외한 실행 환경을 오프라인으로 옮기는 것을 목표로 합니다. 모델은 라이선스와 용량 문제 때문에 포함하지 않습니다.

## 외부 접속 차단/무접속 모드

오프라인 설치 ZIP에는 다운로드/릴리즈용 온라인 스크립트가 포함되지 않습니다. 설치 스크립트는 로컬 VSIX 설치, 로컬 llama.cpp 확인, 로컬 설정 파일 생성만 수행합니다.

설치 과정에서 다음 VS Code/VSCodium 설정을 적용합니다.

- `telemetry.telemetryLevel`: `off`
- `update.mode`: `none`
- `extensions.autoUpdate`: `false`
- `extensions.autoCheckUpdates`: `false`
- `extensions.ignoreRecommendations`: `true`
- `workbench.enableExperiments`: `false`

더 강하게 막고 싶으면 관리자 PowerShell에서 다음을 실행해 에디터 실행 파일의 outbound 방화벽 차단 규칙을 추가할 수 있습니다. 로컬 루프백 API(`127.0.0.1`)는 계속 사용할 수 있습니다.

```powershell
.\scripts\Enable-AirGapMode.ps1 -ConfigureFirewall
```

Roo Code provider는 반드시 `OpenAI Compatible` + `http://127.0.0.1:8080/v1`로 설정하세요. 외부 API provider를 선택하면 그 provider로 접속을 시도할 수 있습니다.
