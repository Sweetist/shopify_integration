module ShopifyIntegration
  module Shopify
    class Shipment
      include APIHelper

      def initialize(payload, config)
        @shipment = payload
        @config = config
      end

      def ship!
        if @shipment['status'] == 'received' && shopify_order_id

          begin
            api_post(
              "orders/#{shopify_order_id}/fulfillments.json",
              {
                fulfillment: {
                  tracking_number: @shipment['tracking'],
                  location_id: find_shopify_location_id_by_name
                }
              }
            )
          rescue RestClient::UnprocessableEntity
            raise "Shipment #{@shipment['id']} has already been marked as shipped in Shopify!"
          end

          "Updated shipment #{@shipment['id']} with tracking number #{@shipment['tracking']}."
        else
          raise "Order #{@shipment['order_id']} not found in Shopify" unless shopify_order_id
        end
      end

      def shopify_order_id
        @shopify_order_id ||= @shipment['shopify_order_id']         \
          || @config.dig('sync_id')                                 \
          || find_order_id_by_order_number(@shipment['order_id'])
      end

      def find_order_id_by_order_number(order_number)
        order_number = order_number.split("-").last
        count = (api_get 'orders/count')['count']
        page_size = 250
        pages = (count / page_size.to_f).ceil
        current_page = 1

        while current_page <= pages do
          response = api_get 'orders',
                             {'limit' => page_size, 'page' => current_page}
          current_page += 1
          response['orders'].each do |order|
            return order['id'].to_s if order['order_number'].to_s == order_number
          end
        end

        return nil
      end

      def find_shopify_location_id_by_name
        ships_from = @shipment.dig('stock_location', 'name')
        raise "Ships from location must be provided" unless ships_from.present?
        
        shopify_locations = api_get('locations')['locations']
        shopify_location = shopify_locations.detect do |location|
          location['name'].downcase == ships_from
        end

        # if there is only one location in Shopify, use that for fulfillments
        if shopify_location.nil? && shopify_locations.count == 1
          shopify_location = shopify_locations.first
        end

        raise "Unable to find matching stock location '#{ships_from}' to ship from in Shopify" unless shopify_location

        shopify_location['id']
      end
    end
  end
end
