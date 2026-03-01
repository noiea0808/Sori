# Sori MVP - Firebase 설정 가이드

1. **FlutterFire CLI** (권장)
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```
   - Android 패키지명: `com.sori.sori`
   - 생성된 `lib/firebase_options.dart`를 사용하세요.

2. **수동**
   - Firebase Console에서 Android 앱 추가 후 `google-services.json`을 `android/app/`에 복사.
   - `lib/main.dart`에서:
     ```dart
     import 'package:firebase_core/firebase_core.dart';
     await Firebase.initializeApp(); // 옵션은 Console에서 확인
     ```

3. **Firestore**
   - 컬렉션 `sori_posts` 생성.
   - GeoQuery용 복합 인덱스: `position` (geohash), 전국 폴백용 `expires_at` ASC + `created_at` DESC.

4. **Storage**
   - 규칙에서 `sori_audio/*` 경로 업로드/읽기 허용.

5. **시그널 사운드**
   - `assets/audio/signal.mp3` (0.5초 짧은 비프)를 추가하면 새 음성 재생 전에 재생됩니다. 없으면 대기만 합니다.
