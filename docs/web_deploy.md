# Вэб хувилбарыг онлайн байршуулах

Mobile апп утсанд суудаг тул "онлайн сервер дээр" байршуулах боломжтой нь
Flutter-ийн **вэб хувилбар** юм. Вэб апп, AI дохио, MSE-ийн ханш гурвыг нэг
Firebase Hosting сайтад байршуулна:

```
https://diplom-23056.web.app
  /                 вэб апп (flutter build web)
  /ai/              signals.json, advisor_model.json, report.md, signal_log.json
  /mse/market.json  I–III ангиллын жагсаалт + сүүлийн ханш
  /mse/history/     I–II ангиллын сүүлийн ~1 жилийн түүх (<SYMBOL>.json)

GitHub Actions — .github/workflows/refresh-signals.yml
  (ажлын өдөр 13:45 УБ, main-д апп-ын код push хийхэд, эсвэл гараар)
  build_dataset → train_advisor → тест → publish_market
    → flutter build web → assemble_hosting → Firebase Hosting
```

> **Анхаар:** Firebase Hosting нь deploy бүрт сайтыг **бүхэлд нь** солино.
> Тиймээс вэб апп, `ai/`, `mse/` гуравыг үргэлж хамт байршуулна
> (`tool/assemble_hosting.dart` дутуу бол алдаа өгч зогсоно). Зөвхөн
> `build/web`-ийг deploy хийвэл mobile апп-ын AI дохио алга болно.

## Вэб ба mobile хувилбарын ялгаа

| | Mobile (Android/iOS) | Вэб |
|---|---|---|
| MSE ханш | open.mse.mn-ээс шууд, арилжааны цагаар 1 мин тутам | `/mse/market.json` — өдөрт нэг удаа, хаалтын дараа (13:45 УБ) |
| Ханшийн график | Бүх хувьцаа | I–II ангилал (III ангилалд "түүх хангалтгүй") |
| Крипто, валютын ханш | Binance, open.er-api.com | Мөн адил (хоёулаа CORS зөвшөөрдөг) |
| AI зөвлөх | `signals.json` | Мөн адил |
| Багц | Firestore | Мөн адил |
| Биометр түгжээ | Бий | Нуусан (`local_auth` вэбд ажилладаггүй) |
| Gemini түлхүүр | Утасны нууц сан | Browser-ийн localStorage (шифрлэсэн) |

**Яагаад MSE-ийн snapshot хэрэгтэй вэ?** open.mse.mn нь CORS header
(`Access-Control-Allow-Origin`) өгдөггүй тул browser тэр сайтаас уншихыг
хориглоно. Иймд GitHub Actions ханшийг татаж өөрийн сайтдаа JSON болгон
нийтэлдэг бөгөөд вэб апп `lib/services/mse_snapshot_service.dart`-аар
уншина. Mobile апп хуучнаараа `MseService`-ээр шууд уншина. Binance
(`data-api.binance.vision`) болон `open.er-api.com` нь
`Access-Control-Allow-Origin: *` өгдөг тул proxy шаардлагагүй (2026-11-18-нд
шалгасан).

## Нэг удаагийн тохиргоо

1. **Firebase Hosting ба GitHub secret** — [signals_pipeline.md](signals_pipeline.md)-ийн
   1–2-р алхам (`FIREBASE_SERVICE_ACCOUNT` secret).

2. **Firebase Auth → Authorized domains.** Firebase Console → Authentication
   → Settings → *Authorized domains* жагсаалтад дараах нь байгаа эсэхийг
   шалгаж, байхгүй бол нэмнэ:
   - `diplom-23056.web.app`, `diplom-23056.firebaseapp.com` — үндсэн сайтынх
     тул ихэвчлэн автоматаар нэмэгдсэн байдаг;
   - `localhost` — дотоод хөгжүүлэлтэд;
   - өөр домайн (custom domain эсвэл өөр Hosting сайт) холбосон бол түүнийг.

   Жагсаалтад байхгүй домайнаас Google г.м. OAuth нэвтрэлт
   `auth/unauthorized-domain` алдаа өгнө, имэйл баталгаажуулах/нууц үг
   сэргээх линк ч ажиллахгүй.

   Хэрэв Google Cloud Console → APIs & Services → Credentials-д *Browser key*
   HTTP referrer-ээр хязгаарлагдсан бол тэнд ч `https://diplom-23056.web.app/*`-ийг нэмнэ.

