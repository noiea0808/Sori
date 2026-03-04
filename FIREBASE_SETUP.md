# Sori - Firebase 연동 가이드

프로젝트 루트에 Firestore/Storage 규칙과 인덱스 설정이 준비되어 있습니다. 아래 순서대로 진행하세요.

---

## 1. Firebase 프로젝트 만들기

1. **Firebase Console** 접속: https://console.firebase.google.com/
2. **프로젝트 추가** → 프로젝트 이름(예: `Sori`) 입력
3. (선택) Google Analytics 사용 여부
4. 생성 완료 후 **프로젝트 설정(톱니바퀴)** 에서 **프로젝트 ID** 확인 (예: `sori-abc12`)

---

## 2. Android 앱 등록

1. Firebase Console **프로젝트 개요** → **Android 아이콘** 클릭
2. **Android 패키지 이름**에 아래를 **그대로** 입력:
   ```
   com.sori.sori
   ```
3. (선택) 앱 닉네임, 디버그 서명 인증서
4. **앱 등록** 후 `google-services.json` 다운로드
5. 다운로드한 파일을 프로젝트의 **`android/app/`** 폴더에 복사

---

## 3. FlutterFire CLI로 Flutter 연동

터미널에서 프로젝트 폴더로 이동한 뒤:

```powershell
cd "d:\700. Dev\200_Sori"

# FlutterFire CLI 설치 (한 번만)
dart pub global activate flutterfire_cli

# Firebase 로그인 및 프로젝트 연결
flutterfire configure
```

- 로그인 창이 뜨면 Google 계정으로 로그인
- 방금 만든 Firebase 프로젝트 선택
- **Android**만 선택해도 됨 (iOS는 나중에)
- 완료되면 `lib/firebase_options.dart`가 생성되고, `google-services.json`이 자동으로 쓰일 수 있음 (이미 2번에서 넣었다면 그대로 사용)

---

## 4. Firebase CLI로 규칙·인덱스 배포 (선택)

Firestore/Storage 규칙과 인덱스를 Firebase에 반영하려면:

```powershell
# Firebase CLI 설치 (한 번만)
npm install -g firebase-tools

# 로그인
firebase login

# 프로젝트 연결 (프로젝트 ID 입력)
firebase use --add
# → 목록에서 방금 만든 프로젝트 선택 후 별칭은 default

# 규칙·인덱스 배포
firebase deploy
```

- **`.firebaserc`** 의 `"sori-xxxxx"`는 `firebase use --add`로 선택한 프로젝트로 자동 갱신됨
- 배포 후 Firestore **규칙**, **인덱스**, Storage **규칙**이 적용됨

직접 콘솔에서 설정하려면:

- **Firestore** → 규칙: `firestore.rules` 내용 복사  
- **Firestore** → 인덱스: `firestore.indexes.json` 내용 참고해 동일하게 생성  
- **Storage** → 규칙: `storage.rules` 내용 복사  

---

## 5. Firestore 컬렉션

- **컬렉션 ID**: `sori_posts`
- 앱에서 첫 문서를 추가할 때 자동 생성되므로, 미리 만들 필요는 없음
- GeoQuery용 **position**(geohash) 필드는 GeoFlutterFire2가 문서 저장 시 자동 추가

---

## 6. 확인

1. `lib/main.dart`에 다음이 있는지 확인:
   ```dart
   await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
   ```
2. `lib/firebase_options.dart` 파일이 있고, `DefaultFirebaseOptions`가 정의되어 있는지 확인
3. 앱 실행:
   ```powershell
   flutter pub get
   flutter run
   ```

---

## 요약 체크리스트

- [ ] Firebase Console에서 프로젝트 생성
- [ ] Android 앱 등록 (패키지명 `com.sori.sori`)
- [ ] `google-services.json` → `android/app/` 에 저장
- [ ] `flutterfire configure` 실행 → `firebase_options.dart` 생성
- [ ] (선택) `firebase use --add` 후 `firebase deploy` 로 규칙·인덱스 배포
- [ ] `flutter run` 으로 앱 실행 후 동작 확인

---

## 기기마다 목록이 다를 때 (트러블슈팅)

**증상**: A에서 빌드한 앱과 B에서 빌드한 앱이 서로 다른 녹음 목록을 보임. 각 기기에서 자기 기기가 녹음한 것만 보임.

**원인**: 빌드할 때마다 다른 Firebase 프로젝트 설정이 들어감. 각 PC/기기에서 `flutterfire configure`를 따로 실행하면 서로 다른 프로젝트가 선택될 수 있음.

**해결** (한 번만 설정):
1. **한 PC에서** `dart pub global run flutterfire_cli:flutterfire configure` 실행 → `sori-ff608` 프로젝트 선택
2. `lib/firebase_options.dart`와 `android/app/google-services.json`이 생성됨
3. **위 두 파일을 커밋** (`git add` + `git commit`)
4. **다른 PC에서** `git pull` 후 빌드 → 모두 같은 Firebase 프로젝트 사용

**중요**: `main.dart`는 `firebase_options.dart`를 사용하도록 설정됨. 이 파일이 커밋되어 있으면 어떤 PC에서 빌드해도 같은 Firestore를 사용합니다.

---

## 파일 설명

| 파일 | 용도 |
|------|------|
| `firebase.json` | Firestore/Storage 규칙·인덱스 파일 경로 |
| `.firebaserc` | 사용할 Firebase 프로젝트 ID (firebase use 시 갱신) |
| `firestore.rules` | Firestore 보안 규칙 (`sori_posts` 읽기/쓰기) |
| `firestore.indexes.json` | 전국 폴백 쿼리용 복합 인덱스 |
| `storage.rules` | Storage 보안 규칙 (`sori_audio` 읽기/쓰기) |
