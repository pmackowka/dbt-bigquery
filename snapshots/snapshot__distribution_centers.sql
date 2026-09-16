{#
	Snapshot = zdjęcie stanu tabeli źródłowej w konkretnym momencie, zapisywane do OSOBNEJ,
	rosnącej tabeli historii (nie nadpisywanej jak zwykły model) - to implementacja SCD2 (Slowly
	Changing Dimension typu 2): każda zmiana w distribution_centers tworzy nowy wiersz z własnym
	okresem ważności, zamiast nadpisywać stary. dbt dokłada automatycznie 4 kolumny techniczne:
	dbt_scd_id (hash wersji rekordu), dbt_updated_at, dbt_valid_from, dbt_valid_to (NULL = wersja
	aktualna). Bez tego dbt run po prostu nadpisałby starą wartość i historia zmian by przepadła.

	Uruchamiane WYŁĄCZNIE przez `dbt snapshot` (dbt run/build tego nie robi) - trzeba pamiętać
	o odpaleniu tej komendy regularnie (np. w CI/CD przed dbt build), inaczej snapshot się nie
	zaktualizuje mimo że źródłowe dane się zmieniły.

	target_schema='snapshots_project' - osobny schemat na tabele snapshotów, świadome oddzielenie
	od schematów modeli (staging/marts), żeby nie zgubić, które tabele w BigQuery to zwykłe modele
	(nadpisywane przy każdym run), a które to rosnąca historia zmian.

	unique_key='id' - klucz, po którym dbt rozpoznaje "to ten sam rekord co poprzednio" - bez
	tego każdy przebieg tworzyłby nowe wiersze zamiast wykrywać zmiany istniejących.

	strategy='check', nie 'timestamp' - tabela źródłowa NIE MA kolumny updated_at (w odróżnieniu
	np. od modeli w repo dbt-snowflake, gdzie strategy='timestamp' jest możliwe właśnie dlatego,
	że tam taka kolumna istnieje). 'check' więc porównuje WARTOŚCI wskazanych kolumn między
	bieżącym stanem a ostatnim snapshotem, zamiast polegać na znaczniku czasu, którego tu po
	prostu nie ma.

	check_cols=['name', 'latitude', 'longitude'] - tylko te 3 kolumny biznesowe faktycznie mogą
	się zmienić w tym źródle (np. przy przeniesieniu centrum dystrybucji). Świadomie NIE ma tu
	'id' - to unique_key, zmiana id oznaczałaby inny rekord, nie edycję tego samego.
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
