# Notatki z sesji `/ucz` — co warto poprawić w tym projekcie

> Powstało w trakcie interaktywnej sesji nauki (`/ucz`) nad konfiguracją projektu
> `dbt-bigquery`. Dwa cele: (1) surowiec do artykułu na blog o praktycznych
> usprawnieniach projektu dbt na BigQuery, (2) kontekst dla przyszłej sesji
> Claude Code, która ma te poprawki realnie wdrożyć w kodzie.
>
> Aktualizowane co 5–10 pytań sesji, nie po każdym. Ostatnia aktualizacja:
> pytanie 23/24, sesja z 2026-09-21/22.

## Jak czytać tę listę

Każdy punkt: **problem → dlaczego to ma znaczenie → poprawka**. Numeracja odpowiada
numerom pytań w sesji `/ucz`, dla odtworzenia kontekstu rozumowania.

---

## 1. Separacja dev/prod (profiles.yml.example) — pytania 2, 4

**Problem:** dev i prod dzielą to samo konto serwisowe i ten sam projekt GCP —
różni je tylko nazwa datasetu.

**Dlaczego ma znaczenie:** brak izolacji IAM. Jedna pomyłka (`--target prod`
odpalone przypadkiem, błąd w hooku, wyciekły keyfile) nadpisuje prod. Brak
śladu audytowego per osoba — w logach BigQuery wszystko figuruje pod tym samym
SA. Wspólna pula slotów i limity współbieżności on-demand.

**Poprawka:**
- Osobne SA per środowisko: SA deweloperskie ma prawa zapisu wyłącznie do
  `dbt_dev_*`, docelowo osobny projekt GCP dla prod.
- Dla dev/lokalnej pracy: OAuth albo impersonation zamiast keyfile SA — ślad
  per osoba.
- W CI/CD: Workload Identity Federation zamiast długożyjącego keyfile.

**Brakujący guardrail kosztowy — pytanie 5:** w profilu nie ma
`maximum_bytes_billed`. `job_execution_timeout_seconds` (limit czasu) i
`priority` tego nie zastępują — przypadkowe zapytanie skanujące terabajty
przechodzi bez blokady, bo BigQuery rozlicza bajty, nie czas. Dodać do obu
targetów, np. 10 GiB dev / 100 GiB prod (wartości do dostrojenia pod realny
rozmiar danych).

---

## 2. `threads: 64` nieadekwatne do rozmiaru projektu — pytania 3, 4

**Problem:** `threads: 64` w obu targetach, przy DAG-u złożonym z ~7-8 modeli
bez rodziców (kilkanaście węzłów licząc testy w `dbt build`).

**Dlaczego ma znaczenie:** to nie szkodzi *teraz* — DAG nigdy nie zbliży się do
64 — ale to mylący sygnał przy kopiowaniu configu do większego projektu, i
błędna intuicja: BigQuery on-demand nie ma warehouse'u do przeciążenia jak
Snowflake, więc `threads` nie wpływa na koszt, tylko na czas ścienny i zajętość
wspólnej puli projektu.

**Poprawka:** 8–16, zweryfikować empirycznie przez `dbt build --threads N` i
porównanie `execution_time` w `target/run_results.json`.

---

## 3. `+hours_to_expiration` niszczy sens incremental w dev — pytania 6–9

**Problem:** globalny default `hours_to_expiration: 1` w dev (dbt_project.yml,
klucz `models: ecommerce_analytics:`) obejmuje też jedyny model incremental —
`stg_ecommerce__events`. Tabela znika po godzinie, więc kolejny `dbt run` w
dev prawie zawsze robi pełny rebuild (`is_incremental()` = false), zamiast
przejść ścieżką `MERGE`.

**Dlaczego ma znaczenie:** ścieżka incremental (filtr `is_incremental()`,
`MERGE` po `unique_key`) prawie nigdy nie jest realnie testowana w dev —
błąd w tej logice wyjdzie dopiero w prod. To opt-out (wszystko wygasa, chyba
że nadpisane) zamiast opt-in — łatwo zapomnieć o wyjątku przy nowym modelu
incremental/snapshot.

**Poprawka:** nadpisać w `config()` modelu `stg_ecommerce__events`:
`hours_to_expiration=none`. Docelowo rozważyć odwrócenie defaultu na opt-in
(expiration tylko dla wybranych folderów/modeli, nie globalnie).

**Dodatkowo — kruchy zapis wartości:** w `target/manifest.json` wartość
`hours_to_expiration` dla `stg_ecommerce__events` to string `' 1\n'`, nie
liczba. Działa przypadkiem (adapter wstawia to jako tekst do SQL), ale warto
zapisać czyściej: `"{{ 1 if target.name == 'dev' else 168 }}"` i zweryfikować
typ w manifeście po zmianie.

