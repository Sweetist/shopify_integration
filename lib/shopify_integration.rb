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
require 'shopify_integration/order'
require 'shopify_integration/option'
require 'shopify_integration/metafield'
require 'shopify_integration/line_item'
require 'shopify_integration/inventory'
require 'shopify_integration/image'
require 'shopify_integration/customer'
require 'shopify_integration/address'


require 'sinatra'
require 'endpoint_base'
require 'httparty'

module ShopifyIntegration
  class Server < EndpointBase::Sinatra::Base
    get '/test_endpoint' do
      binding.pry
      result 200, { result: 'ok' }
    end

    post '/products/create' do
      # logger.info "Config=#{@config}"
      # logger.info "Payload=#{@payload}"
      begin
        push(@payload.to_json)

        result 200, 'Callback from shipping easy'
      rescue => e
        logger.error e.cause
        logger.error e.backtrace.join("\n")
        result 500, e.message
      end
    end

    # /add_shipment or /update_shipment
    post '/*\_shipment' do |_action|
      summary = Shopify::Shipment.new(@payload['shipment'], @config).ship!

      result 200, summary
    end

    ## Make same bellow rquest but with wombat push
    post '/*\_*\_wombat' do |action, obj_name|
      shopify_action "#{action}_#{obj_name}", obj_name.singularize, true
    end

    ## Supported endpoints:
    ## get_ for orders, products, inventories, shipments, customers
    ## add_ for product, customer
    ## update_ for product, customer
    ## set_inventory
    post '/*\_*' do |action, obj_name|
      shopify_action "#{action}_#{obj_name}", obj_name.singularize
    end


    private

      def shopify_action(action, obj_name, womat_push = false)
          #begin

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
              wombat_id = shopify.wombat_id_metafield obj_name, obj['shopify_id']
              unless wombat_id.nil?
                obj['id'] = wombat_id
              end

              ## Add object to Wombat
              add_object obj_name, obj
            end

            push(@objects.to_json) if womat_push

            add_parameter 'since', Time.now.utc.iso8601


          when 'add'
            ## This will do a partial update in Wombat, only the new key
            ## shopify_id will be added, everything else will be the same
            add_object obj_name,
                       { 'id' => @payload[obj_name]['id'],
                         'shopify_id' => response['objects'][obj_name]['id'].to_s }

            ## Add metafield to track Wombat ID
            shopify.add_metafield obj_name,
                                  response['objects'][obj_name]['id'].to_s,
                                  @payload[obj_name]['id']
          end

          if response.has_key?('additional_objs') &&
             response.has_key?('additional_objs_name')
            response['additional_objs'].each do |obj|
              add_object response['additional_objs_name'], obj
            end
          end

          # avoids "Successfully retrieved 0 customers from Shopify."
          if skip_summary?(response, action_type)
            return result 200
          else
            return result 200, response['message']
          end
        # rescue => e
        #   print e.cause
        #   print e.backtrace.join("\n")
        #   result 500, (e.try(:response) ? e.response : e.message)
        # end
      end

      def wombat_resend_add?(action_type, obj_name)
        action_type == 'add' && !@payload[obj_name]['shopify_id'].nil?
      end

      def update_without_shopify_id?(action_type, obj_name)
        action_type == 'update' && @payload[obj_name]['shopify_id'].nil? && obj_name != "shipment"
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

      def add_logs_object(id:, message:, level: 'done', type: 'orders')
        add_object :log, id: id,
                         sync_type: SYNC_TYPE,
                         level: level,
                         message: message,
                         type: type
      end
  end

  class PushApiError < StandardError; end
end