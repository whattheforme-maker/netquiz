# NetQuiz — CCNA tayyorgarlik

Sayt CCNA savollar bankini interaktiv testga aylantiradi. `questions.js` faylida 1 009 ta savol va 276 ta rasm bor. Yakka testlar offline ishlaydi; progress brauzer xotirasida saqlanadi. Guruh xonalari Supabase orqali ishlaydi.

## Ishlatish va hostga joylash

`index.html`, `questions.js` va `supabase-config.js` fayllarini bir papkada saqlang. GitHub Pages’da **Settings → Pages** orqali `main` branch va `/ (root)` papkasini yoqing. Uchala faylni repository asosiy papkasiga yuklang.

## Supabase’ni bir marta sozlash

1. Supabase Dashboard → **Authentication → Sign In / Providers** bo‘limida **Anonymous sign-ins**’ni yoqing.
2. **SQL Editor**’da [supabase-schema.sql](./supabase-schema.sql) faylidagi SQL’ni bir marta ishga tushiring.
3. **Database → Publications** bo‘limida `supabase_realtime` uchun `netquiz_rooms` va `netquiz_participants` jadvallarini yoqing.
4. `supabase-config.js` faylida Supabase **Project URL** va brauzer uchun **Publishable key** bo‘lishi kerak. URL formati `https://<project-ref>.supabase.co`; oxiriga `/rest/v1/` qo‘shilmaydi.
5. Uchala faylni hostingga yuklang. Foydalanuvchilar akkaunt yaratmaydi: sayt har bir brauzer uchun anonim Supabase sessiyasini ochadi; xona kodi yoki havola orqali bir testga birlashadi.

Publishable key brauzerda ishlatish uchun mo‘ljallangan ochiq kalit. `service_role` yoki secret key’ni `index.html`, konfiguratsiya fayli yoki boshqa frontend kodga qo‘ymang. RLS siyosatlari ma’lumotlarni xona a’zolari bilan cheklaydi; ularni qo‘llamasdan jadvallarni ochiq qoldirmang.
