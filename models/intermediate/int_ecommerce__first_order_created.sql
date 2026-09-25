{#
	Data pierwszego zamówienia per user_id - dim_orders liczy z niej days_since_first_order.

	ephemeral: wynik używany w jednym miejscu, prosta agregacja - nie ma po co trzymać osobnej tabeli.
	dbt wkleja tę logikę jako CTE do dim_orders (i do testu z int_ecommerce.yml). Koszt: modelu nie
	da się odpytać w konsoli, bo nie ma go w bazie, a debugowanie wymaga czytania skompilowanego SQL.
#}
{{
	config(materialized='ephemeral')
}}


SELECT
	user_id,
	MIN(created_at) AS first_order_created_at

FROM {{ ref('stg_ecommerce__orders') }}
GROUP BY 1