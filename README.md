# dbt na BigQuery — analityka e-commerce

Projekt dbt Core zbudowany na bazie projektu szkoleniowego i rozszerzony o własne dodatki.
Źródło danych: `bigquery-public-data.thelook_ecommerce` (publiczny dataset BigQuery).

## Struktura

```
models/
  staging/       # stg_ecommerce__* — jeden model na tabelę źródłową
  intermediate/   # int_ecommerce__* — joiny i agregacje pośrednie
  marts/          # dim_orders — finalna tabela biznesowa
seeds/            # dane z CSV
snapshots/        # SCD2 dla distribution_centers
tests/            # testy singular i generic (m.in. własny test primary_key)
macros/           # makra Jinja, w tym UDF-y tworzone przez hook on-run-start
analyses/         # zapytania eksploracyjne (dbt compile, bez materializacji)
```

## Co jest tu ponad materiał źródłowy

- **Dynamiczna lista działów** w `dim_orders` przez `dbt_utils.get_column_values()` zamiast twardo zakodowanej listy.
- **`hours_to_expiration` zależne od targetu** (`dev` vs inne) w `dbt_project.yml`.
- **Governance modeli**: grupa `sales`, `access: public`, kontrakt (`contract: enforced`) na `stg_ecommerce__order_items`.
- **Wersjonowanie modeli** (`stg_ecommerce__products`, wersje `v1`/`v2` z aliasem na niewersjonowaną nazwę tabeli).
- **Własny generic test** `primary_key` (`not_null` + `unique` w jednym).

## Setup

Autoryzacja przez **konto serwisowe** (service account) — nie przez lokalny OAuth (`gcloud auth application-default login`). OAuth loguje CIEBIE i działa tylko na maszynie, na której go odpaliłeś; konto serwisowe to tożsamość samego projektu, przenośna (CI/CD, inny laptop, kontener) i taka, której uprawnienia widać jawnie w IAM, a nie w czyjejś sesji logowania.

### 1. GCP — projekt i konto serwisowe

```bash
# Nowy projekt GCP (pomiń, jeśli używasz istniejącego)
gcloud projects create TWOJ_PROJECT_ID --name="dbt BigQuery"
gcloud config set project TWOJ_PROJECT_ID

# BigQuery API musi być włączone w projekcie, zanim dbt się z nim połączy
gcloud services enable bigquery.googleapis.com

# Konto serwisowe dedykowane pod dbt (nie Twoje osobiste konto Google)
gcloud iam service-accounts create dbt-bigquery \
  --display-name="dbt BigQuery"

# Rola dataEditor: tworzenie/nadpisywanie/kasowanie tabel i widoków w datasetach projektu
# (dbt run/build robi to non-stop — bez tej roli każdy build padnie na permission denied)
gcloud projects add-iam-policy-binding TWOJ_PROJECT_ID \
  --member="serviceAccount:dbt-bigquery@TWOJ_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/bigquery.dataEditor"

# Rola jobUser: uruchamianie zapytań (query jobs) rozliczanych na ten projekt
# (dataEditor sam w sobie NIE pozwala odpalać zapytań - to świadomie rozdzielone uprawnienie)
gcloud projects add-iam-policy-binding TWOJ_PROJECT_ID \
  --member="serviceAccount:dbt-bigquery@TWOJ_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/bigquery.jobUser"

# Klucz JSON - POZA folderem tego repo (np. ~/.gcp/), żeby żaden przyszły `git add -A`
# nie mógł go złapać niezależnie od .gitignore
mkdir -p ~/.gcp
gcloud iam service-accounts keys create ~/.gcp/dbt-bigquery.json \
  --iam-account=dbt-bigquery@TWOJ_PROJECT_ID.iam.gserviceaccount.com
```

Dataset źródłowy `bigquery-public-data.thelook_ecommerce` jest publiczny — Google nadaje odczyt każdej uwierzytelnionej tożsamości GCP, więc powyższe role nic tam nie zmieniają i nic dodatkowego nie trzeba nadawać. Zapytania są tanie (mały dataset, w granicach darmowego 1 TB/miesiąc), ale rozliczane na `TWOJ_PROJECT_ID`, nie na `bigquery-public-data`.

### 2. Repo i środowisko Python

```bash
git clone https://github.com/pmackowka/dbt-bigquery.git
cd dbt-bigquery

python3 -m venv venv
source venv/bin/activate        # Windows: venv\Scripts\activate
pip install --require-hashes -r requirements.lock  # dokładne wersje CAŁEGO stosu, nie tylko adaptera
                                                    # (requirements.txt to wejście dla locka - patrz komentarz w pliku)
```

### 3. Konfiguracja połączenia

```bash
cp profiles.yml.example profiles.yml   # profiles.yml jest w .gitignore - nigdy go nie commituj
export BIGQUERY_PROJECT="TWOJ_PROJECT_ID"
export BIGQUERY_KEYFILE="$HOME/.gcp/dbt-bigquery.json"

dbt deps --profiles-dir .    # instaluje pakiety z packages.yml do dbt_packages/
dbt debug --profiles-dir .   # weryfikuje połączenie PRZED pierwszym run - najczęstszy błąd
                              # na tym etapie to literówka w BIGQUERY_PROJECT albo zła ścieżka klucza
```

Target `prod` ma **osobne** zmienne (`BIGQUERY_PROD_PROJECT`, `BIGQUERY_PROD_KEYFILE`) i celowo nie spada na zmienne dev. Do pracy lokalnej nie są potrzebne — dbt renderuje tylko wybrany target. Żeby odpalić `--target prod`, trzeba mieć drugie konto serwisowe (najlepiej w osobnym projekcie GCP) utworzone tak samo jak w kroku 1; wtedy konto dev może dostać prawo zapisu wyłącznie do własnych datasetów `dbt_dev_*`, a przypadkowy `--target prod` na laptopie z samym kluczem dev pada na brakującej zmiennej, zamiast nadpisać prod. Uzasadnienie w komentarzu w `profiles.yml.example`.

### 4. Pierwszy build

```bash
dbt seed --profiles-dir .       # ładuje seeds/seed_distribution_centers_new.csv (dbt run tego NIE robi)
dbt snapshot --profiles-dir .   # pierwszy przebieg snapshotu SCD2 - zakłada tabelę historii w BigQuery
dbt build --profiles-dir .      # seed + snapshot + run + test w jednym poleceniu, kolejność wg DAG-a
```

Kolejność ma znaczenie: `seed` przed `build`, bo `snapshots/snapshot__distribution_centers.sql` czyta z `source()`, nie z seeda — ale sam seed też trzeba załadować raz, zanim cokolwiek innego po niego sięgnie. `dbt build` przy kolejnych uruchomieniach wystarcza sam.

## Notatki (prywatne, tylko dla mnie)

Pełne notatki merytoryczne z pracy nad tym projektem (setup, warstwy modeli, testy, kontrakty, snapshoty, Jinja/makra) są w moim prywatnym repo wiedzy: [dbt-Kompletny-Przewodnik-BigQuery.md](https://github.com/pmackowka/knowledge-base/blob/main/wiki/Software/dbt/dbt-Kompletny-Przewodnik-BigQuery.md).

Ten link **działa tylko na moim koncie GitHub** — repo jest prywatne i takie zostanie. Dla każdego innego zwraca 404, to celowe, nie błąd.
