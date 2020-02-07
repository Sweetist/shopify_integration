module ShopifyIntegration
  class Order
    attr_reader :shopify_id, :email, :shipping_address, :billing_address

    def add_shopify_obj shopify_order, shopify_api
      @store_name = Util.shopify_host(shopify_api.config).split('.')[0]
      @order_number = order_number_from_shopify(shopify_order)
      @shopify_id = shopify_order['id']
      @source = Util.shopify_host shopify_api.config
      @canceled_date = shopify_order['cancelled_at']
      @fulfillment_status = shopify_order['fulfillment_status']
      @status = order_status
      @email = shopify_order['email']
      @customer_id = shopify_order['customer']['id'] if shopify_order['customer']
      @currency = shopify_order['currency']
      @placed_on = shopify_order['created_at']
      @totals_item = shopify_order['total_line_items_price'].to_f
      @totals_tax = shopify_order['total_tax'].to_f
      @totals_discounts = shopify_order['total_discounts'].to_f
      @totals_shipping = 0.00
      shopify_order['shipping_lines'].each do |shipping_line|
        @totals_shipping += shipping_line['price'].to_f
      end
      @payments = []
      @totals_payment = 0.00
      @tax_lines = shopify_order['tax_lines']
      @shipping_lines = shopify_order['shipping_lines']
      @fulfillments = shopify_order['fulfillments']
                      .map do |f|
                        f.slice('tracking_number',
                                'tracking_company')
                      end
      @totals_order = shopify_order['total_price'].to_f
      @line_items = []
      shopify_order['line_items']
        .map { |f| f.except('admin_graphql_api_id') }
        .each do |shopify_li|
        line_item = LineItem.new
        @line_items << line_item.add_shopify_obj(shopify_li, shopify_api)
      end

      unless shopify_order['shipping_address'].nil?
        @shipping_address = {
          'firstname' => shopify_order['shipping_address']['first_name'],
          'lastname' => shopify_order['shipping_address']['last_name'],
          'company' => shopify_order['shipping_address']['company'],
          'address1' => shopify_order['shipping_address']['address1'],
          'address2' => shopify_order['shipping_address']['address2'],
          'zipcode' => shopify_order['shipping_address']['zip'],
          'city' => shopify_order['shipping_address']['city'],
          'state' => shopify_order['shipping_address']['province'],
          'country' => shopify_order['shipping_address']['country_code'],
          'phone' => shopify_order['shipping_address']['phone']
        }
      end

      unless shopify_order['billing_address'].nil?
        @billing_address = {
          'firstname' => shopify_order['billing_address']['first_name'],
          'lastname' => shopify_order['billing_address']['last_name'],
          'company' => shopify_order['billing_address']['company'],
          'address1' => shopify_order['billing_address']['address1'],
          'address2' => shopify_order['billing_address']['address2'],
          'zipcode' => shopify_order['billing_address']['zip'],
          'city' => shopify_order['billing_address']['city'],
          'state' => shopify_order['billing_address']['province'],
          'country' => shopify_order['billing_address']['country_code'],
          'phone' => shopify_order['billing_address']['phone']
        }
      end

      self
    end

    def order_status
      return 'fulfilled' if @fulfillment_status == 'fulfilled'
      return 'cancelled' if @canceled_date
      'completed'
    end

    def order_number_from_shopify(shopify_order)
      num = shopify_order['name'].to_s
      return num unless num.start_with?('#')
      num[1..-1].strip
    end

    def wombat_obj
      {
        'id' => @store_name.upcase + '-' + @order_number.to_s,
        'display_number' => @order_number.to_s,
        'shopify_id' => @shopify_id.to_s,
        'source' => @source,
        'channel' => @source,
        'status' => @status,
        'email' => @email,
        'customer_id' => @customer_id,
        'currency' => @currency,
        'placed_on' => @placed_on,
        'tax_lines' => @tax_lines,
        'totals' => {
          'item' => @totals_item,
          'tax' => @totals_tax,
          'shipping' => @totals_shipping,
          'payment' => @totals_payment,
          'order' => @totals_order
        },
        'line_items' => Util.wombat_array(@line_items),
        'adjustments' => [
          {
            'name' => 'Discounts',
            'value' => -@totals_discounts
          }
        ],
        'fulfillments' => @fulfillments,
        'shipping_lines' => @shipping_lines,
        'shipping_address' => @shipping_address,
        'billing_address' => @billing_address,
        'payments' => Util.wombat_array(@payments)
      }
    end
  end
end
