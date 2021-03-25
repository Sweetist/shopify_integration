require 'json'
require 'rest-client'
require 'pp'

module ShopifyIntegration
  class ShopifyAPI
    include Shopify::APIHelper

    attr_accessor :order, :config, :payload, :request

    def initialize payload, config={}
      @payload = payload
      @config = config
    end

    def cancel_order
      api_post "orders/#{@config.dig('sync_id')}/cancel.json", {}
    end

    def get_products
      inventories = Array.new
      products = get_objs('products', Product)
      products.each do |product|
        unless product.variants.nil?
          product.variants.each do |variant|
            unless variant.sku.blank?
              inventory = Inventory.new
              inventory.add_obj variant
              inventories << inventory.wombat_obj
            end
          end
        end
      end

      {
        'objects' => Util.wombat_array(products),
        'message' => "Successfully retrieved #{products.length} products " +
                     "from Shopify.",
        'additional_objs' => inventories,
        'additional_objs_name' => 'inventory'
      }
    end

    def get_customers
      get_webhook_results 'customers', Customer
    end

    def get_inventory
      inventories = Array.new
      get_objs('products', Product).each do |product|
        unless product.variants.nil?
          product.variants.each do |variant|
            unless variant.sku.blank?
              inventory = Inventory.new
              inventory.add_obj variant
              inventories << inventory.wombat_obj
            end
          end
        end
      end
      get_reply inventories, "Retrieved inventories."
    end

    def get_shipments
      shipments = Array.new
      get_objs('orders', Order).each do |order|
        shipments += shipments(order.shopify_id)
      end
      get_webhook_results 'shipments', shipments, false
    end

    def get_refunds
      get_webhook_results 'refunds', refunds(config['order_id']), false
    end

    def get_payments
      payments = []
      transactions(config['order_id']).each do |transaction|
        payment = Payment.new
        payments << payment.add_shopify_obj(transaction)
      end
      get_webhook_results 'payments', payments, false
    end

    def get_orders
      get_webhook_results 'orders', Order
      orders = Util.wombat_array(get_objs('orders', Order))

      response = {
        'objects' => orders,
        'message' => "Successfully retrieved #{orders.length} orders " +
                     "from Shopify."
      }

      # config to return corresponding shipments
      if @config[:create_shipments].to_i == 1
        shipments = Array.new
        orders.each do |order|
          shipments << Shipment.wombat_obj_from_order(order)
        end

        response.merge({
          'additional_objs' => shipments,
          'additional_objs_name' => 'shipment'
        })
      else
        response
      end
    end

    def add_product
      product = Product.new
      product.add_wombat_obj @payload['product'], self

      product_id = find_product_shopify_id_by_sku_or_name(product.sku,
                                                          product.name)
      if product_id
        product.shopify_id = product_id
        return update_product(product)
      end

      if product.variants.any?
        result = api_post 'products.json', product.shopify_obj
        product.variants.each do |variant|
          set_inventory_levels(variant, result.dig('product','variants').detect {|item| item['sku'] == variant.sku}['inventory_item_id'])
        end
      else
        result = api_post 'products.json', product.shopify_obj_no_variants
        set_inventory_levels(product.master, result.dig('product', 'variants').first['inventory_item_id'])
      end

      {
        'message' => 'Product added with Shopify ID of ' \
  "#{result['product']['id']} was added.",
        'objects' => result
      }
    end

    def update_variant(variant)
      if variant_id = (variant.shopify_id || find_product_shopify_id_by_sku(variant.sku))
        updated_shopify_variant = api_put(
          "variants/#{variant_id}.json",
          variant.shopify_obj
        )

        # equates to checking that the variant is an inventory type variant
        set_inventory_levels(variant, updated_shopify_variant.dig('variant','inventory_item_id'))
      else
        raise "No variants with SKU: #{variant.sku}"
      end
    end

    def set_inventory_levels(variant, shopify_inventory_item_id)
      return unless variant.inventory_management && shopify_inventory_item_id
      return if variant.shopify_inventory_levels.none?

      shopify_inventory_levels = api_get('inventory_levels', {inventory_item_ids: shopify_inventory_item_id})['inventory_levels']
      shopify_locations = api_get('locations')['locations']
      only_one_location = shopify_locations.size == 1 && variant.shopify_inventory_levels.size == 1
      any_location_synced = false
      variant.shopify_inventory_levels.each do |inventory_level|
        location = inventory_level['stock_location']
        shopify_location = shopify_locations.detect { |sl| sl['name'].downcase == location['name'].downcase }
        shopify_location ||= shopify_locations.first if only_one_location
        if shopify_location.nil?
          Rails.logger.info "Unable to find matching stock location for #{location['name']}"
          next
        end

        api_post(
          'inventory_levels/set.json',
          {
            location_id: shopify_location['id'],
            inventory_item_id: shopify_inventory_item_id,
            available: inventory_level['available']
          }
        )
        any_location_synced = true
      end

      raise "Inventory failed to push to Shopify due to a mismatch in stock location names." unless any_location_synced
    end

    def update_product(product = nil)
      if product.nil?
        product = Product.new
        product.add_wombat_obj @payload['product'], self
      end
      ## Using shopify_obj_no_variants is a workaround until
      ## specifying variants' Shopify IDs is added

      master_result = api_put(
        "products/#{product.shopify_id}.json",
        product.shopify_obj_no_variants
      )
      if product.variants.none? {|variant| !variant.is_master }
        set_inventory_levels(product.master, master_result.dig('product','variants').first['inventory_item_id'])
      end
      product.variants.each do |variant|
        if variant_id = (variant.shopify_id || find_variant_shopify_id(product.shopify_id, variant.sku))
          updated_shopify_variant = api_put(
            "variants/#{variant_id}.json",
            variant.shopify_obj
          )

          # equates to checking that the variant is an inventory type variant
          set_inventory_levels(variant, updated_shopify_variant.dig('variant','inventory_item_id'))
        else
          begin
            unless variant.is_master
              new_shopify_variant = api_post("products/#{product.shopify_id}/variants.json", variant.shopify_obj)
              set_inventory_levels(variant, new_shopify_variant.dig('variant','inventory_item_id'))
            end
          rescue RestClient::UnprocessableEntity
            # theres already a variant with same options, bail.
          end
        end
      end
      {
        'message' => "Product with Shopify ID of " +
                     "#{master_result['product']['id']} was updated."
      }
    end

    def add_customer
      customer = Customer.new
      customer.add_wombat_obj @payload['customer'], self
      result = api_post 'customers.json', customer.shopify_obj

      {
        'objects' => result,
        'message' => "Customer with Shopify ID of " +
                     "#{result['customer']['id']} was added."
      }
    end

    def update_customer
      customer = Customer.new
      customer.add_wombat_obj @payload['customer'], self

      begin
        result = api_put "customers/#{customer.shopify_id}.json",
                       customer.shopify_obj
      rescue RestClient::UnprocessableEntity => e
        # retries without addresses to avoid duplication bug
        customer_without_addresses = customer.shopify_obj
        customer_without_addresses["customer"].delete("addresses")

        result = api_put "customers/#{customer.shopify_id}.json", customer_without_addresses
      end

      {
        'message' => "Customer with Shopify ID of " +
                     "#{result['customer']['id']} was updated."
      }
    end

    def add_metafield obj_name, shopify_id, wombat_id
      api_obj_name = (obj_name == "inventory" ? "product" : obj_name)

      api_post "#{api_obj_name}s/#{shopify_id}/metafields.json",
               Metafield.new(@payload[obj_name]['id']).shopify_obj
    end

    def wombat_id_metafield obj_name, shopify_id
      wombat_id = nil

      api_obj_name = (obj_name == "inventory" ? "product" : obj_name)

      metafields_array = api_get "#{api_obj_name}s/#{shopify_id}/metafields"
      unless metafields_array.nil? || metafields_array['metafields'].nil?
        metafields_array['metafields'].each do |metafield|
          if metafield['key'] == 'wombat_id'
            wombat_id = metafield['value']
            break
          end
        end
      end

      wombat_id
    end

    def order(order_id)
      get_objs "orders/#{order_id}", Order
    end

    def transactions(order_id)
      get_objs "orders/#{order_id}/transactions", Transaction
    end

    def shipments(order_id)
      get_objs "orders/#{order_id}/fulfillments", Shipment
    end

    def refunds(order_id)
      get_objs "orders/#{order_id}/refunds", Refund
    end

    private

    def get_webhook_results obj_name, obj, get_objs = true
      objs = Util.wombat_array(get_objs ? get_objs(obj_name, obj) : obj)
      get_reply objs, "Successfully retrieved #{objs.length} #{obj_name} " +
                      "from Shopify."
    end

    def get_reply objs, message
      {
        'objects' => objs,
        'message' => message
      }
    end

    def get_objs objs_name, obj_class
      objs = Array.new
      shopify_objs = api_get objs_name
      if shopify_objs.values.first.kind_of?(Array)
        shopify_objs.values.first.each do |shopify_obj|
          obj = obj_class.new
          obj.add_shopify_obj shopify_obj, self
          objs << obj
        end
      else
        obj = obj_class.new
        obj.add_shopify_obj shopify_objs.values.first, self
        objs << obj
      end

      objs
    end

    def find_variant_shopify_id(product_shopify_id, variant_sku)
      variants = api_get("products/#{product_shopify_id}/variants")["variants"]

      if variant = variants.find {|v| v["sku"] == variant_sku}
        variant["id"]
      end
    end

    def product_shopify_id_from_shopify_response(products, name: nil, sku: nil)
      product_shopify_id = nil

      products.each do |product|
        if name.present? && product['title'] == name
          product_shopify_id = product['id'].to_s
          break
        else
          product['variants'].each do |variant|
            if variant['sku'] == sku
              product_shopify_id = variant['id'].to_s
              break
            end
          end
        end
      end

      product_shopify_id
    end

    def find_product_shopify_id_by_sku_or_name(sku, name)
      count = api_get('products/count')['count'].to_i
      page_size = 5
      total_pages = ([count, 1].max / page_size.to_f).ceil

      response = api_get_raw_response('products', limit: page_size)
      products = JSON.parse(response.body.force_encoding('utf-8'))['products']
      product_shopify_id = product_shopify_id_from_shopify_response(products, name: name, sku: sku)

      current_page = 1

      while product_shopify_id.nil? && response.headers.key?(:link) && current_page < total_pages do
        # links can include next and previous separated by a comma
        links = response.headers[:link].to_s.split(',').map(&:strip)
        # link: <https://....?page_info=xxxx>; rel=next
        next_link = links.detect { |link| link.to_s.split(';')[1].to_s.include?('next') }
        # break if there is no link or only a previous link
        break unless next_link
        # parse the next link string to get just the query string
        next_link_params = next_link.split(';')[0].strip.slice(1...-1).split('?')[1]

        response = api_get_raw_response('products', next_link_params)
        products = JSON.parse(response.body.force_encoding('utf-8'))['products']
        product_shopify_id = product_shopify_id_from_shopify_response(products, name: name, sku: sku)
        current_page += 1
      end

      product_shopify_id
    end

    def find_product_shopify_id_by_sku(sku)
      count = api_get('products/count')['count'].to_i
      page_size = 5
      total_pages = ([count, 1].max / page_size.to_f).ceil

      response = api_get_raw_response('products', limit: page_size)
      products = JSON.parse(response.body.force_encoding('utf-8'))['products']
      product_shopify_id = product_shopify_id_from_shopify_response(products, sku: sku)

      current_page = 1

      while product_shopify_id.nil? && response.headers.key?(:link) && current_page < total_pages do
        # links can include next and previous separated by a comma
        links = response.headers[:link].to_s.split(',').map(&:strip)
        # link: <https://....?page_info=xxxx>; rel=next
        next_link = links.detect { |link| link.to_s.split(';')[1].to_s.include?('next') }
        # break if there is no link or only a previous link
        break unless next_link
        # parse the next link string to get just the query string
        next_link_params = next_link.split(';')[0].strip.slice(1...-1).split('?')[1]

        response = api_get_raw_response('products', next_link_params)
        products = JSON.parse(response.body.force_encoding('utf-8'))['products']
        product_shopify_id = product_shopify_id_from_shopify_response(products, sku: sku)
        current_page += 1
      end

      product_shopify_id
    end
  end

  class AuthenticationError < StandardError; end
  class ShopifyError < StandardError; end
end