**Błędny komentarz w kodzie (dbt_project.yml, linie ~53–55):** opisuje 7-dniowy
expiration w prod jako "bufor bezpieczeństwa". To odwrotne znaczenie —
expiration to zegar **kasujący** dane, nie zabezpieczenie. Ryzyko: cicha utrata
danych po 7 dniach, `dbt run` pozostaje zielony, zauważy to dopiero BI/analityk
trafiając na "table not found". Poprawić komentarz + rozważyć, czy prod
w ogóle powinien mieć auto-expiration.

---

## 4. Domyślna materializacja `table` dla staging nie skaluje się — pytanie 10

**Problem:** `+materialized: table` jako default dla całego projektu,
uzasadnione komentarzem "dataset jest mały".

**Dlaczego ma znaczenie:** przy większym źródle (np. 500 GB) codzienny pełny
rebuild staging jako `table` generuje niepotrzebny koszt compute (dominujący
nad storage — orientacyjnie rząd 85 USD/mies. skanu vs 9 USD/mies. storage przy
takiej skali) w porównaniu do `view`, który płaci tylko przy odpytaniu.

**Poprawka:** udokumentować założenie explicité jako "działa dla obecnej skali
publicznego datasetu demo, do rewizji przy wzroście źródła". W realnym
projekcie: `view` dla staging, `table`/`incremental` tylko tam, gdzie realnie
się opłaca (marty, duże/często odpytywane źródła).

---

## 5. UDF przez hook `on-run-start` — nadmiarowa architektura — pytanie 11

**Problem:** `get_brand_name()` — jednolinijkowy `REGEXP_EXTRACT` — jest
zaimplementowany jako trwały UDF w BigQuery, tworzony przez hook
`on-run-start` przy **każdym** dbt run/test/seed/snapshot/build, zamiast jako
makro Jinja rozwijane inline w SQL-u modelu.

**Dlaczego ma znaczenie:** to ilustracja mechanizmu hooków z kursu, nie
decyzja projektowa — dodaje job przy każdej komendzie i obiekt w bazie
niewidoczny w lineage dbt, bez realnego uzasadnienia (logika użyta w jednym
miejscu).

**Poprawka:** w realnym projekcie zastąpić makrem inline, chyba że logikę
faktycznie muszą wołać konsumenci spoza dbt (BI, analitycy w konsoli).

---

## 6. Globalny default `severity: warn` — odwrócony kierunek — pytania 12–15

**Problem:** `tests: ecommerce_analytics: +severity: warn` jako default,
z jednym jedynym wyjątkiem (`primary_key` na `stg_ecommerce__orders.order_id`
ma `error`). Reszta testów integralności na kolumnach, które są kluczami
joinów/agregacji w dalszych modelach — `user_id` (`not_null`), `created_at`
(`not_null`) — dziedziczy `warn`.

**Dlaczego ma znaczenie:** `warn` nie blokuje `dbt build` — model zależny
(`dim_orders`) buduje się dalej nawet gdy test na kluczu joina pada. Komentarz
w `dim_orders.yml`, że mart "ufa testom w staging", jest więc tylko częściowo
prawdziwy: ufa istnieniu testu, nie temu, że test cokolwiek blokuje.

**Poprawka:** podnieść do `error` testy na kolumnach będących kluczami
joinów/agregacji (`user_id`, `created_at` w `stg_ecommerce__orders.yml`).
Zostawić `warn` dla czysto biznesowych/kosmetycznych reguł (statusy,
sekwencje timestampów). Dodać routing alertów dla `warn` — bez tego nikt ich
nie widzi (Slack/PagerDuty/tabela z `--store-failures`).

---

## 7. `stg_ecommerce__events` — brak okna wstecznego w filtrze incremental — pytanie 16

**Problem:** `WHERE created_at > (SELECT MAX(created_at) FROM {{ this }})`
bez marginesu na spóźnione dane (late-arriving events).

**Dlaczego ma znaczenie:** event, który dociera do źródła z opóźnieniem (ma
poprawny, stary `created_at`), zostaje trwale pominięty i zgubiony — bez
błędu, build zostaje zielony. Analogia z Twojego stacku: eksport GA4 do
BigQuery ma podobne opóźnienia (do ~72h), stąd standardowa praktyka okna
wstecznego 2-3 dni w modelach incremental na danych eventowych.

**Poprawka:**
```sql
{% if is_incremental() %}
WHERE created_at > TIMESTAMP_SUB((SELECT MAX(created_at) FROM {{ this }}), INTERVAL 3 DAY)
{% endif %}
```
`unique_key='event_id'` (już jest) deduplikuje nakładające się dni przez
`MERGE`.

---

## 8. `on_schema_change='sync_all_columns'` — ryzyko cichej utraty danych — pytanie 17

**Problem:** komentarz w kodzie myli "zmianę w źródle" ze "zmianą w SELECT
modelu" — to drugie faktycznie uruchamia mechanizm (dbt porównuje kolumny
wyniku modelu z istniejącą tabelą przy edycji `.sql`, nie przy zmianie
źródła).

**Dlaczego ma znaczenie:** `sync_all_columns` może wykonać ciche
`DROP COLUMN` (z utratą danych tej kolumny) przy edycji modelu, bez
ostrzeżenia.

