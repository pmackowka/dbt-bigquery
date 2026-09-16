{# Jawny severity='warn', mimo że to i tak domyślne ustawienie projektu (dbt_project.yml -
   tests: +severity: warn) - celowa nadmiarowość: ktoś czytający TYLKO ten plik (bez otwierania
   dbt_project.yml) od razu widzi, że niezgodność ma tylko ostrzegać, nie blokować builda. #}
{{ config(severity='warn') }}

/*
	Sprawdza, czy dla każdego zamówienia liczba pozycji w tabeli order_items
	zgadza się z kolumną num_items_ordered w tabeli orders.

	Zwraca wszystkie wiersze, w których liczba się nie zgadza (albo w ogóle brak dopasowania
	po jednej ze stron - FULL OUTER JOIN niżej wyłapuje też takie przypadki, nie tylko
	rozjazd liczb).

	Można by dorzucić tu więcej kontroli (np. że każde zamówienie ma dokładnie 1 user_id, albo
	że znaczniki czasu shipped_at są spójne w ramach jednego zamówienia), ale to tylko przykład
	pojedynczego testu (singular test) - nie ma ambicji być kompletnym zestawem kontroli.
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
