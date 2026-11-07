# NetQuiz — CCNA tayyorgarlik

Sayt CCNA savollar bankini interaktiv testga aylantiradi. `questions.js` faylida 1 009 ta savol va 276 ta rasm yo‘li bor; rasm fayllari `images/` papkasida alohida saqlanadi va faqat kerak bo‘lganda yuklanadi. Yakka testlar offline ishlaydi; progress brauzer xotirasida saqlanadi. Guruh xonalari Supabase orqali ishlaydi.

## Ishlatish va hostga joylash

Lokal sinash uchun `npx serve` buyrug‘ini ishga tushiring. Hostga `index.html`, `questions.js`, `supabase-config.js` fayllari va butun `images/` papkasini deploy qiling. GitHub Pages’da **Settings → Pages** orqali `main` branch va `/ (root)` papkasini yoqing.

`extract-images.js` bir martalik migratsiya skripti: u base64 rasmlarni `images/` papkasiga chiqaradi. Muvaffaqiyatli ishlagandan keyin uni qayta ishga tushirish shart emas; skriptni migratsiya uchun repo’da qoldirish mumkin. `questions.backup.js` Git’ga qo‘shilmaydi.

## Supabase’ni bir marta sozlash


1. Supabase Dashboard → **Authentication → Sign In / Providers** bo‘limida **Anonymous sign-ins**’ni yoqing.
2. **SQL Editor**’da [supabase-schema.sql](./supabase-schema.sql) faylidagi SQL’ni bir marta ishga tushiring.
3. **Database → Publications** bo‘limida `supabase_realtime` uchun `netquiz_rooms` va `netquiz_participants` jadvallarini yoqing.
4. `supabase-config.js` faylida Supabase **Project URL** va brauzer uchun **Publishable key** bo‘lishi kerak. URL formati `https://<project-ref>.supabase.co`; oxiriga `/rest/v1/` qo‘shilmaydi.
5. Sayt fayllari va `images/` papkasini hostingga yuklang. Foydalanuvchilar akkaunt yaratmaydi: sayt har bir brauzer uchun anonim Supabase sessiyasini ochadi; xona kodi yoki havola orqali bir testga birlashadi.

Publishable key brauzerda ishlatish uchun mo‘ljallangan ochiq kalit. `service_role` yoki secret key’ni `index.html`, konfiguratsiya fayli yoki boshqa frontend kodga qo‘ymang. RLS siyosatlari ma’lumotlarni xona a’zolari bilan cheklaydi; ularni qo‘llamasdan jadvallarni ochiq qoldirmang.

Avval schema faylini, keyin [supabase-room-cleanup.sql](./supabase-room-cleanup.sql) migratsiyasini SQL Editor’da bajaring. Cron sozlamasini tekshirish uchun:

```sql
select jobname, schedule, active
from cron.job
where jobname = 'netquiz-inactive-room-cleanup';
```

Migratsiya xona egasi chiqsa xonani `closed` qiladi, 5 daqiqadan ortiq faol bo‘lmagan ishtirokchilar/xonalarni tozalash funksiyasi va 10 daqiqalik `pg_cron` vazifasini o‘rnatadi. Cleanup funksiyasiga `anon`, `authenticated` yoki `service_role` bevosita kira olmaydi.
