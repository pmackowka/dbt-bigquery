{#
	Staging: eventy użytkowników (thelook_ecommerce.events).

	Jedyny model incremental w tym projekcie (reszta to table) - świadomy wybór, nie domyślne
	ustawienie: events to tabela zdarzeń (kliknięcia, wizyty), która w realnym sklepie rośnie
	milionami wierszy dziennie. Materializacja 'table' przeliczałaby CAŁĄ historię od zera przy
	każdym dbt run - drogo (skanowanie BigQuery liczone od ilości danych) i wolno. Incremental
	dokłada tylko nowe wiersze od ostatniego przebiegu.
#}
{#
	unique_key='event_id' - klucz, po którym dbt rozpoznaje ten sam event przy kolejnych
	przebiegach (potrzebne przy strategii merge/upsert - bez tego incremental tylko dokleja
	wiersze, nie potrafi rozpoznać duplikatu, gdyby ten sam event trafił do źródła dwa razy).

	on_schema_change='sync_all_columns' - jeśli źródłowa tabela events dostanie nową/usuniętą
	kolumnę, dbt sam dostosuje schemat docelowej tabeli przy najbliższym run. Alternatywa -
	on_schema_change='fail' (użyta w siostrzanym repo dbt-snowflake dla fct_reviews) świadomie
	przerywa build zamiast automatycznie dostosowywać schemat; tu wybrano wygodę automatycznej
	synchronizacji, bo events to tabela wewnętrzna projektu (mniejsze ryzyko niespodziewanej,
	cichej zmiany struktury niż przy tabeli współdzielonej z innym zespołem/systemem).

	partition_by - dzieli fizyczną tabelę w BigQuery na kawałki po dniu (created_at). Po co:
	zapytanie filtrujące po dacie (np. "eventy z ostatniego tygodnia") skanuje TYLKO partycje
	z tego zakresu, nie całą tabelę - mniej danych przeskanowanych = niższy koszt zapytania
	(BigQuery rozlicza się od ilości zeskanowanych danych) i szybszy czas odpowiedzi. Bez
	partycjonowania każde zapytanie skanowałoby całą, rosnącą tabelę.

	hours_to_expiration=none - nadpisuje globalny default z dbt_project.yml (1h w dev). Z nim
	tabela znikałaby godzinę po zbudowaniu, więc kolejny dbt run w dev prawie zawsze widziałby
	is_incremental() = false i budował od zera - ścieżka filtra i MERGE byłaby testowana dopiero
	w prod. Model incremental żyje z tego, że poprzedni stan tabeli ISTNIEJE.
#}
{{
	config(
		materialized='incremental',
		hours_to_expiration=none,
		unique_key='event_id',
		on_schema_change='sync_all_columns',
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
	{# Wywołanie UDF-a get_brand_name() (macros/macro_get_brand_name.sql), który dbt tworzy w
	   schemacie targetu automatycznie na starcie KAŻDEGO przebiegu (hook on-run-start w
	   dbt_project.yml) - stąd odwołanie przez {{ target.schema }}, nie przez nazwę modelu/ref(). #}
	{{ target.schema }}.get_brand_name(uri) AS brand_name

FROM source

{% if is_incremental() %}

-- Filtr aktywny TYLKO przy przebiegach po pierwszym (is_incremental() jest false przy pierwszym
-- dbt run i przy --full-refresh) - dolicza wyłącznie eventy nowsze niż to, co już jest w tabeli,
-- zamiast przeliczać całą historię od zera.
WHERE created_at > (SELECT MAX(created_at) FROM {{ this }})

{% endif %}