3. **Firebase-ийн вэб тохиргоо.** `lib/firebase_options.dart` repo-оос
   хасагдсан (түлхүүрүүдийг устгасан) тул вэб апп тохиргоогоо байршуулсан
   сайтынхаа `/__/firebase/init.json` хаягаас уншина (`lib/firebase_init.dart`).
   Анхны deploy-ын дараа https://diplom-23056.web.app/__/firebase/init.json
   нээж `apiKey`, `appId`, `projectId` байгааг шалгана. `appId` байхгүй бол
   Firebase Console → Project settings → Your apps → Web app
   (`1:464701040005:web:8b1bbfc349926d481a10ec`) → *Firebase Hosting*-д
   `diplom-23056` сайтыг холбоно.

   Өөр нэг арга: GitHub → Settings → Secrets → `FIREBASE_WEB_API_KEY` нэмбэл
   workflow түүнийг build-д оруулна (вэбийн apiKey нууц биш — browser бүрт
   очдог; хамгаалалт нь authorized domains ба Firestore rules).

4. **Анхны байршуулалт:** GitHub → Actions → *Refresh AI signals and deploy
   web* → *Run workflow* (эсвэл main-д merge хийнэ). Дуусмагц
   https://diplom-23056.web.app нээгдэнэ.

## Дотоод хөгжүүлэлт (Chrome)

```
copy web_config.example.json web_config.json
```

`web_config.json`-д Firebase Console → Project settings → Your apps → Web
app-ын `apiKey`-г бичнэ (файл `.gitignore`-д байгаа, commit хийгдэхгүй).

```
flutter run -d chrome --dart-define-from-file=web_config.json
```

Энэ нь MSE-ийн ханш, AI дохиог байршуулсан сайтаас
(`https://diplom-23056.web.app/mse`, `/ai`) уншина.

**Анхны deploy-оос өмнө** бүх зүйлийг өөрийн компьютер дээр шалгах:

```
dart run tool/build_dataset.dart
dart run tool/publish_market.dart
flutter build web --release --dart-define-from-file=web_config.json --dart-define=MSE_DATA_URL=mse --dart-define=SIGNALS_URL=ai/signals.json
dart run tool/assemble_hosting.dart
python -m http.server 8765 --directory build/hosting
```

Дараа нь http://localhost:8765 нээнэ. (`build_dataset` анх удаа хувьцаа
бүрийн бүтэн түүхийг (~4MB) татдаг тул хэдэн минут болно.)

## Гараар байршуулах (GitHub Actions-гүй)

Дээрх `build_dataset` → `publish_market` → `flutter build web` (`MSE_DATA_URL`,
`SIGNALS_URL`-гүйгээр) → `assemble_hosting` алхмуудын дараа:

```
firebase deploy --only hosting
```

Нийтлэгдсэн дохионы түүхийг хадгалахын тулд эхлээд
https://diplom-23056.web.app/ai/signal_log.json-ийг `tool/data/signal_log.json`
руу татаж аваарай. Үгүй бол `ai/signal_log.json` дараагийн deploy хүртэл алга болно.

## Хязгаарлалт

- Вэб дээрх MSE-ийн ханш өдөрт нэг удаа (хаалтын дараа) шинэчлэгдэнэ.
  Дэлгэцийн толгойд "…-ийн байдлаар" гэж огноо нь харагдана.
- Spark (үнэгүй) төлөвлөгөөнд Hosting-ийн татаж авах хэмжээ өдөрт 360MB.
  Апп-ыг анх нээхэд ~1–2MB (CanvasKit-ийг Google-ийн CDN-ээс татна) тул
  дипломын үзүүлэнд хангалттай.
- GitHub-ийн хуваарьт ажил 60 хоног идэвхгүй repo-д зогсдог —
  [signals_pipeline.md](signals_pipeline.md)-г үз.

## Алдаа засах

| Шинж тэмдэг | Шалтгаан / шийдэл |
|---|---|
| "Апп эхлүүлэхэд алдаа гарлаа … init.json" | Дээрх 3-р алхам: web app-ыг Hosting сайттай холбох эсвэл `FIREBASE_WEB_API_KEY` secret. Дотоодод `--dart-define-from-file=web_config.json`. |
| `auth/unauthorized-domain` | 2-р алхам: домайныг Authorized domains-д нэмэх. |
| Зах зээл: "MSE-ийн нийтлэгдсэн өгөгдөл: HTTP 404" | Workflow хараахан амжилттай ажиллаагүй — Actions-аас шалгах. |
| Ханшийн огноо хуучирсан | Actions-д сүүлийн ажиллагаа унасан (MSE сайт унасан г.м.); хуучин өгөгдөл хэвээр үлдэнэ. |
