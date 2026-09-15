# dbt na BigQuery — analityka e-commerce

Projekt dbt Core zbudowany w trakcie kursu Udemy *Mastering dbt (Data Build Tool)* i rozszerzony o własne dodatki.
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

## Co jest tu ponad materiał kursu

- **Dynamiczna lista działów** w `dim_orders` przez `dbt_utils.get_column_values()` zamiast twardo zakodowanej listy.
- **`hours_to_expiration` zależne od targetu** (`dev` vs inne) w `dbt_project.yml`.
- **Governance modeli**: grupa `sales`, `access: public`, kontrakt (`contract: enforced`) na `stg_ecommerce__order_items`.
- **Wersjonowanie modeli** (`stg_ecommerce__products`, wersje `v1`/`v2` z aliasem na niewersjonowaną nazwę tabeli).
- **Własny generic test** `primary_key` (`not_null` + `unique` w jednym).

## Setup

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

cp profiles.yml.example profiles.yml   # profiles.yml jest w .gitignore
export BIGQUERY_PROJECT="twoj-projekt-gcp"
export BIGQUERY_KEYFILE="/sciezka/do/service-account.json"

dbt deps --profiles-dir .
dbt build --profiles-dir .
```

## Dokumentacja notatek

Notatki merytoryczne z kursu (setup, warstwy modeli, testy, kontrakty, snapshoty, Jinja/makra) są w osobnym repo wiedzy — nie w tym repo kodu.
