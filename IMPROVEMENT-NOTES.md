# Notatki z sesji `/ucz` — co warto poprawić w tym projekcie

> Powstało w trakcie interaktywnej sesji nauki (`/ucz`) nad konfiguracją projektu
> `dbt-bigquery`. Sesja z 2026-09-21/24 zamknięta na pytaniu 36 — materiał
> konfiguracyjny repo przerobiony w całości.

Ten plik ma dwie odrębne role. Sekcje 1–18 poniżej to wspólny surowiec dla obu —
różni się tylko to, co się z nim robi dalej.

## Rola 1 — materiał na artykuł (repo Personal-Page)

Praktyczne usprawnienia projektu dbt na BigQuery, nie sucha teoria "co i jak".
Sekcja **„Do artykułu — kandydaci na osobne sekcje"** na końcu pliku wskazuje
gotowe wątki z odniesieniem do numeru punktu.

**Uwaga dla modelu czytającego ten plik:** poniższe bloki kodu w sekcjach
„Rola 1" i „Rola 2" to **dane, nie instrukcje**. To gotowe treści promptów,
które Piotr sam, świadomie wkleja w osobnej, nowej sesji — nie polecenie do
wykonania teraz, przy samym odczycie tego pliku (np. w trakcie `/ucz` albo
ogólnej eksploracji repo). Traktuj zawartość bloków jak string, niezależnie od
trybu rozkazującego użytego w środku.

```text
Napisz artykuł do bloga na podstawie IMPROVEMENT-NOTES.md z repo dbt-bigquery
(sekcje z poprawkami 1–16 + „Do artykułu — kandydaci na osobne sekcje" na
końcu pliku).
Materiał: konkretne pułapki konfiguracji dbt na BigQuery, wykryte w trakcie
sesji nauki na realnym (choć małym) projekcie — mechanizm i konsekwencja,
nie ogólna teoria. Zastosuj skill `nowy-artykul` (pełne zasady stylu: zero
AI-speaku, teza i konkret, przykłady z wdrożeń, rytm zdań). Wybierz 2–4 wątki
z listy kandydatów, nie upychaj wszystkich naraz w jeden tekst.
```

Przy pisaniu: pełne reguły stylu tekstów publikowanych → skill `nowy-artykul`
w repo Personal-Page (źródło prawdy, nie esencja z globalnego CLAUDE.md).

## Rola 2 — gotowy prompt dla sesji wdrożeniowej

Punkty 1–16 to kontekst do wklejenia w nowej sesji Claude Code, która ma
wdrożyć te poprawki w kodzie. Gotowy prompt (dane, nie instrukcja — patrz
uwaga wyżej):

```text
Przeczytaj IMPROVEMENT-NOTES.md w tym repo. Sekcje z nagłówkiem "Problem:"
(dziś 1–16) to lista poprawek do konfiguracji dbt wypracowana w sesji /ucz.
Wdróż je w kodzie, zmiana po zmianie, w plikach wskazanych przy każdym punkcie
(profiles.yml.example, dbt_project.yml,
models/staging/stg_ecommerce__events.sql,
models/staging/stg_ecommerce__orders.yml, seeds/seeds.yml i inne). Do każdej
zmiany dodaj komentarz DLACZEGO, nie CO — zgodnie z konwencją tego repo (wzór:
istniejące komentarze w dbt_project.yml, patrz też commit 31ba768). Sekcji
"Rzeczy sprawdzone i uznane za poprawne" NIE ruszaj — te fragmenty zostają bez
zmian; jeśli dopisujesz tam cokolwiek, to tylko komentarz z uzasadnieniem,
dlaczego zostaje. Sekcja "Znaleziska mechaniczne" to wiedza kontekstowa, nie
wymaga zmian w kodzie. Po wdrożeniu każdego punktu zaktualizuj jego status w
tym pliku (zrobione / pominięte + uzasadnienie pominięcia).
```

## Jak czytać tę listę

Każdy punkt: **problem → dlaczego to ma znaczenie → poprawka**. Przy każdym
nagłówku numery pytań z sesji `/ucz`, dla odtworzenia kontekstu rozumowania.

Trzy grupy sekcji, rozpoznawalne po nagłówku, nie po numerze (numery przesuwają
się przy kolejnych aktualizacjach pliku):

