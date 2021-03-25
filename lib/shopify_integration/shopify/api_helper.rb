require 'logger'

module ShopifyIntegration
  module Shopify
    module APIHelper
      SHOPIFY_API_VERSION = '2021-01'.freeze

      def api_get(resource, data = {})
        response = api_get_raw_response(resource, data)

        JSON.parse response.body.force_encoding("utf-8")
      end

      # Use for paginated requests or when you need information from the header
      def api_get_raw_response(resource, data = {})
        params = ''
        unless data.empty?
          params = '?'
          if data.is_a? Hash
            data.each do |key, value|
              params += '&' unless params == '?'
              params += "#{key}=#{value}"
            end
          else
            params += data
          end
        end

        response = RestClient.get(shopify_url + final_resource(resource) + params)
        log_data(shopify_url + final_resource(resource), data, response)

        response
      end

      def api_post(resource, data)
        response = RestClient.post(shopify_url + resource, data.to_json, content_type: :json, accept: :json)
        log_data(shopify_url + resource, data, response)

        JSON.parse response.force_encoding("utf-8")
      end

      def api_put(resource, data)
        response = RestClient.put(shopify_url + resource, data.to_json, content_type: :json, accept: :json)
        log_data(shopify_url + resource, data, response)

        JSON.parse response.force_encoding("utf-8")
      end

      def log_data(url, data, response)
        return unless ENV['SHOPIFY_LOG'] == true || ENV['SHOPIFY_LOG'] == 'true'
        logger.info "Shopify URL = #{url}" if url
        logger.info "Shopify Data = #{data}" if data
        logger.info "Shopify Response = #{response}" if response
      end

      def logger
        Logger.new(STDOUT)
      end


      def shopify_url
        "https://#{Util.shopify_apikey @config}:#{Util.shopify_password @config}" +
        "@#{Util.shopify_host @config}/admin/api/#{SHOPIFY_API_VERSION}/"
      end

      def final_resource(resource)
        if !@config['since'].nil?
          resource += ".json?status=any&updated_at_min=#{@config['since']}"
        elsif !@config['id'].nil?
          resource += "/#{@config['id']}.json"
        elsif !@config['email'].nil?
          resource += "/search.json?query=email:#{@config['email']}"
        else
          resource += '.json'
        end
        resource
      end
    end
  end
end
