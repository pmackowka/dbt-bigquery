"""Atrapa pakietu dbt_utils dla templatera jinja w sqlfluff.

Lint w kroku 0 działa bez połączenia z BigQuery, a prawdziwe dbt_utils.get_column_values odpytuje
hurtownię w czasie kompilacji. sqlfluff ładuje moduły z library_path jako obiekty w kontekście
Jinja, więc `dbt_utils.get_column_values(...)` w dim_orders.sql trafia tutaj.
"""


def get_column_values(table=None, column=None, **kwargs):
    # Stała lista o tym samym kształcie co prawdziwe dane (działy produktów) - lintowi wystarczy,
    # że pętla w dim_orders.sql wygeneruje poprawny składniowo SQL.
    return ["Men", "Women"]
