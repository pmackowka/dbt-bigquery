{#
	Makro typu 2 (hook) - on-run-start w dbt_project.yml, więc na początku KAŻDEGO przebiegu dbt
	(run/build/test/seed/snapshot) robi CREATE OR REPLACE UDF get_brand_name() w schemacie targetu.
	Używane w stg_ecommerce__events.sql do wyciągnięcia marki z URL-a.

	Regex ".+/brand/(.+)" dla "/department/men/category/active/brand/columbia":
	- ".+/brand/" dopasowuje wszystko do "/brand/" włącznie,
	- "(.+)" to grupa przechwytująca - REGEXP_EXTRACT zwraca tylko ją, czyli "columbia".
#}

{% macro get_brand_name() %}
	-- Tworzymy lub zastępujemy funkcję w docelowym schemacie, która wyodrębnia nazwę marki z linku
	CREATE OR REPLACE FUNCTION {{ target.schema }}.get_brand_name(web_link STRING)
	RETURNS STRING
	AS (
		-- Funkcja REGEXP_EXTRACT służy do wyodrębnienia nazwy marki z linku (web_link)
		-- Wyrażenie regularne r'.+/brand/(.+)' pasuje do tekstu po "/brand/"
		REGEXP_EXTRACT(web_link, r'.+/brand/(.+)')
	)
{% endmacro %}