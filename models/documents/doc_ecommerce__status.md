<!-- Blok dokumentacji wielokrotnego użytku (doc()). Odwołanie: description: "{{ doc('status') }}"
     w models/staging/stg_ecommerce__orders.yml i models/marts/dim_orders.yml - jedna definicja,
     dwa miejsca użycia, bez duplikowania opisu. -->
{% docs status %}

The status of the order. Can be one of:
- Processing
- Cancelled
- Shipped
- Complete
- Returned

{% enddocs %}