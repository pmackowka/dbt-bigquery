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

	on_schema_change='append_new_columns' - co się dzieje, gdy kolumny WYNIKU MODELU (SELECT w tym
	pliku) przestają się zgadzać z istniejącą tabelą. Trigger to edycja tego .sql, nie zmiana
	w źródle: SELECT wymienia kolumny z nazwy, więc nowa kolumna w źródle niczego tu nie zmienia,
	dopóki ktoś nie dopisze jej do SELECT-a.
	Dlaczego nie sync_all_columns (poprzednia wartość): synchronizuje w obie strony, czyli usunięcie
	kolumny z SELECT-a wykonuje na tabeli ciche DROP COLUMN - razem z całą historią tej kolumny, bez
	ostrzeżenia. W tabeli incremental historii nie odbudowuje zwykły run, tylko --full-refresh
	(tu akurat możliwy, bo źródło trzyma całą historię - ale to cecha publicznego datasetu, nie
	gwarancja). append_new_columns tylko DOKŁADA kolumny: usunięta z SELECT-a zostaje w tabeli
	z NULL-ami w nowych wierszach, a jej skasowanie jest osobną, świadomą decyzją.
	Ostrzejsza alternatywa - 'fail' (użyta w siostrzanym repo dbt-snowflake dla fct_reviews) -
	zatrzymuje build przy każdej rozbieżności i wymusza --full-refresh; przy dużej tabeli eventów
	to drogi rebuild za każdym razem, gdy model zyskuje kolumnę.

	partition_by - dzieli fizyczną tabelę w BigQuery na kawałki po dniu (created_at). Po co:
	zapytanie filtrujące po dacie (np. "eventy z ostatniego tygodnia") skanuje TYLKO partycje
	z tego zakresu, nie całą tabelę - mniej danych przeskanowanych = niższy koszt zapytania
	(BigQuery rozlicza się od ilości zeskanowanych danych) i szybszy czas odpowiedzi. Bez
	partycjonowania każde zapytanie skanowałoby całą, rosnącą tabelę.
	granularity 'day', nie 'hour' - świadoma decyzja, do zostawienia. BigQuery ma dwa limity:
	10 000 partycji na tabelę i 4 000 partycji modyfikowanych przez jeden job. Przy 'day' to
	~27 lat w tabeli i ~11 lat historii, które da się zbudować jednym --full-refresh. Przy 'hour'
	odpowiednio ~416 dni i ~166 dni - tabela rosnąca bezterminowo uderzyłaby w limit, a pełny
	rebuild padłby już po pół roku historii. Zapytania o eventy i tak filtrują po dniach.

	hours_to_expiration=none - nadpisuje globalny default z dbt_project.yml (1h w dev). Z nim
	tabela znikałaby godzinę po zbudowaniu, więc kolejny dbt run w dev prawie zawsze widziałby
	is_incremental() = false i budował od zera - ścieżka filtra i MERGE byłaby testowana dopiero
	w prod. Model incremental żyje z tego, że poprzedni stan tabeli ISTNIEJE.

	incremental_predicates - dokleja warunek do ON w generowanym MERGE (AND z dopasowaniem po
	event_id). Bez niego ON nie zawiera nic o kolumnie partycjonującej, więc BigQuery nie może
	wykluczyć żadnej partycji strony docelowej: każdy MERGE skanuje CAŁĄ historię tabeli, a koszt
	rośnie z wiekiem tabeli, nie z rozmiarem nowej porcji. Predykat na created_at ze stałą
	względem CURRENT_TIMESTAMP() pozwala przyciąć partycje docelowe do ostatnich dni.
	Pułapka: przycięta strona docelowa to też przycięte dopasowania. Wiersz ze źródła, którego
	istniejąca kopia leży POZA oknem predykatu, nie znajdzie pary i zostanie wstawiony drugi raz
	(duplikat event_id), zamiast zrobić UPDATE. Dlatego okno MERGE musi pokryć całe okno filtra
	źródła. Te dwa okna mają różne punkty odniesienia: filtr liczy od MAX(created_at) w tabeli,
	predykat od teraz. Warunek bezpieczeństwa to więc:
	    merge_lookback_days >= source_lookback_days + dni od ostatniego udanego przebiegu.
	Te same wartości w obu miejscach (np. 3 i 3) wystarczą tylko wtedy, gdy model biegnie non-stop;
	jedna przerwa w harmonogramie i MERGE zaczyna wstawiać duplikaty. 7 vs 3 toleruje ok. 4 dni
	przestoju; po dłuższym - dbt build --full-refresh -s stg_ecommerce__events. Siatka
	bezpieczeństwa: unique na event_id z severity error (stg_ecommerce__events.yml) zatrzyma
	build, jeśli duplikat jednak powstanie.
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
	{# Wywołanie UDF-a get_brand_name() (macros/macro_get_brand_name.sql), który dbt tworzy w
	   schemacie targetu automatycznie na starcie KAŻDEGO przebiegu (hook on-run-start w
	   dbt_project.yml) - stąd odwołanie przez {{ target.schema }}, nie przez nazwę modelu/ref(). #}
	{{ target.schema }}.get_brand_name(uri) AS brand_name

FROM source

{% if is_incremental() %}

-- Filtr aktywny TYLKO przy przebiegach po pierwszym (is_incremental() jest false przy pierwszym
-- dbt run i przy --full-refresh) - dolicza eventy od ostatniego stanu tabeli, zamiast przeliczać
-- całą historię od zera.
-- Okno wsteczne (source_lookback_days), a nie samo "> MAX(created_at)": event, który dotarł do
-- źródła z opóźnieniem, ma poprawny, STARY created_at - mniejszy niż MAX w tabeli. Filtr bez
-- marginesu pominąłby go na zawsze, bez błędu i przy zielonym buildzie. Ten sam wzorzec co przy
-- eksporcie GA4 do BigQuery, gdzie dane dociągają się do ~72h. Nakładające się dni nie tworzą
-- duplikatów, bo unique_key='event_id' zamienia je w UPDATE w MERGE.
WHERE created_at > TIMESTAMP_SUB((SELECT MAX(created_at) FROM {{ this }}), INTERVAL {{ source_lookback_days }} DAY)

{% endif %}
