{#
	Makro typu 3 (operacja) - nie jest wywoływane z żadnego modelu, tylko ręcznie z terminala:
	dbt run-operation more_example_jinja --profiles-dir .
	Przykład introspekcji: adapter.get_columns_in_relation() czyta metadane kolumn zbudowanego
	modelu dim_orders, dbt_utils.get_column_values() odpytuje bazę o realne wartości w kolumnie
	order_status. Wynik trafia tylko do logu (log(..., info=True)), nic nie materializuje.

	Martwy kod z punktu widzenia pipeline'u (zero konsumentów) - zostaje, bo to repo pełni też
	funkcję portfolio dydaktycznego: to jedyny przykład introspekcji relacji w czasie wykonania
	(adapter.get_columns_in_relation). W projekcie produkcyjnym takie makro nie przetrwałoby
	przeglądu - nie buduje niczego, a nazwa nie mówi, do czego służy.
#}
{% macro more_example_jinja() %}
  {% set columns = adapter.get_columns_in_relation(ref('dim_orders')) %}

  {% set selected_columns = [] %}
  {% for column in columns %}
    {% if column.name.startswith('total') %}
      {% do selected_columns.append(column.name.upper()) %}
    {% endif %}
  {% endfor %}

  {% set values = dbt_utils.get_column_values(ref('dim_orders'), 'order_status') %}

  {{ log("Kolumny: " ~ selected_columns | join(', '), info=True) }}
  {{ log("Wartości z order_status: " ~ values | join(', '), info=True) }}

  {{ return("Makro wykonane – sprawdź log powyżej.") }}
{% endmacro %}