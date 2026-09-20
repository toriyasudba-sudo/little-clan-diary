# Little Clan Diary — загрузка в GitHub с телефона

1. Открой репозиторий `little-clan-diary`.
2. Нажми `Add file` → `Upload files`.
3. Распакуй этот архив на телефоне.
4. Выбери все файлы и папки из папки `little-clan-diary` и загрузи их в корень репозитория.
5. Нажми `Commit changes`.
6. После загрузки открой `Settings` → `Pages`.
7. В `Build and deployment` выбери `GitHub Actions`, если такой пункт доступен.
8. Если GitHub покажет workflow `Deploy to GitHub Pages`, запусти/дождись его выполнения во вкладке `Actions`.

Важно:
- Не загружай файл `Little_Clan_Diary_KEEP_PRIVATE_VAPID_SECRETS.txt`.
- Не публикуй VAPID private key.
- Publishable Supabase key в `index.html` предназначен для клиентского приложения; секретный Supabase key туда не помещается.
