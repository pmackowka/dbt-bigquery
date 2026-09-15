{# Ephemeral: data pierwszego zamówienia per user_id, wklejane jako CTE do dim_orders (liczy days_since_first_order) #}
{{
	config(materialized='ephemeral')
}}


SELECT
	user_id,
	MIN(created_at) AS first_order_created_at

FROM {{ ref('stg_ecommerce__orders') }}
GROUP BY 1