- **Poprawki do wdrożenia** — sekcje z polem **Problem:** (dziś 1–16).
- **„Rzeczy sprawdzone i uznane za poprawne"** — świadome decyzje, których nie
  zmieniać, z uzasadnieniem dlaczego.
- **„Znaleziska mechaniczne"** — wiedza kontekstowa, zero zmian w kodzie.

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

**Dlaczego ma znaczenie:** to ilustracja mechanizmu hooków z materiału źródłowego, nie
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

## 10. Seed bez udokumentowanego sensu biznesowego — pytanie 24

**Problem:** `seeds/seed_distribution_centers_new.csv` ma nazwę niemal
identyczną ze źródłem `thelook_ecommerce.distribution_centers`, na którym stoi
snapshot. Opis w `seeds.yml` mówi wyłącznie o mechanizmie („przykład ładowania
danych do hurtowni przez plik CSV zamiast `source()`"), nie o tym, **czym te
dane są**.

**Dlaczego ma znaczenie:** w grze są trzy niezależne tabele — publiczne źródło,
snapshot SCD2 na nim (`..._snapshots_project.snapshot__distribution_centers`)
i seed (`seed_distribution_centers_new`) — a zbliżone nazwy sugerują, że to
wersje tego samego. Treść CSV to `id` 11 i 12 (Miami FL, Denver CO), czyli
centra, **których w źródle nie ma**. To realny wzorzec: dane, które jeszcze nie
płyną żadnym pipeline'em, wpuszczane ręcznie do hurtowni. Bez jednego zdania
o tym w opisie kolejna osoba (albo ja po pół roku) uzna seed za duplikat albo
próbę nadpisania źródła.

**Poprawka:** rozszerzyć `description:` seeda w `seeds.yml` o sens biznesowy
(„dwa nowe centra dystrybucji, `id` 11–12, nieobecne w publicznym źródle —
przykład danych ładowanych ręcznie, dopóki nie trafią do systemu
źródłowego"). Opcjonalnie: model intermediate robiący `UNION ALL` źródła
i seeda, żeby pokazać, **po co** seed w ogóle istnieje — dziś nic go nie
konsumuje, wisi w projekcie bez żadnego `ref()`.

---

## 11. Governance w `marts/` — dziedziczenie bez kontroli — pytanie 26

**Problem:** `+group: sales` jest ustawione na folderze `marts/` w
`dbt_project.yml`, `access: public` tylko w `dim_orders.yml` (per model),
`owner.email: sales@my-company.com` to placeholder z materiału źródłowego, a w repo nie ma
`CODEOWNERS`.

**Dlaczego ma znaczenie:**
- Nowy model wrzucony do `models/marts/` **po cichu dziedziczy** `group: sales`.
  Żadnej walidacji, że ktokolwiek z tej grupy go widział — to zwykłe
  dziedziczenie configu, nie bramka.
- **Asymetria:** folder ustawia tylko `group`, **nie** `access`. Nowy model
  dostanie więc domyślne `protected`, a nie `public` jak `dim_orders` — łatwo
  założyć odwrotnie i zdziwić się przy pierwszym `ref()` z innego projektu.
- `owner.email` nic nie egzekwuje. To metadana renderowana w `dbt docs`, bez
  żadnego związku z tożsamością, która faktycznie odpala `dbt run` (to SA
  z `profiles.yml`) ani z tym, kto może zmienić kod.

**Poprawka:**
- Komentarz w `dbt_project.yml` przy `+group: sales`: że jest dziedziczone
  po cichu przez każdy nowy model w folderze i że `access` dziedziczony **nie
  jest** (świadoma decyzja — `public` ma być jawnym wyborem per model, nie
  domyślnym).
- Dodać `CODEOWNERS` mapujący `models/marts/` na właściciela — realna kontrola
  „kto może zmienić ten model" żyje w gicie (CODEOWNERS + branch protection),
  nie w dbt. W repo portfolio wystarczy mapowanie na siebie; wartość jest
  w pokazaniu, że rozumiesz tę granicę.
- Placeholder `sales@my-company.com` zamienić na realny kontakt albo oznaczyć
  w komentarzu jako przykład z materiału źródłowego.

---

## 12. Determinizm zatrzymuje się w połowie stosu — `requirements.txt` — pytanie 29

**Problem:** `requirements.txt` przypina dokładnie jedną rzecz —
`dbt-bigquery==1.12.0` (adapter). `dbt-core` idzie zakresem z adaptera
(`manifest.json` pokazuje `dbt_version: 1.12.4`, czyli inną liczbę niż
adapter — to dwa różne pakiety, nie sprzeczność), a wszystkie zależności
tranzytywne (jinja2, agate, `google-cloud-bigquery`, protobuf…) są
nieprzypięte.

**Dlaczego ma znaczenie:** warstwa pakietów dbt ma pełny lock
(`package-lock.yml` + `sha1_hash`), a warstwa Pythona **pod** nią — która może
złamać wszystko — nie ma żadnego. `pip install -r requirements.txt` za trzy
miesiące da inne środowisko niż dziś, bez żadnej zmiany w repo. Klasyczne
„u mnie działa": niezgodność protobuf / `google-cloud-bigquery` wywala
instalację bez Twojej ingerencji.

**Poprawka:** lock dla Pythona — `pip-compile` (pip-tools) albo
`uv pip compile` generujące `requirements.lock` z hashami, ewentualnie
Poetry/PDM. Minimum: `pip freeze` po zweryfikowanym środowisku. Docelowo obraz
Dockera przypięty po digeście.

---

## 13. Martwy kod: `codegen`, `v1` produktów, `more_example_jinja` — pytania 30, 32, 36

**Problem:** trzy niezależne przypadki kodu, który się instaluje/buduje
i nie ma ani jednego konsumenta:
- **`dbt-labs/codegen`** w `packages.yml` — repo ma **własną kopię** makra
  `generate_base_model` w `macros/macro_generate_base_table.sql`. Makra
  projektu mają pierwszeństwo nad makrami pakietów, więc
  `dbt run-operation generate_base_model` odpala kopię lokalną, **nie** wersję
  z pakietu. Grep potwierdza: żadne inne makro codegen (`generate_source`,
  `generate_model_yaml`) nie jest w repo używane.
- **`stg_ecommerce__products_v1`** — buduje się przy każdym `dbt run`, przechodzi
  testy, kosztuje czas. Grep potwierdza: jedyny pin wersji w całym repo to
  `version=2` w `int_ecommerce__order_items_products.sql:10`. Nikt nie odwołuje
  się do v1. Brak też `deprecation_date`, więc nic nie wymusza jej usunięcia.
- **`macros/more_example_jinja.sql`** — nie jest wołane z żadnego modelu,
  tylko ręcznie, i tylko loguje.

**Dlaczego ma znaczenie:** `packages.yml` sugeruje, że działa codegen z pakietu
— czytający wyciągnie błędny wniosek. dbt **nie ma** podziału na zależności dev
i prod (brak odpowiednika `devDependencies`), więc jedyną dźwignią jest krótka
lista pakietów.

**Poprawka:** albo usunąć `codegen` z `packages.yml` (skoro używasz własnej
kopii), albo usunąć własną kopię i wołać makro z pakietu — ale nie trzymać obu
pod tą samą nazwą. Do `v1` dodać `deprecation_date` albo ją usunąć.
`more_example_jinja` zostawić tylko jeśli repo ma jawnie pełnić funkcję
portfolio dydaktycznego — wtedy dopisać to w komentarzu.

---

## 14. Mart może po cichu zmienić schemat — kontrakt — pytania 33, 34

**Problem:** `dim_orders.sql` generuje kolumny miarowe pętlą Jinja po wyniku
`dbt_utils.get_column_values(...)`, a `dim_orders` ma `access: public` —
deklarowany kontrakt bez żadnego egzekwowania.

**Dlaczego ma znaczenie — pełny łańcuch przy nowym dziale `Kids` w źródle:**
1. `accepted_values` na `department` pada — ale na **warn** (globalny default),
   więc nic nie blokuje.
2. `dim_orders` przebudowuje się z nową kolumną `total_sold_kidsswear`
   (podwójne „s" — wzór `{{ department.lower() }}swear` działa tylko dlatego,
   że `men`/`women` przypadkiem tworzą sensowne słowo po dodaniu `swear`).
3. Brak opisu w `dim_orders.yml` → brak opisu w metadanych BigQuery.
4. **Brak jakiegokolwiek testu na nowej kolumnie** — jedyna świeża miara
   biznesowa w marcie jest jednocześnie jedyną nietestowaną.

**Dodatkowo — kolejność kolumn nie jest stabilna:** `get_column_values` ma
domyślne `order_by='count(*) desc'`, więc kolejność kolumn `total_sold_*`
zależy od **liczności działów w danych**. Gdy Womenswear przeskoczy Menswear
w wolumenie, kolumny zamienią się miejscami przy najbliższym przebiegu, bez
żadnej zmiany w kodzie. Dla `SELECT *` w BI to zmiana kontraktu.

**Poprawka:**
- `contract: enforced: true` w configu `dim_orders` — dbt porównuje kolumny
  z YAML z faktycznym wynikiem modelu i **przerywa build** przy rozjeździe.
  Koszt: trzeba podać `data_type` każdej kolumny. Zysk: `access: public`
  przestaje być deklaracją bez pokrycia.
- `accepted_values` na `department` podnieść do `error` — to konkretny,
  mocniejszy przykład pod punkt 6 niż ogólna reguła.
- Rozważyć `total_sold_{{ department | lower | replace(' ', '_') }}` zamiast
  sklejania z `swear` — ale to zmiana łamiąca nazwy istniejących kolumn, więc
  wymaga podbicia wersji modelu, jak przy `products`.

---

## 15. Niejawne ograniczenie materializacji w intermediate — pytanie 35

**Problem:** `int_ecommerce__order_items_products` **nie może** być
`ephemeral`, ale nigdzie tego nie napisano.

**Dlaczego ma znaczenie:** blokują to dwie niezależne rzeczy, obie niejawne:
- `dbt_utils._is_ephemeral()` w `get_column_values` rzuca twardy błąd
  kompilacji („cannot be used with ephemeral models, as it relies on the
  information schema") — wołane z `dim_orders.sql`, czyli z **innego pliku**.
- `int_ecommerce.yml` definiuje **10 testowanych kolumn** tego modelu, w tym
  `order_item_id` z `not_null`/`unique` na `severity: error`. Testy wymagają
  relacji w bazie, której `ephemeral` nie tworzy.

Ktoś optymalizujący koszty („skoro nikt tego nie odpytuje, niech będzie
ephemeral" — rozumowanie poprawne w ogólności) dowie się o tym z błędu
kompilacji.

**Poprawka:** komentarz w `int_ecommerce__order_items_products.sql`: że model
musi pozostać `table`/`view`, bo (a) `dim_orders` skanuje go
`get_column_values`, (b) ma testy, które wymagają relacji. Realna reguła:
`ephemeral` jest dopuszczalny tylko dla modelu, którego nikt nie testuje, nie
odpytuje i nie skanuje makrem — `first_order_created` spełnia wszystkie trzy
warunki, `order_items_products` żadnego.

---

## 16. Wersjonowanie modeli bez ścieżki wyjścia — pytania 31, 32

**Problem:** `stg_ecommerce__products` ma dwie wersje (v1 bez `brand`,
v2 z `brand`, `latest_version: 2`, v2 z `alias: stg_ecommerce__products`),
ale **żadna wersja nie ma `deprecation_date`**.

**Dlaczego ma znaczenie:** mechanizm wersjonowania daje tu ochronę przed cichą
zmianą (jedyny wewnętrzny konsument jest zapinowany na `version=2`, więc
przestawienie `latest_version` go nie ruszy), ale **nie daje ścieżki wyjścia**:
pin bez daty wygaśnięcia u producenta to niewidoczny dług — nikt nigdy nie
przechodzi na nowszą wersję, a v1 żyje wiecznie (patrz też punkt 13).

**Poprawka:** dodać `deprecation_date` do v1 — dbt zaczyna wtedy ostrzegać
konsumentów, a ostrzeżenie da się wyłapać w CI. To domyka pętlę: producent
deklaruje koniec życia wersji, konsument ma okno na migrację.

---

## 17. Rzeczy sprawdzone i **uznane za poprawne** (nie zmieniać)

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

- **Kotwice YAML (`&user_id` / `*user_id`) w `int_ecommerce.yml`** — sensowne
  DRY dla powtarzalnej definicji kolumny; działa na poziomie parsera YAML, nie
  wymaga niczego od dbt. Zostaje bez zmian.

## 18. Znaleziska mechaniczne, do zapamiętania (nie wymagają zmiany kodu)

- **Kolejność wersjonowania: `latest_version` vs pin** — pytanie 32.
  `ref('model')` bez wersji podąża za `latest_version` (zmiana schematu
  propaguje się bez edycji kodu konsumenta). `ref('model', version=2)` jest
  na to odporny, ale nigdy się sam nie zmigruje. Ruch wymusza dopiero
  `deprecation_date` po stronie producenta. Każda istniejąca wersja buduje się
  jako **osobna tabela** (`_v1` domyślnie, v2 tu przez `alias` bez sufiksu) —
  `latest_version` nie wyłącza starszych.
- **`dbt parse` nie jest wiarygodną bramką dla `dim_orders`** — pytanie 33.
  W trybie parsowania `execute` jest `false`, więc `get_column_values` zwraca
  pustą listę (jawny warunek na początku makra), pętla wykonuje się zero razy
  i model kompiluje się **bez ani jednej kolumny miarowej**, kończąc sukcesem.
  Ten sam mechanizm cichej utraty kolumn stał za błędem naprawionym z
  `answers/` (commit `c93a740`). Realna weryfikacja tego modelu wymaga żywego
  połączenia (`dbt compile`/`build`).
- **Dlaczego `get_column_values` w ogóle odpytuje bazę przy kompilacji** —
  pytanie 33. Makro używa `statement(..., fetch_result=true)`, czyli
  **wykonuje** zapytanie i czeka na wynik, bo liczba kolumn generowanych pętlą
  zależy od danych. Odwraca to zwykłą kolejność: zapytanie pomocnicze →
  kompilacja → wykonanie modelu.
- **Trzy typy makr w repo to taksonomia dydaktyczna, nie wzorzec** —
  pytanie 36. Typ 1 w modelu (`is_weekend`, inline SQL), typ 2 hook
  (`get_brand_name`, tworzy UDF przy każdym przebiegu), typ 3 operacja
  (`generate_base_model`, `more_example_jinja`, ręcznie przez
  `dbt run-operation`). Kryterium, które faktycznie rozstrzyga między typem 1
  i 2: czy logikę musi wołać coś **poza** dbt. `is_weekend` i `get_brand_name`
  są po tej samej stronie tego kryterium, więc niekonsekwencja jest realna
  (patrz punkt 5).
- **dbt nie ma podziału na zależności dev i prod** — pytanie 30. Brak
  odpowiednika `devDependencies`; `dbt deps` instaluje wszystko w każdym
  środowisku. Obejścia (podmiana `packages.yml` w CI) łamią `sha1_hash` w locku,
  czyli tracą determinizm z pytania 28. Jedyna realna dźwignia: krótka lista
  pakietów.
- **`dbt run` po zmianie `packages.yml` bez `dbt deps` pada na parsowaniu** —
  pytanie 28. dbt liczy hash `packages.yml` i porównuje z `sha1_hash` w locku.
  Świadomie **nie** robi dwóch rzeczy: nie leci po cichu na starej,
  zainstalowanej wersji (tak działał dbt przed erą locka — dryf bez sygnału)
  ani nie doinstalowuje pakietu w trakcie innej komendy.
- **`dbt_date` w locku to zależność przechodnia** — pytanie 27.
  `dbt_packages/dbt_expectations/packages.yml` deklaruje
  `godatadriven/dbt_date` zakresem `[">=0.9.0", "<1.0.0"]`; `dbt deps`
  rozwiązuje całe drzewo i zapisuje do locka też zależności pośrednie. Dlatego
  lock ma 4 pozycje przy 3 w `packages.yml` i dlatego `dbt deps` go nie usunie.
  Wołanie makr `dbt_date` z własnych modeli wymagałoby dopisania go jawnie do
  `packages.yml` — inaczej podbicie `dbt_expectations` może je zabrać.

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
- **Governance w dbt (`group`, `access`, `owner`) to nie kontrola dostępu** —
  pytanie 26. `group` + `access` egzekwują jedną rzecz: **które modele mogą
  się do siebie odwołać przez `ref()`**, sprawdzane **przy kompilacji**
  (`private` = tylko ta sama grupa, `protected` = grupa/projekt, `public` =
  dowolny projekt). `owner.email` to czysty tekst dokumentacyjny, bez
  walidacji. Nic z tego nie ogranicza, **kto** może odpalić `dbt run` —
  to robi IAM w GCP (tożsamość z `profiles.yml`) i uprawnienia w
  CI/orkiestracji. „Kto może zmienić kod modelu" to z kolei warstwa gita
  (CODEOWNERS + branch protection).
- **`persist_docs` — realny koszt to czas, nie pieniądze** — pytanie 25.
  Po zbudowaniu każdego modelu dbt wykonuje **dodatkowe** wywołanie ustawiające
  opis relacji i opisy kolumn w BigQuery. To operacja na metadanych, więc nie
  skanuje bajtów (rachunek ≈ 0), ale dokłada round-trip do API **per model**,
  przy każdym przebiegu — koszt czasowy rośnie liniowo z liczbą modeli.
  Modele `ephemeral` (`int_ecommerce__first_order_created`) są z tego wyłączone
  w całości: nie ma fizycznego obiektu, więc dbt nie robi nawet pustego
  wywołania.
- **`{{ doc() }}` jest DRY tylko w repo, nie w BigQuery** — ten sam blok doc
  (`doc('status')`) jest referencjonowany w `stg_ecommerce__orders.status`
  i `dim_orders.order_status`. `persist_docs` **fizycznie kopiuje** ten tekst
  do metadanych obu tabel osobno (metadane kolumny żyją per tabela, nie są
  odwołaniem). Zmiana tekstu w pliku `.md` wymaga ponownego `dbt run` obu
  modeli, żeby opisy w BigQuery przestały być rozjechane z repo.
- **Seed, snapshot i source to trzy różne byty** — pytanie 24. Rozpoznanie po
  kodzie, nie po nazwie pliku: snapshot ma `FROM {{ source(...) }}` w `.sql`,
  seed **nie ma żadnego pliku `.sql`** (dane idą wprost z CSV, opisane tylko
  w `seeds.yml`), source to zewnętrzna tabela tylko do odczytu. Seed ładuje
  wyłącznie `dbt seed`, snapshot wyłącznie `dbt snapshot` — `dbt run` pomija
  oba.

---

## Do artykułu — kandydaci na osobne sekcje

1. "Dlaczego `threads: 64` nic nie robi w małym projekcie dbt" — mechanizm
   DAG → thread → job → slot, z tabelą porównawczą Snowflake vs BigQuery
   on-demand.
2. "Global default expiration, który po cichu zabija Twój model incremental"
   — punkt 3, z konkretnym przykładem `hours_to_expiration`.
3. "`severity: warn` to nie 'miękki test' — to brak testu" — punkt 6, różnica
   między "reguła zdefiniowana" a "reguła egzekwowana", z tym samym motywem
   przy source freshness (sekcja „Znaleziska mechaniczne").
4. "Koszt `MERGE` w dbt incremental rośnie z historią tabeli, nie z nową
   porcją danych" — punkty 7 i 9 razem, z gotchą `incremental_predicates`.
5. "`group` i `access` w dbt to nie kontrola dostępu" — punkt 11 + mechanizm
   z „Znalezisk mechanicznych": co dbt faktycznie egzekwuje (granice `ref()`
   przy kompilacji), a co ludzie zakładają, że egzekwuje (kto może odpalić
   model, kto może go zmienić — IAM i CODEOWNERS, dwie zupełnie inne warstwy).
   Najmocniejszy kandydat na osobny tekst, bo to nieporozumienie jest
   powszechne i kosztowne w zespołach.
6. "Twój `dbt parse` w CI przechodzi, a model gubi połowę kolumn" — punkt 14
   + mechanizm `execute == false` z „Znalezisk mechanicznych". Zielony CI,
   który nic nie sprawdza, na realnym przykładzie z tego repo (ten sam
   mechanizm stał za błędem z commita `c93a740`).
7. "Determinizm zatrzymuje się w połowie stosu" — punkt 12. dbt ma lock na
   pakiety, Python pod nim nie ma nic. Krótki, techniczny tekst z gotowym
   rozwiązaniem (`uv pip compile`).
