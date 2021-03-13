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
      else
        result = api_post 'products.json', product.shopify_obj_no_variants
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
        update_inventory_levels(variant, updated_shopify_variant.dig('variant','inventory_item_id')) if variant.inventory_management
      else
        raise "No variants with SKU: #{variant.sku}"
      end
    end

    def update_inventory_levels(variant, shopify_inventory_item_id)
      shopify_inventory_levels = api_get('inventory_levels', {inventory_item_ids: shopify_inventory_item_id})['inventory_levels']
      shopify_locations = api_get('locations')['locations']
      variant.shopify_inventory_levels.each do |inventory_level|
        location = inventory_level['stock_location']
        shopify_location = shopify_locations.detect { |sl| sl['name'].downcase == location['name'].downcase }
        next if shopify_location.nil?

        api_post(
          'inventory_levels/set.json',
          {
            location_id: shopify_location['id'],
            inventory_item_id: shopify_inventory_item_id,
            available: inventory_level['available']
          }
        )
      end
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
      product.variants.each do |variant|
        if variant_id = (variant.shopify_id || find_variant_shopify_id(product.shopify_id, variant.sku))
          updated_shopify_variant = api_put(
            "variants/#{variant_id}.json",
            variant.shopify_obj
          )

          # equates to checking that the variant is an inventory type variant
          update_inventory_levels(variant, updated_shopify_variant.dig('variant','inventory_item_id')) if variant.inventory_management
        else
          begin
            api_post("products/#{product.shopify_id}/variants.json", variant.shopify_obj) if variant.is_master == false
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

    def set_inventory
      inventory = Inventory.new
      inventory.add_wombat_obj @payload['inventory']
      puts "INV: " + @payload['inventory'].to_json
      shopify_id = inventory.shopify_id.blank? ?
                      find_product_shopify_id_by_sku(inventory.sku) : inventory.shopify_id

      message = 'Could not find item with SKU of ' + inventory.sku
      unless shopify_id.blank?
        result = api_put "variants/#{shopify_id}.json",
                         {'variant' => inventory.shopify_obj}
        message = "Set inventory of SKU #{inventory.sku} " +
                  "to #{inventory.quantity}."
      end
      {
        'message' => message
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

    def find_product_shopify_id_by_sku_or_name(sku, name)
      count = (api_get 'products/count')['count']
      page_size = 250
      pages = (count / page_size.to_f).ceil
      current_page = 1

      while current_page <= pages
        products = api_get('products',
                           'limit' => page_size,
                           'page' => current_page)
        current_page += 1
        products['products'].each do |product|
          return product['id'].to_s if product['title'] == name
          product['variants'].each do |variant|
            return variant['id'].to_s if variant['sku'] == sku
          end
        end
      end

      nil
    end

    def find_product_shopify_id_by_sku sku
      count = (api_get 'products/count')['count']
      page_size = 250
      pages = (count / page_size.to_f).ceil
      current_page = 1

      while current_page <= pages do
        products = api_get 'products',
                           {'limit' => page_size, 'page' => current_page}
        current_page += 1
        products['products'].each do |product|
          product['variants'].each do |variant|
            return variant['id'].to_s if variant['sku'] == sku
          end
        end
      end

      return nil
    end
  end

  class AuthenticationError < StandardError; end
  class ShopifyError < StandardError; end
end
