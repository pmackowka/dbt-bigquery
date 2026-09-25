{# Intermediate: łączy stg_ecommerce__order_items z produktami (v2), liczy item_profit/item_discount dla dim_orders #}
{#
	Ten model MUSI zostać table/view, choć nikt go nie odpytuje wprost i wygląda na kandydata do
	ephemeral: dim_orders.sql skanuje go dbt_utils.get_column_values(), które rzuca twardy błąd dla
	modelu ephemeral (czyta information schema, więc potrzebuje relacji w bazie). Błąd wyszedłby
	w INNYM pliku niż zmieniony. Testy z int_ecommerce.yml nie są przeszkodą - dbt wkleja ephemeral
	jako CTE także do testów - ale przy ephemeral każdy z 10 testów przeliczałby join od nowa.
#}
WITH products AS (
	SELECT
		product_id,
		department AS product_department,
		cost AS product_cost,
		retail_price AS product_retail_price

	-- FROM {{ ref('stg_ecommerce__products') }}
	FROM {{ ref('stg_ecommerce__products', version=2) }} -- Model zarządzania – wersjonowanie modeli 

)

SELECT

	-- IDs
	order_items.order_item_id,
	order_items.order_id,
	order_items.user_id,
	order_items.product_id,

	-- Order item data
	order_items.item_sale_price,

	-- Product data
	products.product_department,
	products.product_cost,
	products.product_retail_price,

	-- Calculated fields
	order_items.item_sale_price - products.product_cost AS item_profit,
	products.product_retail_price - order_items.item_sale_price AS item_discount

FROM {{ ref('stg_ecommerce__order_items') }} AS order_items
LEFT JOIN products ON order_items.product_id = products.product_id