{# Mart: finalna tabela zamówień - agreguje int_ecommerce__order_items_products i int_ecommerce__first_order_created #}
{#
	Lista działów przychodzi z DANYCH (zapytanie do bazy przy kompilacji), więc schemat tego
	modelu może się zmienić bez zmiany w kodzie. Dwie blokady w projekcie: accepted_values na
	department (severity error, stg_ecommerce__products.yml) i kontrakt w dim_orders.yml.
	Nazwa kolumny {{ department.lower() }}swear działa tylko dlatego, że 'men'/'women' + 'swear'
	przypadkiem dają sensowne słowo - nowy dział 'Kids' dałby total_sold_kidsswear. Czystsza forma
	(total_sold_{{ department | lower | replace(' ', '_') }}) zmienia nazwy istniejących kolumn
	publicznego martu, czyli jest zmianą łamiącą - wymaga nowej wersji modelu (jak v1/v2 przy
	stg_ecommerce__products), dlatego na razie zostaje stary wzór.
	dbt parse NIE sprawdza tej pętli: przy parsowaniu execute = false, get_column_values zwraca
	pustą listę i model "kompiluje się" bez żadnej kolumny total_sold_*. Realna weryfikacja
	wymaga dbt compile/build z połączeniem.
#}
{%- set departments = dbt_utils.get_column_values(table=ref('int_ecommerce__order_items_products'), column='product_department') -%}

WITH

-- Aggregate measures
order_item_measures AS (
	SELECT
		order_id,
		SUM(item_sale_price) AS total_sale_price,
		SUM(product_cost) AS total_product_cost,
		SUM(item_profit) AS total_profit,
		SUM(item_discount) AS total_discount,

		{% for department in departments %}
		SUM(IF(product_department = '{{ department }}', item_sale_price, 0)) AS total_sold_{{ department.lower() }}swear{{ "," if not loop.last }}
		{%- endfor %}

	FROM {{ ref('int_ecommerce__order_items_products') }}
	GROUP BY 1
)

SELECT
	od.order_id,
	od.created_at AS order_created_at,
	{{ is_weekend('od.created_at') }} AS order_was_created_on_weekend,
	od.shipped_at AS order_shipped_at,
	od.delivered_at AS order_delivered_at,
	od.returned_at AS order_returned_at,
	od.status AS order_status,
	od.num_items_ordered,
	om.total_sale_price,
	om.total_product_cost,
	om.total_profit,
	om.total_discount,

	{% for department in departments %}
	om.total_sold_{{ department.lower() }}swear,
	{%- endfor %}
	-- In practise we'd calculate this column in the model itself, but it's
	-- a good way to demonstrate how to use an ephemeral materialisation
	TIMESTAMP_DIFF(od.created_at, user_data.first_order_created_at, DAY) AS days_since_first_order

FROM {{ ref('stg_ecommerce__orders') }} AS od
LEFT JOIN order_item_measures AS om
	ON od.order_id = om.order_id
LEFT JOIN {{ ref('int_ecommerce__first_order_created') }} AS user_data
	ON od.user_id = user_data.user_id