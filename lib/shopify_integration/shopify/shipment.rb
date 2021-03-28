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
        page_size = 100

        count = api_get('orders/count')['count'].to_i
        total_pages = ([count, 1].max.to_f / page_size).ceil

        response = api_get_raw_response('orders', limit: page_size)
        orders = JSON.parse(response.body.force_encoding('utf-8'))['orders']
        order = orders.detect { |o| o['id'].to_s == order_number }

        current_page = 1

        while order.nil? && response.headers.key?(:link) && current_page < total_pages do
          # links can include next and previous separated by a comma
          links = response.headers[:link].to_s.split(',').map(&:strip)
          # link: <https://....?page_info=xxxx>; rel=next
          next_link = links.detect { |link| link.to_s.split(';')[1].to_s.include?('next') }
          # break if there is no link or only a previous link
          break unless next_link
          # parse the next link string to get just the query string
          next_link_params = next_link.split(';')[0].strip.slice(1...-1).split('?')[1]

          response = api_get_raw_response('orders', next_link_params)
          orders = JSON.parse(response.body.force_encoding('utf-8'))['orders']
          order = orders.detect { |o| o['id'].to_s == order_number }
          current_page += 1
        end

        order&.dig('id')
      end

      def find_shopify_location_id_by_name
        ships_from = @shipment.dig('stock_location', 'name')
        raise "Ships from location must be provided" unless ships_from.present?

        shopify_locations = api_get('locations')['locations']
        shopify_location = shopify_locations.detect do |location|
          location['name'].downcase == ships_from.downcase
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
