{# Staging: produkty, wersja 1 (bez kolumny brand) - patrz models/staging/stg_ecommerce__products.yml -> versions #}
WITH source AS (
	SELECT *

	FROM {{ source('thelook_ecommerce', 'products') }}
)

SELECT
	-- IDs
	id AS product_id,

	-- Other columns
	cost,
	retail_price,
	department

FROM source