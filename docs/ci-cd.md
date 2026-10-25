# CI/CD dla dbt na BigQuery

Projekt CI/CD dla tego repo: dbt Core 1.12 + BigQuery, publiczne repo na GitHubie, GitHub Actions bez kluczy JSON (Workload Identity Federation).

**Status:** szkielety plików są w repo (`.github/workflows/`, `ci/`, `.sqlfluff`). Joby wymagające GCP pomijają się, dopóki nie ustawisz zmiennej `GCP_WIF_PROVIDER` — repo można więc wypchnąć przed konfiguracją GCP i nic nie będzie padać. Konfiguracja GCP i GitHuba z sekcji 4 i 5 **nie została wykonana**.

Spis treści:
1. [Architektura docelowa](#1-architektura-docelowa)
2. [Kolejność wdrożenia](#2-kolejność-wdrożenia)
3. [Krok 0 — bez poświadczeń](#3-krok-0--bez-poświadczeń-sqlfluff--dbt-parse)
4. [GCP](#4-gcp)
5. [GitHub](#5-github)
6. [Pliki w repo](#6-pliki-w-repo)
7. [CD a harmonogram i orkiestracja](#7-cd-a-harmonogram-i-orkiestracja)
8. [`+severity: warn` a sens bramki CI](#8-severity-warn-a-sens-bramki-ci)
9. [Co zweryfikowano, a co nie](#9-co-zweryfikowano-a-co-nie)
10. [Dalsze kroki](#10-dalsze-kroki)

---

## 1. Architektura docelowa

```
 PULL REQUEST (ci.yml)                                MERGE DO MAIN (cd.yml)
 ─────────────────────                                ──────────────────────
 static  ── bez GCP ─────────────────┐                deploy  (environment: prod, zatwierdzenie)
   sqlfluff (zmienione pliki)        │                  auth WIF -> sa-dbt-prod
   dbt deps + dbt parse              │                  dbt source freshness  ── bramka: exit 1 = stop
                                     ▼                  dbt build --target prod
 slim-ci ── auth WIF -> sa-dbt-ci                       manifest.json ──────────────┐
   bq mk ci_pr_<nr> (wygasanie 24h)                                                 │
   pobierz manifest prod  ◄──────────── gs://<bucket>/prod/manifest.json ◄──────────┘
   dbt build --select state:modified+ --defer --state prod-state
   run_results: test na warn = błąd

 cleanup (PR zamknięty) ── bq rm -r ci_pr_<nr>
```

### Mechanizm Slim CI

Pełny `dbt build` na każdym PR buduje wszystkie modele od zera — przy dużym projekcie to godzina i realny koszt skanów. Slim CI buduje **tylko to, co PR zmienia, i to, co od tego zależy**:

1. **Stan odniesienia.** Po każdym udanym deployu na prod CD wysyła `target/manifest.json` do GCS. Manifest to pełny opis projektu w danej chwili: każdy węzeł, jego SQL (`raw_code`), konfiguracja, zależności i nazwa tabeli w BigQuery.
2. **Porównanie.** CI parsuje kod z PR i porównuje go z manifestem prod. `state:modified` wybiera węzły, których kod lub konfiguracja się różni; `+` dokłada wszystko, co od nich zależy (modele i testy).
3. **Defer.** Model zmieniony w PR potrzebuje swoich niezmienionych przodków. `--defer` sprawia, że `ref()` do węzła **spoza** selekcji wskazuje tabelę na prod, zamiast wymagać jej zbudowania w CI. CI czyta więc tabele prod — stąd rola `dataViewer` dla konta CI na datasecie prod (sekcja 4).
4. **Izolacja.** Każdy PR buduje się w datasecie `ci_pr_<numer>` (`DBT_CI_DATASET` w `ci/profiles.yml`). Dwa otwarte PR-y nie nadpisują sobie tabel, a prod nigdy nie jest celem zapisu z CI.
5. **Sprzątanie.** Job `cleanup` kasuje dataset po zamknięciu PR. Siatką bezpieczeństwa jest domyślne wygasanie tabel 24h ustawiane przy `bq mk`.

Przykład zweryfikowany lokalnie: zmiana w `stg_ecommerce__orders.sql` wybiera ten model, `int_ecommerce__first_order_created`, `dim_orders` i 33 testy na tych modelach — pozostałe modele i testy nie są budowane.

**Pułapka, która tu nie występuje:** `hours_to_expiration` w `dbt_project.yml` zależy od `target.name`, więc wartość dla prod (`None`) i dev (`1`) jest różna. Mogłoby to oznaczyć **każdy** model jako zmieniony. Nie oznacza: dla konfiguracji z `dbt_project.yml` dbt porównuje `unrendered_config`, czyli tekst `{{ 1 if target.name == 'dev' else none }}`, a nie wynik. Sprawdzone: manifest z `--target prod` vs parse z `--target dev` → 0 zmienionych modeli.

### Bramka świeżości

`src_ecommerce.yml` deklaruje freshness dla `events` (warn 12h, error 24h), ale `dbt build` jej nie sprawdza. W CD `dbt source freshness` idzie jako osobny krok **przed** buildem: przekroczone `error_after` daje kod wyjścia 1, job staje i build na starych danych się nie odpala.

Freshness jest tylko w CD, nie w CI — wiek danych źródłowych nie jest winą PR-a i nie powinien blokować merge'a.

Uwaga: w dbt 1.12 flaga `source_freshness_run_project_hooks` ma domyślnie `True`, więc `dbt source freshness` odpala też hook `on-run-start` i tworzy UDF `get_brand_name`. Bramka nie jest czystym odczytem — konto prod potrzebuje prawa zapisu już na tym etapie.

---

## 2. Kolejność wdrożenia

Kolejność jest wymuszona: każdy krok potrzebuje poprzedniego.

| # | Gdzie | Co | Efekt kroku |
|---|---|---|---|
| 0 | Repo | `.sqlfluff`, `ci/`, `ci.yml` (job `static`) — już są | Każdy PR dostaje lint SQL i `dbt parse` bez żadnych poświadczeń, także z forka |
| 1 | GCP | Projekty, API, datasety prod | Jest gdzie budować; prod i CI rozdzielone na poziomie projektu |
| 2 | GCP | Konta `sa-dbt-prod`, `sa-dbt-ci` + role BigQuery | Dwie tożsamości z minimalnymi prawami; CI nie może pisać do prod |
| 3 | GCP | Bucket GCS na manifest + role | Miejsce na stan prod dla Slim CI |
| 4 | GCP | Workload Identity Federation: pool, provider, powiązania kont | GitHub Actions loguje się do GCP bez klucza JSON |
| 5 | GCP | `maximum_bytes_billed` (już w `ci/profiles.yml`), budżet, quota | Limit kosztu pojedynczego zapytania, alert i twardy dzienny limit |
| 6 | GitHub | Zmienne Actions + environment `prod` | Workflow znają identyfikatory GCP; deploy na prod wymaga zatwierdzenia |
| 7 | GitHub | Ręczne `cd` (Actions → cd → Run workflow) | Pierwszy build prod; manifest trafia do GCS |
| 8 | — | Testowy PR | `slim-ci` buduje tylko zmienione modele w `ci_pr_<nr>`, `cleanup` sprząta |
| 9 | GitHub | Ruleset na `main`: wymagane checki `static`, `slim-ci` | Merge bez zielonego CI jest niemożliwy |

**Efekt całości:** żadna zmiana nie trafia na `main` bez zielonego lintu, parse i builda zmienionych modeli z testami; każdy merge buduje prod (o ile dane są świeże) i aktualizuje stan, z którym porównywany jest kolejny PR; w całym łańcuchu nie istnieje żaden długoterminowy sekret.

Krok 9 jest na końcu celowo: GitHub pozwala wybrać wymagany check dopiero wtedy, gdy ten check przynajmniej raz się wykonał.

---

## 3. Krok 0 — bez poświadczeń (sqlfluff + dbt parse)

Job `static` w `ci.yml`. Działa od razu po wypchnięciu, bez GCP.

**`dbt parse`** waliduje YAML, Jinja i graf zależności. Nie łączy się z BigQuery: profil `ci` z `method: oauth` przechodzi parse z fikcyjnymi wartościami zmiennych i bez żadnych poświadczeń (sprawdzone). Nie złapie błędów, które ujawnia dopiero baza — np. brakującej kolumny ani kolumn `total_sold_*` generowanych w `dim_orders.sql` przez `dbt_utils.get_column_values`, które odpytuje hurtownię już przy kompilacji.

**sqlfluff** z templaterem `jinja`, nie `dbt`. Templater `dbt` kompiluje projekt, a kompilacja `dim_orders.sql` wymaga połączenia z BigQuery — krok 0 przestałby być bezpoświadczeniowy. Templater `jinja` nie zna kontekstu dbt, więc dostaje atrapy:

| Brakujący element | Skąd atrapa |
|---|---|
| `ref`, `source`, `config`, `var`, `is_incremental`, `this` | `apply_dbt_builtins = True` (wbudowane w sqlfluff) |
| Własne makra (`is_weekend`, `get_brand_name`) | `load_macros_from_path = macros` — renderują się naprawdę |
| `dbt_utils.get_column_values` | `ci/sqlfluff_libs/dbt_utils.py` — zwraca `["Men", "Women"]` |
| `target.schema` | `ci/sqlfluff_libs/target.py` |
| Blok `{% snapshot %}` | brak — `snapshots/` w `.sqlfluffignore` |

Wcięcia: projekt używa tabulatorów (`indent_unit = tab`). Bez tego sqlfluff zgłasza ~100 fałszywych naruszeń LT02.

**Stan wyjściowy:** 32 naruszenia w 10 plikach (głównie brak końcowego znaku nowej linii — LT12 — i wcięcia). Lint całego repo jako bramka byłby czerwony od pierwszego dnia i szybko zostałby zignorowany. Dlatego CI lintuje **tylko pliki zmienione w PR**: kto dotyka pliku, doprowadza go do porządku. Pierwszy PR zmieniający dowolny model musi więc poprawić jego istniejące naruszenia.

`sqlfluff fix` poprawia automatycznie 23 z 32 naruszeń, ale w `dim_orders.sql` rozbija pętlę `{% for department %}` i zostawia pustą linię z tabulatorem. Poprawki rób osobnym PR z ręcznym przeglądem diffu, nie na ślepo.

Lokalnie:

```bash
uvx sqlfluff==4.4.0 lint models/marts/dim_orders.sql
```

---

## 4. GCP

Placeholdery: `PROJECT_PROD`, `PROJECT_CI`, `PROJECT_PROD_NUMBER` (numer, nie ID: `gcloud projects describe PROJECT_PROD --format='value(projectNumber)'`), `BUCKET`, `OWNER_ID` (`gh api users/pmackowka --jq .id`). Prawdziwe wartości trafiają tylko do zmiennych w ustawieniach GitHuba, nigdy do plików repo.

### 4.1 Projekty i datasety

Dwa projekty: `PROJECT_PROD` (prod) i `PROJECT_CI` (dev + CI). Osobny projekt to najprostsza granica IAM i kosztów: role nadane w projekcie CI w ogóle nie sięgają prod, a rachunki i limity są rozdzielone. Rozwiązuje też problem snapshotu: `target_schema='snapshots_project'` nie dostaje prefiksu targetu, więc w jednym projekcie dev, CI i prod pisałyby do tej samej tabeli historii.

```bash
for p in PROJECT_PROD PROJECT_CI; do
  gcloud services enable bigquery.googleapis.com storage.googleapis.com iam.googleapis.com \
    iamcredentials.googleapis.com sts.googleapis.com --project="$p"
done

# Datasety prod zakłada człowiek, nie dbt - dzięki temu konto prod nie potrzebuje prawa
# bigquery.datasets.create na całym projekcie.
bq --location=US mk --dataset PROJECT_PROD:dbt_prod_project
bq --location=US mk --dataset PROJECT_PROD:snapshots_project
```

Datasety CI (`ci_pr_<nr>`) tworzy workflow w trakcie działania.

### 4.2 Konta serwisowe i role

```bash
gcloud iam service-accounts create sa-dbt-prod --project=PROJECT_PROD
gcloud iam service-accounts create sa-dbt-ci   --project=PROJECT_CI
```

| Konto | Rola | Zakres | Po co |
|---|---|---|---|
| `sa-dbt-prod` | `roles/bigquery.jobUser` | projekt PROD | Uruchamianie zapytań rozliczanych na projekt prod |
| `sa-dbt-prod` | `roles/bigquery.dataEditor` | datasety `dbt_prod_project`, `snapshots_project` | Tworzenie i nadpisywanie tabel, widoków i UDF — tylko w tych dwóch datasetach |
| `sa-dbt-prod` | `roles/storage.objectUser` | bucket | Zapis (nadpisanie) `manifest.json` |
| `sa-dbt-ci` | `roles/bigquery.user` | projekt CI | Uruchamianie zapytań **i** tworzenie datasetów; twórca datasetu dostaje na nim `dataOwner`, więc CI może też go skasować |
| `sa-dbt-ci` | `roles/bigquery.dataViewer` | dataset `dbt_prod_project` | Odczyt tabel prod przez `--defer` (w tym `get_column_values` w `dim_orders`) |
| `sa-dbt-ci` | `roles/storage.objectViewer` | bucket | Pobranie manifestu prod |

Źródło `bigquery-public-data.thelook_ecommerce` jest publiczne — żadne konto nie potrzebuje do niego roli, wystarczy prawo uruchamiania zapytań we własnym projekcie.

```bash
gcloud projects add-iam-policy-binding PROJECT_PROD \
  --member="serviceAccount:sa-dbt-prod@PROJECT_PROD.iam.gserviceaccount.com" --role=roles/bigquery.jobUser
gcloud projects add-iam-policy-binding PROJECT_CI \
  --member="serviceAccount:sa-dbt-ci@PROJECT_CI.iam.gserviceaccount.com" --role=roles/bigquery.user
```

Role na poziomie datasetu najprościej nadać przez DCL w BigQuery (konsola, projekt PROD):

```sql
GRANT `roles/bigquery.dataEditor` ON SCHEMA `PROJECT_PROD.dbt_prod_project`
  TO "serviceAccount:sa-dbt-prod@PROJECT_PROD.iam.gserviceaccount.com";
GRANT `roles/bigquery.dataEditor` ON SCHEMA `PROJECT_PROD.snapshots_project`
  TO "serviceAccount:sa-dbt-prod@PROJECT_PROD.iam.gserviceaccount.com";
GRANT `roles/bigquery.dataViewer` ON SCHEMA `PROJECT_PROD.dbt_prod_project`
  TO "serviceAccount:sa-dbt-ci@PROJECT_CI.iam.gserviceaccount.com";
```

Dlaczego nie `dataEditor` na projekcie: rola projektowa dziedziczy się na **wszystkie** datasety, także te, które powstaną później.

### 4.3 Bucket na manifest

```bash
gcloud storage buckets create gs://BUCKET --project=PROJECT_PROD --location=US \
  --uniform-bucket-level-access --public-access-prevention
# Wersjonowanie: po złym deployu można wrócić do poprzedniego manifestu.
gcloud storage buckets update gs://BUCKET --versioning

gcloud storage buckets add-iam-policy-binding gs://BUCKET \
  --member="serviceAccount:sa-dbt-prod@PROJECT_PROD.iam.gserviceaccount.com" --role=roles/storage.objectUser
gcloud storage buckets add-iam-policy-binding gs://BUCKET \
  --member="serviceAccount:sa-dbt-ci@PROJECT_CI.iam.gserviceaccount.com" --role=roles/storage.objectViewer
```

### 4.4 Workload Identity Federation

**Dlaczego nie klucz JSON:** repo jest publiczne, a klucz w sekrecie GitHuba to długoterminowe hasło — wycieka z logu, z forka albo z błędnego workflow i działa do ręcznego unieważnienia. WIF nie przechowuje niczego.

**Mechanizm:**
1. Job z `permissions: id-token: write` prosi GitHuba o token OIDC (JWT) podpisany przez `token.actions.githubusercontent.com`. Token zawiera m.in. `repository`, `ref`, `environment` i `sub`, np. `repo:pmackowka/dbt-bigquery:pull_request` albo `repo:pmackowka/dbt-bigquery:environment:prod`.
2. `google-github-actions/auth` wysyła go do Google STS. STS weryfikuje podpis kluczami publicznymi GitHuba i sprawdza `attribute-condition` providera.
3. STS wydaje token federacyjny, który może podszyć się (impersonate) pod konto serwisowe — ale tylko pod to, na którym dany `sub` ma rolę `workloadIdentityUser`.
4. Wynik: token dostępu konta serwisowego ważny ok. 1h, zapisany jako ADC. dbt (`method: oauth`), `bq` i `gcloud` używają go automatycznie.

```bash
gcloud iam workload-identity-pools create github \
  --project=PROJECT_PROD --location=global --display-name="GitHub Actions"

# attribute-condition: bez niego token z DOWOLNEGO repo na GitHubie przeszedłby przez pool.
# repository_owner_id (liczba) zamiast samej nazwy - nazwa konta może po zmianie trafić do kogoś innego.
gcloud iam workload-identity-pools providers create-oidc dbt-bigquery \
  --project=PROJECT_PROD --location=global --workload-identity-pool=github \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repository_owner_id=assertion.repository_owner_id" \
  --attribute-condition="assertion.repository == 'pmackowka/dbt-bigquery' && assertion.repository_owner_id == 'OWNER_ID'"

POOL="principal://iam.googleapis.com/projects/PROJECT_PROD_NUMBER/locations/global/workloadIdentityPools/github/subject"

# Konto CI: tylko joby uruchomione przez pull_request.
gcloud iam service-accounts add-iam-policy-binding sa-dbt-ci@PROJECT_CI.iam.gserviceaccount.com \
  --project=PROJECT_CI --role=roles/iam.workloadIdentityUser \
  --member="${POOL}/repo:pmackowka/dbt-bigquery:pull_request"

# Konto prod: tylko joby z environment prod (a to environment wymaga zatwierdzenia i gałęzi main).
gcloud iam service-accounts add-iam-policy-binding sa-dbt-prod@PROJECT_PROD.iam.gserviceaccount.com \
  --project=PROJECT_PROD --role=roles/iam.workloadIdentityUser \
  --member="${POOL}/repo:pmackowka/dbt-bigquery:environment:prod"

# Wartość do zmiennej GCP_WIF_PROVIDER w GitHubie:
gcloud iam workload-identity-pools providers describe dbt-bigquery \
  --project=PROJECT_PROD --location=global --workload-identity-pool=github --format="value(name)"
```

Powiązanie po `sub` to sedno bezpieczeństwa: workflow uruchomiony z pushem na dowolną gałąź (bez PR i bez environment) nie dostanie żadnego z kont, nawet jeśli ktoś go dopisze do repo.

### 4.5 Koszty

| Mechanizm | Co robi | Czy zatrzymuje wydatek |
|---|---|---|
| `maximum_bytes_billed` w `ci/profiles.yml` (CI 10 GiB, prod 100 GiB) | Zapytanie, które przeskanowałoby więcej, pada przed startem | Tak, per zapytanie |
| Budżet w Billing (np. progi 50/90/100%) | Wysyła e-mail po przekroczeniu progu | **Nie** — tylko alarmuje, z opóźnieniem |
| Quota BigQuery „Query usage per day” (IAM & Admin → Quotas) | Dzienny limit przeskanowanych bajtów na projekt | Tak, twardo, dla całego projektu |

Budżet sam niczego nie blokuje — to częste błędne założenie. Twardą granicą jest limit per zapytanie plus dzienna quota.

---

## 5. GitHub

### 5.1 Zmienne (nie sekrety)

Przy WIF nie ma żadnego sekretu. Identyfikatory to **zmienne**, bo nie są tajne w sensie kryptograficznym — ale trzyma się je w ustawieniach, nie w plikach repo, żeby nie publikować ID projektów.

Settings → Secrets and variables → Actions → **Variables**:

| Zmienna | Poziom | Przykład wartości |
|---|---|---|
| `GCP_WIF_PROVIDER` | repozytorium | `projects/PROJECT_PROD_NUMBER/locations/global/workloadIdentityPools/github/providers/dbt-bigquery` |
| `GCP_PROJECT_CI` | repozytorium | `PROJECT_CI` |
| `GCP_SA_CI` | repozytorium | `sa-dbt-ci@PROJECT_CI.iam.gserviceaccount.com` |
| `GCS_MANIFEST_BUCKET` | repozytorium | `BUCKET` |
| `GCP_PROJECT_PROD` | environment `prod` | `PROJECT_PROD` |
| `GCP_SA_PROD` | environment `prod` | `sa-dbt-prod@PROJECT_PROD.iam.gserviceaccount.com` |

`GCP_WIF_PROVIDER` jest też przełącznikiem: puste → joby `slim-ci`, `cleanup` i `deploy` się pomijają.

### 5.2 Environment `prod`

Settings → Environments → New environment `prod`:
- **Required reviewers:** `pmackowka` — każdy deploy czeka na kliknięcie „Approve”.
- **Deployment branches:** Selected branches → `main`.
- **Environment variables:** `GCP_PROJECT_PROD`, `GCP_SA_PROD`.

Zmienne prod są tylko w environment, więc job bez `environment: prod` w ogóle ich nie widzi. Druga warstwa to WIF: konto prod jest powiązane z `sub` `...:environment:prod`.

### 5.3 Ochrona gałęzi `main`

Settings → Rules → Rulesets → New branch ruleset, target `main`:
- Require a pull request before merging.
- Require status checks to pass: `static`, `slim-ci`.
- Block force pushes.
- **Require review from Code Owners** — dopiero to zamienia `.github/CODEOWNERS` z prośby w wymóg.

**Pułapka przy pracy solo:** GitHub nie pozwala zatwierdzić własnego PR. Wymagany review od Code Ownera, którym jesteś tylko ty, zablokuje każdy merge. Solo: wymagaj tylko checków, a review od Code Owners włącz, gdy pojawi się druga osoba (albo dodaj siebie do bypass list rulesetu — wtedy reguła jest deklaracją, nie bramką). W banku review od Code Owners jest standardem, bo ownerem jest zespół.

### 5.4 PR z forka

- PR z forka **nie dostaje** sekretów, zmiennych środowiskowych ani tokenu OIDC (`id-token: write` jest ignorowane), a `GITHUB_TOKEN` ma tylko odczyt. Dlatego `slim-ci` sprawdza `head.repo.full_name == github.repository` i dla forka się pomija; job `static` działa normalnie.
- **Pułapka:** job pominięty przez `if` raportuje status „skipped”, a GitHub traktuje go jako spełniony wymagany check. PR z forka przejdzie bramkę `slim-ci` bez builda. Przed merge'em takiego PR przenieś zmiany na gałąź w repo albo sprawdź je lokalnie.
- Nigdy nie używaj `pull_request_target` z checkoutem kodu z PR: ten trigger daje sekrety i OIDC, a kod pochodzi od autora forka.
- Settings → Actions → General → „Require approval for all outside collaborators” — workflow z forka nie ruszy bez twojej zgody.

---

## 6. Pliki w repo

```
.github/
  CODEOWNERS                 # istniał - kto zatwierdza zmiany (wymuszenie: ruleset, 5.3)
  workflows/
    ci.yml                   # PR: static -> slim-ci, cleanup po zamknięciu
    cd.yml                   # main: freshness -> build prod -> manifest do GCS
ci/
  profiles.yml               # targety ci i prod, method: oauth (ADC z WIF), bez kluczy
  check_test_warnings.py     # test na warn w CI = błąd (sekcja 8)
  sqlfluff_libs/
    dbt_utils.py             # atrapa get_column_values dla lintu bez bazy
    target.py                # atrapa target.schema
.sqlfluff                    # dialekt bigquery, templater jinja, tabulatory
.sqlfluffignore              # snapshots/, macros/
docs/ci-cd.md                # ten dokument
```

Decyzje w plikach, które nie są oczywiste:
- **`ci/profiles.yml` osobno od `profiles.yml.example`.** Lokalnie logujesz się kluczem konta serwisowego, w CI — tokenem z WIF. Jeden plik z dwoma metodami logowania myliłby oba przypadki.
- **Target prod w CI nazywa się `prod`.** Warunki w `dbt_project.yml` (`target.name == 'dev'`) muszą działać tak samo jak przy lokalnym `--target prod`.
- **Snapshot wykluczony z CI** (`--exclude resource_type:snapshot`). Sprawdzone: zmieniony snapshot bez wykluczenia trafia do selekcji i pisałby do wspólnego `snapshots_project` w projekcie CI, czyli do historii dev.
- **`uvx sqlfluff==4.4.0` zamiast zależności w `uv.lock`.** Lint nie zmienia środowiska dbt, a przypięta wersja daje ten sam wynik lokalnie i w CI. Wada: wersja żyje w dwóch miejscach (`ci.yml` i komenda lokalna).
- **`concurrency`:** w CI nowy push anuluje stary przebieg; w CD deploye czekają w kolejce i nigdy nie są przerywane w połowie.
- **Manifest publikowany dopiero po udanym buildzie.** Manifest z nieudanego deployu opisywałby tabele, których na prod nie ma, a CI deferowałby do nieistniejących relacji.

---

## 7. CD a harmonogram i orkiestracja

dbt nie ma artefaktu do wdrożenia w klasycznym sensie: „deploy” oznacza, że kod z `main` jest tym, który wykona się przy następnym przebiegu. CD w `cd.yml` robi więc dwie rzeczy naraz — weryfikuje, że `main` buduje się na prod, i odświeża dane. Codzienne odświeżanie danych to osobna odpowiedzialność: **harmonogram**.

| | Cron w GitHub Actions | Cloud Scheduler + Cloud Run Jobs | Cloud Composer (Airflow) |
|---|---|---|---|
| Uruchomienie | `schedule:` w workflow | Kontener z projektem dbt, odpalany wg crona | DAG z zadaniami dbt |
| Niezawodność | Best effort: opóźnienia przy obciążeniu; w publicznym repo GitHub wyłącza harmonogram po 60 dniach bez aktywności | Usługa GCP z SLA | Usługa GCP z SLA |
| Zależności od innych systemów (np. „po załadowaniu ingestu”) | Brak | Ograniczone | Tak — sensory, zależności między DAG-ami |
| Retry, backfill, alerting | Ręcznie | Retry wbudowany, reszta ręcznie | Wbudowane |
| Uwierzytelnienie | WIF jak w CD | Natywnie jako konto serwisowe joba, bez WIF | Natywnie jako konto środowiska |
| Koszt stały | Brak (publiczne repo) | Brak, płacisz za czas wykonania | Stałe środowisko, rząd setek USD miesięcznie (nie sprawdzałem aktualnego cennika) |

Konflikt w tym repo: environment `prod` z wymaganym zatwierdzeniem zatrzyma każdy nocny przebieg w oczekiwaniu na kliknięcie. Harmonogram w Actions wymagałby osobnego environment bez reviewera, a WIF musiałby wpuścić także jego `sub` — czyli słabszą bramkę na tym samym koncie prod.

**Rekomendacja:**
- Ten projekt (portfolio): CD na merge wystarczy. Harmonogram w Actions można włączyć jako demo, z osobnym environment i świadomością, że to best effort.
- W banku: CD buduje **obraz Dockera** z projektem dbt i zależnościami, wysyła go do Artifact Registry z tagiem commita; Composer albo Cloud Run Jobs uruchamia konkretny tag według harmonogramu i zależności od ingestu. Publikacja manifestu przechodzi wtedy do przebiegu harmonogramu, bo to on jest źródłem prawdy o stanie prod. Rozdział odpowiedzialności: CI/CD dostarcza przetestowany artefakt, orkiestrator decyduje, kiedy go uruchomić.

---

## 8. `+severity: warn` a sens bramki CI

`dbt_project.yml` ustawia `+severity: warn` dla całego projektu; `error` mają tylko jawnie wskazane testy (klucze, kolumny pod joinami). Konsekwencja dla CI: `dbt build` kończy się kodem 0 mimo oblanych testów na warn. Bramka bez dodatkowego kroku zatrzymałaby tylko błędy SQL, naruszone kontrakty (`stg_ecommerce__order_items`, `dim_orders`) i testy na `error` — PR łamiący regułę biznesową przeszedłby na zielono.

| Opcja | Jak | Wada |
|---|---|---|
| A. `dbt build --warn-error` | Wszystkie ostrzeżenia dbt jako błędy | Obejmuje też deprecations i inne ostrzeżenia niezwiązane z PR — CI pada np. po podbiciu wersji dbt. Nie sprawdzałem, jak w 1.12 traktuje testy na warn |
| B. Severity zależne od targetu | `+severity: "{{ 'error' if target.name == 'ci' else 'warn' }}"` | Działa, ale ukrywa politykę w Jinja w konfiguracji, a prod i CI zaczynają się różnić w mniej oczywisty sposób |
| **C. Skrypt na `run_results.json`** (zaimplementowane) | `ci/check_test_warnings.py`: dowolny węzeł ze statusem `warn` → kod 1 i adnotacja w PR | Dodatkowy krok — ale jawny i ograniczony do CI |

**Rekomendacja: C.** W CI każdy oblany test blokuje PR, bo sprawdza tylko zmienione modele i ich potomków. Na prod `warn` zostaje, bo zatrzymywanie nocnego builda z powodu reguły biznesowej to decyzja biznesowa, nie techniczna. Warunek, żeby `warn` na prod miał sens: ktoś musi go zobaczyć. Potrzebny jest routing — alert ze `store_failures` albo narzędzie typu Elementary. Bez tego `warn` na prod to tylko linia w logu, której nikt nie czyta.

Ograniczenie opcji C: jeśli test na warn oblewa się już na prod (problem w danych, nie w kodzie), każdy PR dotykający tego modelu będzie czerwony. To akurat pożądane — zmusza do decyzji: naprawić dane, zmienić regułę albo świadomie podnieść ją do `error` czy usunąć.

---

## 9. Co zweryfikowano, a co nie

Sprawdzone lokalnie (2026-10-25, dbt-core 1.12.5, dbt-bigquery 1.12.0):
- `dbt parse` z `ci/profiles.yml` (`method: oauth`) bez żadnych poświadczeń → exit 0.
- `state:modified+` vs manifest prod: zmiana w `stg_ecommerce__orders` wybiera ten model, 2 potomków i ich testy; warunkowy `hours_to_expiration` nie daje fałszywych trafień (porównanie `unrendered_config`).
- `--exclude resource_type:snapshot` usuwa zmieniony snapshot z selekcji.
- sqlfluff 4.4.0: templating wszystkich 10 plików bez błędów, 32 naruszenia na starcie; `.sqlfluffignore` pomija także ścieżki podane wprost.
- `ci.yml`, `cd.yml`: walidacja schematem (`check-jsonschema`) i `actionlint` bez uwag.
- `ci/check_test_warnings.py`: kod 1 przy `warn`, 0 bez.

Niesprawdzone (wymaga GCP i GitHuba):
- Wymiana tokenu WIF, uprawnienia ról w praktyce, `bq mk` / `bq rm`, `gcloud storage cp`.
- Prawdziwy `dbt build` w CI z `--defer` przeciwko tabelom prod.
- Zachowanie rulesetu i environment w GitHubie.

---

## 10. Dalsze kroki

1. **Model incremental w CI.** Zmieniony `stg_ecommerce__events` buduje się w pustym `ci_pr_<nr>`, więc `is_incremental()` daje `false` — CI testuje pełny build, nie ścieżkę MERGE. `dbt clone --select state:modified+,config.materialized:incremental --state prod-state` przed buildem kopiuje tabelę prod (zero-copy clone w BigQuery) i CI testuje to, co naprawdę wykona się na prod.
2. **Unit testy dbt** (`unit_tests:` w YAML, od dbt 1.8) — sprawdzają logikę SQL na danych z YAML, np. pętlę po działach w `dim_orders`. Uruchamiają się w CI tym samym `dbt build`.
3. **`dbt build --empty`** — buduje modele z `LIMIT 0` na wejściu: tanie sprawdzenie, że SQL i kontrakty się kompilują i wykonują, bez kosztu skanów. Testy na pustych tabelach przechodzą trywialnie, więc to uzupełnienie, nie zamiennik.
4. **Jednorazowy PR z `sqlfluff fix`** z ręcznym przeglądem — po nim lint całego repo może zostać bramką zamiast lintu zmienionych plików.
5. **Routing ostrzeżeń z prod** (Elementary albo `store_failures` + alert) — warunek sensu `+severity: warn` (sekcja 8).
