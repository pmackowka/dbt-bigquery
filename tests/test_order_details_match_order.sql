{# Jawny warn, choć to default projektu - czytający sam ten plik od razu widzi, że test nie blokuje
   builda. Czyli: bez routingu alertów niezgodność kończy jako wpis w logu. #}
{{ config(severity='warn') }}

/*
	Singular test: liczba pozycji w order_items ma się zgadzać z num_items_ordered w orders.
	Zwraca wiersze z rozjazdem liczb albo bez pary po jednej ze stron (stąd FULL OUTER JOIN).
	Pojedynczy przykład, nie kompletny zestaw kontroli spójności zamówienia.
*/

WITH order_details AS (
    SELECT
        order_id,
        COUNT(*) AS num_of_items_in_order

    FROM {{ ref('stg_ecommerce__order_items') }}
    GROUP BY 1
)

SELECT
    o.*,
    od.*

FROM {{ ref('stg_ecommerce__orders') }} AS o
FULL OUTER JOIN order_details AS od USING(order_id)
WHERE
    -- Każde zamówienie powinno mieć min. 1 pozycję, a każda pozycja - pasować do zamówienia
    o.order_id IS NULL
    OR od.order_id IS NULL
    -- Liczba pozycji się nie zgadza
    OR o.num_items_ordered != od.num_of_items_in_order
