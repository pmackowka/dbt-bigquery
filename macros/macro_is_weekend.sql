{#
	Makro typu 1 (używane wewnątrz modelu SQL) - sprawdza, czy data w podanej kolumnie wypada w weekend.
	DAYOFWEEK w BigQuery: 1 = niedziela, 7 = sobota.
	Użycie: {{ is_weekend('od.created_at') }} - patrz models/marts/dim_orders.sql.
#}
{%- macro is_weekend(date_column) -%}
	EXTRACT(DAYOFWEEK FROM DATE({{ date_column }})) IN (1, 7)
{%- endmacro -%}