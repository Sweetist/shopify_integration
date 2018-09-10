require 'shopify_integration/shopify/api_helper'
require 'shopify_integration/shopify/shipment'
require 'shopify_integration/shopify_api'
require 'shopify_integration/variant'
require 'shopify_integration/version'
require 'shopify_integration/util'
require 'shopify_integration/transaction'
require 'shopify_integration/shipment'
require 'shopify_integration/product'
require 'shopify_integration/payment'
require 'shopify_integration/refund'
require 'shopify_integration/order'
require 'shopify_integration/option'
require 'shopify_integration/metafield'
require 'shopify_integration/line_item'
require 'shopify_integration/inventory'
require 'shopify_integration/image'
require 'shopify_integration/customer'
require 'shopify_integration/address'

require 'sinatra'
require 'i18n'
require 'i18n/backend/fallbacks'

require 'endpoint_base'
require 'httparty'

I18n::Backend::Simple.send(:include, I18n::Backend::Fallbacks)
I18n.load_path += Dir[File.join(File.dirname(__FILE__), 'locales', '*.yml').to_s]
I18n.backend.load_translations

module ShopifyIntegration
  class Server < EndpointBase::Sinatra::Base
    SYNC_TYPE = 'shopify'.freeze

    post '/cancel_order' do
      begin
        api = ShopifyAPI.new(@payload, @config)
        response = api.cancel_order

        add_logs_object(message: "Order #{response['order']['name']} cancelled")
        add_integration_params
        result 200, 'Order cancelled'
      rescue => e
        logger.error e.backtrace.join("\n")
        result 500, response_for_error(e)
      end
    end

    # /add_shipment or /update_shipment
    post '/*\_shipment' do |_action|
      begin
        summary = Shopify::Shipment.new(@payload['order']['shipments'].first, @config).ship!

        add_logs_object(message: summary)
        add_integration_params
        result 200, summary
      rescue => e
        logger.error e.cause
        logger.error e.backtrace.join("\n")
        result 500, response_for_error(e)
      end
    end

    ## Supported callbacks:
    ## order, product, customer _callback
    post '/*\_callback' do |obj_name|
      callback_handle obj_name
    end

    ## Supported endpoints:
    ## get_ for orders, products, inventories, shipments, customers
    ## add_ for product, customer
    ## update_ for product, customer
    ## set_inventory
    post '/*\_*' do |action, obj_name|
      # binding.pry
      return not_support_response if action == 'update' && obj_name == 'orders'

      shopify_action "#{action}_#{obj_name}", obj_name.singularize
    end

    private

    def callback_handle(obj_name)
      @config = { 'shopify_host' => request.env['HTTP_X_SHOPIFY_SHOP_DOMAIN'],
                  'status' => request.env['HTTP_X_SHOPIFY_TOPIC'] }
      api = ShopifyAPI.new(@payload, @config)
      api.log_data(@config['shopify_host'], "Callback with #{obj_name} from shopify", @payload)
      obj = "ShopifyIntegration::#{obj_name.capitalize}".safe_constantize.new
      obj.add_shopify_obj @payload, api
      add_object obj_name, obj.wombat_obj
      if obj_name == 'product' && obj.variants.any?
        obj.variants.each do |variant|
          next if variant.sku.blank?
          inventory = Inventory.new
          inventory.add_obj variant
          add_object :inventory, inventory.wombat_obj
        end
      end
      add_integration_params
      push(@objects.merge('parameters' => @parameters).to_json)

      result 200, 'Callback from Shopify'
    rescue => e
      logger.error e.cause
      logger.error e.backtrace.join("\n")
      result 500, response_for_error(e)
    end

    def shopify_action(action, obj_name)
      begin
        action_type = action.split('_')[0]
        ## Add and update shouldn't come with a shopify_id, therefore when
        ## they do, it indicates Wombat resending an object.
        if wombat_resend_add?(action_type, obj_name) ||
           update_without_shopify_id?(action_type, obj_name)

          return result 200
        end

        shopify = ShopifyAPI.new(@payload, @config)
        response = shopify.send(action)

        case action_type
        when 'get'
          response['objects'].each do |obj|
            ## Check if object has a metafield with a Wombat ID in it,
            ## if so change object ID to that prior to adding to Wombat
            # wombat_id = shopify.wombat_id_metafield obj_name, obj['shopify_id']

            # obj['id'] = wombat_id if wombat_id

            ## Add object to Wombat
            add_object obj_name, obj
          end

        when 'add'

          ## This will do a partial update in Wombat, only the new key
          ## shopify_id will be added, everything else will be the same
          # add_object obj_name,
          #            { 'id' => @payload[obj_name]['id'],
          #              'shopify_id' => response['objects'][obj_name]['id'].to_s }

          ## Add metafield to track Wombat ID
          # shopify.add_metafield obj_name,
          #                       response['objects'][obj_name]['id'].to_s,
          #                       @payload[obj_name]['id']
        end

        if response.has_key?('additional_objs') &&
           response.has_key?('additional_objs_name')
          response['additional_objs'].each do |obj|
            add_object response['additional_objs_name'], obj
          end
        end

        # avoids "Successfully retrieved 0 customers from Shopify."
        add_logs_object(message: response['message']) if sync_action
        add_integration_params

        if skip_summary?(response, action_type)
          return result 200
        else
          return result 200, response['message']
        end
      rescue => e
        print e.cause
        print e.backtrace.join("\n")
        result 500, response_for_error(e)
      end
    end

    def response_for_error(error)
      {
        message: error.message,
        backtrace: error.backtrace
      }
    end

    def wombat_resend_add?(action_type, obj_name)
      action_type == 'add' && !@payload[obj_name]['shopify_id'].nil?
    end

    def update_without_shopify_id?(action_type, obj_name)
      action_type == 'update'                            \
        && @payload[obj_name]['shopify_id'].nil?         \
        && @config['sync_id'].nil?                       \
        && obj_name != 'shipment'
    end

    def skip_summary?(response, action_type)
      response['message'].nil? || get_without_objects?(response, action_type)
    end

    def get_without_objects?(response, action_type)
      action_type == 'get' && response['objects'].to_a.size == 0
    end

    def validate(res)
      return if res.code == 202
      raise PushApiError,
        "Push not successful. Returned response code #{res.code} and message: #{res.body}"
    end

    def push(json_payload)
      res = HTTParty.post(
        ENV['CANGAROO_ENDPOINT'],
        body: json_payload,
        headers: {
          'Content-Type'       => 'application/json',
          'X-Hub-Store'        => ENV['CANGAROO_SECRET_KEY'],
          'X-Hub-Access-Token' => ENV['CANGAROO_SECRET_TOKEN'],
          'X-Hub-Timestamp'    => Time.now.utc.to_i.to_s
        }
      )

      validate(res)
    end

    def not_support_response
      add_logs_object(message: I18n.t('not_support'),
                      status: 3)
      add_integration_params
      result 200, 'Not support response'
    end

    def add_logs_object(message:, type: 'orders', level: 'done', id: 'none', status: nil)
      add_object :log, id: id,
                       level: level,
                       message: message,
                       type: type,
                       status: status
    end

    def add_integration_params
      add_parameter 'sync_action', sync_action
      add_parameter 'sync_type', SYNC_TYPE
      add_parameter 'vendor', vendor
    end

    def sync_action
      @config['sync_action']
    end

    def vendor
      @config['vendor']
    end
  end

  class PushApiError < StandardError; end
end
