# Flutter 처음 설치 가이드 (Windows)

Sori 프로젝트를 실행하려면 Flutter SDK가 필요합니다. 아래 순서대로 진행하세요.

---

## 1. Flutter SDK 설치

### 방법 A: 공식 사이트에서 설치 (권장)

1. **다운로드**
   - https://docs.flutter.dev/get-started/install/windows 접속
   - 또는 직접: https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.24.5-stable.zip
   - ZIP 파일을 **C 드라이브** 등 경로에 짧게 두는 것을 권장 (예: `C:\flutter`)

2. **압축 해제**
   - `C:\flutter` 같은 폴더에 풀기 (경로에 공백/한글 피하기)

3. **PATH 추가**
   - Windows 검색에서 "환경 변수" 입력 → "시스템 환경 변수 편집"
   - "환경 변수" 버튼 클릭
   - "사용자 변수"에서 **Path** 선택 → "편집" → "새로 만들기"
   - 다음 경로 추가: `C:\flutter\bin` (본인이 풀어둔 경로의 `\bin` 폴더)
   - 확인으로 모두 닫기

4. **새 터미널 열기**
   - Cursor/VS Code를 완전히 종료했다가 다시 열거나, 새 터미널 탭을 연다.

5. **설치 확인**
   ```powershell
   flutter --version
   flutter doctor
   ```

---

### 방법 B: winget으로 설치 (Windows 10/11)

```powershell
winget install -e --id Google.Flutter
```

설치 후 **새 터미널**을 열고 `flutter doctor` 실행.

---

## 2. flutter doctor로 환경 점검

```powershell
flutter doctor
```

- ✅ **Flutter**: 나오면 OK  
- ✅ **Android toolchain**: Android 앱을 만들려면 필요  
- ⚠️ **Android Studio** / **VS Code**: 없으면 해당 IDE 설치 후 Flutter 확장 설치  
- ⚠️ **Android licenses**: 안드로이드 개발용. `flutter doctor --android-licenses` 실행 후 전부 `y` 입력

---

## 3. Android 앱을 실행하려면 (선택)

- **Android Studio** 설치: https://developer.android.com/studio  
  - 설치 시 "Android SDK", "Android SDK Platform", "Android Virtual Device" 포함되도록 선택  
- 또는 **실기기** USB 연결 후 USB 디버깅 켜기  
- 터미널에서: `flutter doctor --android-licenses` 로 라이선스 동의

---

## 4. Sori 프로젝트 실행 순서

Flutter가 정상 동작하면:

```powershell
cd "e:\200. Dev\Sori"
flutter pub get
flutter run
```

(실기기 또는 에뮬레이터가 연결된 상태에서 실행)

---

## 5. Firebase 연결 (나중에)

Flutter가 잘 돌아가는 걸 확인한 뒤:

```powershell
dart pub global activate flutterfire_cli
flutterfire configure
```

---

## 요약 체크리스트

- [ ] Flutter SDK 다운로드 및 압축 해제 (예: C:\flutter)
- [ ] Path에 `flutter\bin` 추가
- [ ] 새 터미널에서 `flutter doctor` 실행
- [ ] (Android 앱용) Android Studio 또는 실기기 + `flutter doctor --android-licenses`
- [ ] `cd "e:\200. Dev\Sori"` → `flutter pub get` → `flutter run`

문제 생기면 `flutter doctor -v` 결과를 확인해 보세요.
