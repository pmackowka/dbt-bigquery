{#
	Makro typu 3 (operacja) - własna, zmodyfikowana wersja makra generate_base_model z pakietu
	dbt-labs/codegen. Generuje gotowy szkielet SQL modelu staging (SELECT * z source + rename
	id -> <tabela_w_liczbie_pojedynczej>_id) na podstawie metadanych kolumn źródła.
	Sam pakiet codegen NIE jest zainstalowany (patrz packages.yml): makro projektu i tak ma
	pierwszeństwo przed makrem pakietu o tej samej nazwie, więc trzymanie obu dawało tylko
	mylące wrażenie, że działa wersja z pakietu. Kopia potrzebuje wyłącznie wbudowanych funkcji
	dbt (source, adapter.get_columns_in_relation).
	Wywołanie: dbt run-operation generate_base_model --args '{"source_name": "thelook_ecommerce", "table_name": "orders"}'
	Wynik trafia do logu (log(..., info=True)) - trzeba go ręcznie wkleić do nowego pliku .sql,
	makro niczego samo nie zapisuje na dysk.
#}
{% macro generate_base_model(source_name, table_name, case_sensitive_cols=False, materialized=None) %}

{%- set source_relation = source(source_name, table_name) -%}

{%- set columns = adapter.get_columns_in_relation(source_relation) -%}
{% set column_names=columns | map(attribute='name') %}
{% set base_model_sql %}

{%- if materialized is not none -%}
	{{ "{{ config(materialized='" ~ materialized ~ "') }}" }}
{%- endif %}

WITH source AS (
	SELECT *

	FROM {% raw %}{{ source({% endraw %}'{{ source_name }}', '{{ table_name }}'{% raw %}) }}{% endraw %}
)

SELECT
{%- for column in column_names %}
	{%- if column == 'id' -%}
	{# Kolumnę 'id' zmienia na <nazwa_tabeli_w_liczbie_pojedynczej>_id (np. orders -> order_id).
	   Po co: w tabelach, do których orders się odwołuje (order_items.order_id), klucz obcy już
	   nazywa się order_id, nie id - to ujednolica nazewnictwo klucza głównego z nazwą, pod jaką
	   występuje jako klucz obcy gdzie indziej, więc join'y są czytelniejsze (order_id = order_id,
	   nie id = order_id). #}
	id AS {{ table_name[:-1] }}_id{{"," if not loop.last}}
	{%- else -%}
	{# Każdą inną kolumnę (nie 'id') przepisuje bez zmian - brak dobrego, ogólnego wzorca
	   przemianowania dla kolumn innych niż klucz główny. #}
	{{ column }}{{"," if not loop.last}}
	{%- endif -%}
{%- endfor %}

FROM source

{% endset %}

{% if execute %}

{{ log(base_model_sql, info=True) }}
{% do return(base_model_sql) %}

{% endif %}
{% endmacro %}