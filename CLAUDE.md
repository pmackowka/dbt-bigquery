# CLAUDE.md — dbt-bigquery

Projekt dbt Core (BigQuery) z kursu Udemy *Mastering dbt*, rozszerzony o własne dodatki. Dataset źródłowy: `bigquery-public-data.thelook_ecommerce`. Pełny opis i lista własnych rozszerzeń ponad materiał kursu → [README.md](README.md).

## Setup i komendy

```bash
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt          # dbt-bigquery==1.12.0

cp profiles.yml.example profiles.yml     # profiles.yml jest w .gitignore, nigdy nie commitować
export BIGQUERY_PROJECT="twoj-projekt-gcp"
export BIGQUERY_KEYFILE="/sciezka/do/service-account.json"

dbt deps --profiles-dir .
dbt parse --profiles-dir .               # weryfikacja bez połączenia z BigQuery
dbt build --profiles-dir .               # seed + snapshot + run + test, wymaga żywego połączenia
```

`dbt compile`/`dbt build` wymagają żywej bazy — `dim_orders.sql` używa `dbt_utils.get_column_values()`, które odpytuje BigQuery o listę działów w czasie kompilacji. `dbt parse` tego nie złapie.

## Struktura

```
models/staging/       stg_ecommerce__*     — jeden model na tabelę źródłową
models/intermediate/  int_ecommerce__*     — joiny i agregacje pośrednie
models/marts/         dim_orders           — finalna tabela biznesowa
seeds/                                     — dane z CSV
snapshots/             scd2                — SCD2 dla distribution_centers
tests/                                     — singular + generic (własny test primary_key)
macros/                                    — Jinja, w tym UDF-y z hooka on-run-start
analyses/                                  — SQL eksploracyjny, tylko dbt compile
```

Nazwa projektu i profilu: `dbt_bigquery_course` (NIE `dbt_bigquery` — ta nazwa koliduje z wewnętrznym pakietem makr adaptera dbt-bigquery, dbt parse rzuca wtedy hard error).

## Historia repo — ważne dla kontekstu

To repo powstało 2026-09 z podziału większego monorepo `pmackowka/dbt` (dwa kursy dbt + kilka projektów firmowych). Siostrzane repo z drugiego kursu (Snowflake, dataset Airbnb): [pmackowka/dbt-snowflake](https://github.com/pmackowka/dbt-snowflake), lokalnie `~/Documents/dev/dbt-snowflake`.

Historia gita jest **czysta od 2026-09-14** (jeden commit początkowy) — stare monorepo z hasłami/danymi klientów w historii zostało usunięte z GitHuba, nie tylko z HEAD. Nie próbować "odzyskać" starszej historii tego repo, ona celowo nie istnieje na zdalnym.

Ten projekt istniał w dwóch równoległych wersjach (`project/` — praca własna, `answers/` — rozwiązania autora kursu). Obecna wersja to `project/` z 4 błędami naprawionymi na podstawie `answers/` (m.in. pętla Jinja po niezdefiniowanej zmiennej w `dim_orders.sql`, która po cichu gubiła kolumny). Szczegóły w commicie `c93a740`.

Notatki merytoryczne z kursu (setup, warstwy modeli, governance, Jinja) są w osobnym repo wiedzy, nie tutaj — `knowledge-base/wiki/Software/dbt/dbt-Kompletny-Przewodnik-BigQuery.md`.

## Konwencje

- Kod i nazwy po angielsku, komentarze po polsku (zgodnie z globalnym stylem użytkownika).
- `profiles.yml` i `.user.yml` nigdy nie trafiają do repo — tylko `profiles.yml.example` z `env_var()`.
- Repo jest (lub docelowo będzie) publiczne jako portfolio reskillingu — przy każdej zmianie sprawdzać, czy nie wchodzą dane wrażliwe (klucze, nazwy klientów, ID projektów GCP).
