{#
	Data pierwszego zamówienia per user_id, wklejane jako CTE do dim_orders (liczy
	days_since_first_order).

	materialized='ephemeral', nie table/view: ten wynik jest używany tylko w JEDNYM miejscu
	(dim_orders.sql) i to prosta, szybka agregacja - nie ma sensu trzymać go jako osobną tabelę/
	widok w BigQuery, skoro nikt inny go nie potrzebuje. dbt wkleja tę logikę bezpośrednio jako
	CTE do zapytania dim_orders przy kompilacji - nie da się go za to zapytać osobno ani użyć
	w dbt run-operation (ephemeral nie tworzy żadnego obiektu w bazie). Testować się go da:
	dbt wkleja ten sam CTE do SQL testu (patrz not_null na user_id w int_ecommerce.yml).
#}
{{
	config(materialized='ephemeral')
}}


SELECT
	user_id,
	MIN(created_at) AS first_order_created_at

FROM {{ ref('stg_ecommerce__orders') }}
GROUP BY 1