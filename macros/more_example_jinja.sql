{#
	Makro typu 3 (operacja), odpalane ręcznie: dbt run-operation more_example_jinja --profiles-dir .
	Introspekcja w czasie wykonania: adapter.get_columns_in_relation() czyta kolumny zbudowanego
	dim_orders, get_column_values() - wartości order_status. Wynik tylko w logu.
	Martwy kod dla pipeline'u, zostaje jako jedyny przykład introspekcji relacji w tym repo.
	W projekcie produkcyjnym nie przeszedłby przeglądu - nic nie buduje, a nazwa nic nie mówi.
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