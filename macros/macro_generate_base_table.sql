{#
	Makro typu 3 (operacja) - własna kopia/nadpisanie makra generate_base_model z pakietu
	dbt-labs/codegen. Generuje gotowy szkielet SQL modelu staging (SELECT * z source + rename
	id -> <tabela_w_liczbie_pojedynczej>_id) na podstawie metadanych kolumn źródła.
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
	{# Takes the table name, strips the last letter to make it singular (e.g orders --> order)
	   and appends "_id" to create a primary key that matches the name of foreign keys #}
	id AS {{ table_name[:-1] }}_id{{"," if not loop.last}}
	{%- else -%}
	{# Otherwise, just takes the column name #}
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