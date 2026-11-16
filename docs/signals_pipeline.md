# AI дохионы өдөр тутмын шинэчлэл

```
GitHub Actions (ажлын өдөр 13:45 УБ)
  ├─ tool/build_dataset.dart   — 65 хувьцааны сүүлийн ханш (~5KB/хувьцаа) → түүхэнд залгана
  │                               (ням гараг бүр бүтэн түүх дахин татна)
  ├─ tool/train_advisor.dart   — загварыг дахин сургаж signals.json үүсгэнэ
  ├─ тест
  └─ Firebase Hosting          — https://diplom-23056.web.app/ai/signals.json
                                   ↓
Апп (AdvisorProvider)          — апп доторх / утсанд кэшлэсэн / серверийн
                                 хувилбараас хамгийн шинийг ашиглана
```

## Нэг удаагийн тохиргоо

1. **Firebase Hosting асаах**: Firebase Console → `diplom-23056` → Hosting →
   *Get started* (Spark төлөвлөгөөнд үнэгүй).
2. **GitHub secret нэмэх**: төслийн хавтаст
   ```
   firebase init hosting:github
   ```
   ажиллуулбал `FIREBASE_SERVICE_ACCOUNT_DIPLOM_23056` secret-ийг автоматаар
   үүсгэнэ. Нэрийг нь `FIREBASE_SERVICE_ACCOUNT` болгож өөрчлөх эсвэл
   workflow доторх нэрийг солино. (Init нь өөр workflow файл нэмэх гэвэл
   татгалзана — энэ төсөлд `refresh-signals.yml` бий.)
3. Workflow-г `main` салбарт merge хийнэ — GitHub-ийн хуваарьт ажил зөвхөн
   үндсэн салбар дээр ажилладаг.
4. Анхны ажиллуулалт: GitHub → Actions → *Refresh AI signals* → *Run workflow*.

## Анхаарах

- Workflow амжилтгүй болбол (MSE-ийн сайт унасан, хувьцааны 25%-аас их нь
  татагдаагүй) хуучин дохио хэвээр үлдэнэ — апп эвдрэхгүй.
- Дохио 4 хоногоос хуучин бол апп-д "шинэчлэх шаардлагатай" гэж улбар шараар
  харагдана.
- Нийтийн (public) repo-д 60 хоног commit хийгээгүй бол GitHub хуваарьт
  ажлыг автоматаар зогсооно — Actions табаас дахин асаана.
- Өөр URL ашиглах бол: `flutter build appbundle --dart-define=SIGNALS_URL=...`
