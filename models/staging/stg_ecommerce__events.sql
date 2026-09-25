{#
	Staging: eventy użytkowników (thelook_ecommerce.events).

	Jedyny model incremental w projekcie: tabela zdarzeń w realnym sklepie rośnie milionami wierszy
	dziennie, a 'table' przeliczałaby całą historię przy każdym run - drogo (BigQuery liczy
	zeskanowane bajty) i wolno. Incremental dokłada tylko nowe wiersze.
#}
{#
	unique_key='event_id' - po nim MERGE rozpoznaje ten sam event w kolejnych przebiegach; bez klucza
	incremental tylko dokleja wiersze i nie wykryje duplikatu.

	on_schema_change='append_new_columns' - reaguje na zmianę kolumn WYNIKU MODELU (edycja SELECT-a),
	nie źródła. Nie sync_all_columns, bo ta usunięcie kolumny z SELECT-a zamienia w ciche DROP COLUMN
	razem z historią, którą odbuduje tylko --full-refresh. append tylko dokłada kolumny - kasowanie
	zostaje świadomą decyzją. Nie 'fail', bo wymusza drogi --full-refresh przy każdej nowej kolumnie.

	partition_by po dniu - zapytanie z filtrem po dacie skanuje tylko pasujące partycje, nie całą
	tabelę. 'day', nie 'hour': limity BigQuery to 10 000 partycji na tabelę i 4 000 na jeden job.
	Dla 'day' to ~27 lat w tabeli i ~11 lat w jednym --full-refresh, dla 'hour' ~416 i ~166 dni.

	hours_to_expiration=none - nadpisuje 1h z dbt_project.yml. Z nim tabela w dev znikałaby przed
	kolejnym run, is_incremental() byłoby prawie zawsze false i ścieżka MERGE nie byłaby testowana.

	incremental_predicates - dokleja do ON w MERGE warunek na kolumnie partycjonującej. Bez niego
	BigQuery skanuje CAŁĄ historię tabeli docelowej przy każdym MERGE, więc koszt rośnie z wiekiem
	tabeli, nie z nową porcją.
	Pułapka: wiersz ze źródła, którego kopia leży POZA oknem predykatu, nie znajdzie pary i wejdzie
	drugi raz (duplikat zamiast UPDATE). Filtr źródła liczy od MAX(created_at), predykat od teraz,
	więc warunek to: merge_lookback_days >= source_lookback_days + dni od ostatniego przebiegu.
	7 vs 3 toleruje ~4 dni przestoju; dłużej - --full-refresh. Siatka: unique na event_id (error)
	w stg_ecommerce__events.yml zatrzyma build, jeśli duplikat jednak powstanie.
#}
{#- Ile dni wstecz od MAX(created_at) w tabeli doczytujemy ze źródła - patrz filtr na dole pliku. -#}
{%- set source_lookback_days = 3 -%}
{#- Ile dni wstecz od TERAZ MERGE szuka dopasowań w tabeli docelowej - patrz incremental_predicates. -#}
{%- set merge_lookback_days = 7 -%}

{{
	config(
		materialized='incremental',
		hours_to_expiration=none,
		unique_key='event_id',
		incremental_predicates=[
			"DBT_INTERNAL_DEST.created_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL " ~ merge_lookback_days ~ " DAY)"
		],
		on_schema_change='append_new_columns',
		partition_by={
			"field": "created_at",
			"data_type": "timestamp",
			"granularity": "day"
		}
	)
}}

WITH source AS (
	SELECT *

	FROM {{ source('thelook_ecommerce', 'events') }}
)

SELECT
	id AS event_id,
	user_id,
	sequence_number,
	session_id,
	created_at,
	ip_address,
	city,
	state,
	postal_code,
	browser,
	traffic_source,
	uri AS web_link,
	event_type,
	{# UDF tworzony przez hook on-run-start w schemacie targetu - stąd {{ target.schema }}, nie ref(). #}
	{{ target.schema }}.get_brand_name(uri) AS brand_name

FROM source

{% if is_incremental() %}

-- Aktywne tylko po pierwszym przebiegu (nie przy pierwszym run ani --full-refresh).
-- Okno wsteczne zamiast samego "> MAX(created_at)": spóźniony event ma poprawny, STARY created_at
-- i bez marginesu przepadłby na zawsze, przy zielonym buildzie (jak eksport GA4, dociągający dane
-- do ~72h). Nakładające się dni nie dają duplikatów - MERGE po event_id robi z nich UPDATE.
WHERE created_at > TIMESTAMP_SUB((SELECT MAX(created_at) FROM {{ this }}), INTERVAL {{ source_lookback_days }} DAY)

{% endif %}
