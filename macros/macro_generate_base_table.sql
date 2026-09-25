{#
	Makro typu 3 (operacja) - zmodyfikowana kopia generate_base_model z dbt-labs/codegen: generuje
	szkielet modelu staging z metadanych kolumn źródła (z rename id -> <tabela>_id).
	Pakietu codegen celowo nie ma w packages.yml - makro projektu i tak wygrywa z makrem pakietu
	o tej samej nazwie, a kopia używa tylko wbudowanych funkcji dbt.
	Wywołanie: dbt run-operation generate_base_model --args '{"source_name": "thelook_ecommerce", "table_name": "orders"}'
	Wynik trafia tylko do logu - trzeba go ręcznie wkleić do nowego pliku .sql.
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
	{# id -> <tabela w liczbie pojedynczej>_id (orders -> order_id): klucz główny nazywa się tak jak
	   klucz obcy w innych tabelach, więc join to order_id = order_id, a nie id = order_id. #}
	id AS {{ table_name[:-1] }}_id{{"," if not loop.last}}
	{%- else -%}
	{# Pozostałe kolumny bez zmian - dla nich nie ma ogólnego wzorca nazewnictwa. #}
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