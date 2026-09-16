{#
	Data pierwszego zamówienia per user_id, wklejane jako CTE do dim_orders (liczy
	days_since_first_order).

	materialized='ephemeral', nie table/view: ten wynik jest używany tylko w JEDNYM miejscu
	(dim_orders.sql) i to prosta, szybka agregacja - nie ma sensu trzymać go jako osobną tabelę/
	widok w BigQuery, skoro nikt inny go nie potrzebuje. dbt wkleja tę logikę bezpośrednio jako
	CTE do zapytania dim_orders przy kompilacji - nie da się go za to przetestować/zapytać
	osobno (ephemeral nie tworzy żadnego obiektu w bazie, którego można by dotknąć).
#}
{{
	config(materialized='ephemeral')
}}


SELECT
	user_id,
	MIN(created_at) AS first_order_created_at

FROM {{ ref('stg_ecommerce__orders') }}
GROUP BY 1