**Poprawka:** dla tabeli będącej jedynym miejscem z historią rozważyć
`append_new_columns` (nigdy nie kasuje) albo `fail` (wymusza świadomą
decyzję) zamiast cichej synchronizacji. Poprawić komentarz w kodzie, żeby
opisywał faktyczny trigger.

---

## 9. `MERGE` bez `incremental_predicates` — koszt rośnie z całą historią — pytania 18–19

**Problem:** brak `incremental_predicates` w configu `stg_ecommerce__events`.
Warunek `ON` w generowanym `MERGE` nie zawiera predykatu na kolumnie
partycjonującej, więc BigQuery nie może wykluczyć żadnej partycji strony
docelowej przy szukaniu dopasowań — `MERGE` skanuje całą historię tabeli
(3 lata), nie tylko nową porcję.

**Poprawka:**
```sql
config(
    materialized='incremental',
    unique_key='event_id',
    incremental_predicates=["DBT_INTERNAL_DEST.created_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 3 DAY)"]
)
```

**Gotcha do zapamiętania przy wdrażaniu razem z punktem 7:** okno
`incremental_predicates` musi być **≥** okno filtra źródła. Jeśli predicate
window jest węższe, `MERGE` nie znajdzie dopasowania dla starszych powtórzonych
wierszy (bo strona `DBT_INTERNAL_DEST` jest przycięta predykatem) i wstawi
**duplikat** zamiast zrobić `UPDATE`. Oba okna trzymać na tej samej wartości
(np. 3 dni).

---

## 10. Rzeczy sprawdzone i **uznane za poprawne** (nie zmieniać)

- **`partition_by` po dniu, nie po godzinie** (`stg_ecommerce__events`) —
  poprawna decyzja: limit liczby partycji na tabelę w BigQuery. Przy `day`
  daje to ~11 lat historii do limitu, przy `hour` tylko ~166 dni (niecałe pół
  roku) dla tabeli rosnącej bezterminowo. Warto tylko dopisać w komentarzu
  konkretne liczby, nie tylko ogólnikowe "zbyt granularne".
- **Source freshness zdefiniowany tylko dla `events`**, nie dla pozostałych
  źródeł — świadomie poprawne. `orders.created_at` i podobne to timestampy
  biznesowe (moment zdarzenia), nie load-time, a `thelook_ecommerce` to
  prawdopodobnie statyczny dataset demo — freshness na takiej kolumnie
  dawałby fałszywe alarmy. Warto dopisać to uzasadnienie wprost w
  `src_ecommerce.yml`, żeby nikt "nie naprawił" tego przez dodanie freshness
  wszędzie.
- **`target_schema='snapshots_project'` zapisany na sztywno** — sprawdzone
  grepem: brak customowego makra `generate_schema_name` w repo, więc dbt
  domyślnie prefiksuje `target.schema`. Dev i prod dostają osobne datasety
  (`dbt_dev_project_snapshots_project` / `dbt_prod_project_snapshots_project`)
  — **nie kolidują**. Wartość na sztywno (nie przez `env_var`) odróżnia się od
  reszty configu wrażliwego na środowisko w repo — kosmetyka do ujednolicenia,
  nie błąd.

---

## 11. Znaleziska mechaniczne, do zapamiętania (nie wymagają zmiany kodu)

- **Source freshness (`error_after: 24h`) nie blokuje `dbt build`** —
  `dbt source freshness` to osobna komenda, nie krok wewnątrz `dbt build`
  (seed → snapshot → run → test). W tym repo nic nie spina wyniku freshness
  z pipeline'em. Żeby to realnie egzekwować, trzeba w CI/orkiestracji dodać
  jawny gate: krok 1 `dbt source freshness`, sprawdzenie exit code, dopiero
  potem `dbt build`.
- **`threads` w dbt vs sloty w BigQuery** — to dwie różne warstwy (klient vs
  serwer). `threads` ogranicza, ile jobów dbt wysyła naraz; sloty to zasób
  obliczeniowy po stronie BigQuery, przydzielany dynamicznie per job
  (on-demand) albo kupowany z góry (capacity/reservations). W modelu
  on-demand rachunek liczy bajty zeskanowane przez job, nie liczbę wątków ani
  slotów.

---

## Do artykułu — kandydaci na osobne sekcje

1. "Dlaczego `threads: 64` nic nie robi w małym projekcie dbt" — mechanizm
   DAG → thread → job → slot, z tabelą porównawczą Snowflake vs BigQuery
   on-demand.
2. "Global default expiration, który po cichu zabija Twój model incremental"
   — punkt 3, z konkretnym przykładem `hours_to_expiration`.
3. "`severity: warn` to nie 'miękki test' — to brak testu" — punkt 6, różnica
   między "reguła zdefiniowana" a "reguła egzekwowana", z tym samym motywem
   przy source freshness (punkt 11).
4. "Koszt `MERGE` w dbt incremental rośnie z historią tabeli, nie z nową
   porcją danych" — punkty 7 i 9 razem, z gotchą `incremental_predicates`.
