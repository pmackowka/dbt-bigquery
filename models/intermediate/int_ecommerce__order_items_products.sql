{# Intermediate: łączy stg_ecommerce__order_items z produktami (v2), liczy item_profit/item_discount dla dim_orders #}
{#
	Ten model MUSI zostać table/view - nie może być ephemeral, choć nikt go nie odpytuje wprost
	i na pierwszy rzut oka to kandydat do "optymalizacji" (jak int_ecommerce__first_order_created).
	Blokują to dwie rzeczy, obie niewidoczne z tego pliku:
	(a) dim_orders.sql skanuje go dbt_utils.get_column_values() przy kompilacji, a makro rzuca
	    twardy błąd dla modelu ephemeral (czyta z information schema, więc potrzebuje relacji
	    w bazie) - błąd pojawi się w INNYM pliku niż ten zmieniony;
	(b) int_ecommerce.yml ma na nim testy (m.in. unique/not_null na order_item_id z severity
	    error), a test potrzebuje obiektu w bazie, którego ephemeral nie tworzy.
	Reguła: ephemeral tylko dla modelu, którego nikt nie testuje, nie odpytuje i nie skanuje
	makrem. first_order_created spełnia wszystkie trzy warunki, ten model - żadnego.
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