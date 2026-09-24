{# Intermediate: łączy stg_ecommerce__order_items z produktami (v2), liczy item_profit/item_discount dla dim_orders #}
{#
	Ten model MUSI zostać table/view - nie może być ephemeral, choć nikt go nie odpytuje wprost
	i na pierwszy rzut oka to kandydat do "optymalizacji" (jak int_ecommerce__first_order_created).
	Blokuje to rzecz niewidoczna z tego pliku: dim_orders.sql skanuje go
	dbt_utils.get_column_values() przy kompilacji, a makro rzuca twardy błąd dla modelu
	ephemeral (czyta z information schema, więc potrzebuje relacji w bazie) - błąd pojawi się
	w INNYM pliku niż ten zmieniony.
	Testy w int_ecommerce.yml (unique/not_null na order_item_id) NIE są blokadą: test na modelu
	ephemeral działa, bo dbt wkleja model jako CTE do SQL testu.
	Reguła: ephemeral tylko dla modelu, który nie musi istnieć jako relacja w bazie - nikt go
	nie odpytuje wprost ani nie skanuje makrem przy kompilacji. first_order_created ten warunek
	spełnia, ten model nie (przez get_column_values).
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