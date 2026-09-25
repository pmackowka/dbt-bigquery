{#
	Snapshot SCD2: każda zmiana w distribution_centers dopisuje nowy wiersz z okresem ważności do
	OSOBNEJ, rosnącej tabeli historii, zamiast nadpisywać stary. dbt dokłada kolumny dbt_scd_id,
	dbt_updated_at, dbt_valid_from, dbt_valid_to (NULL = wersja aktualna).

	Uruchamia go dbt snapshot albo dbt build - dbt run go pomija. Historia powstaje tylko w momentach
	przebiegu: zmiana, która pojawi się i zniknie między dwoma przebiegami, nie zostanie zapisana.

	target_schema='snapshots_project' - osobny schemat, żeby odróżnić rosnącą historię od modeli
	nadpisywanych przy każdym run. UWAGA: target_schema jest używany dosłownie, bez prefiksu
	target.schema (w odróżnieniu od nowego configu schema=), więc przy jednym projekcie GCP dev
	i prod piszą do TEJ SAMEJ tabeli historii. Rozdziela je dopiero osobny projekt GCP dla prod
	(profiles.yml.example). Przejście na schema= porzuciłoby istniejącą historię - wymaga migracji.

	unique_key='id' - po nim dbt rozpoznaje ten sam rekord; bez niego każdy przebieg dopisywałby
	wiersze zamiast wykrywać zmiany.

	strategy='check', nie 'timestamp' - źródło nie ma kolumny updated_at, więc dbt porównuje
	WARTOŚCI kolumn z check_cols. id nie jest na liście, bo to unique_key - inne id to inny rekord.
#}
{% snapshot snapshot__distribution_centers %}

{{
	config(
		target_schema='snapshots_project',
		unique_key='id',
		strategy='check',
		check_cols=['name', 'latitude', 'longitude']
	)
}}

SELECT
	id,
	name,
	latitude,
	longitude

FROM {{ source('thelook_ecommerce', 'distribution_centers') }}

{% endsnapshot %}
