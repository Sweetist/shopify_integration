$LOAD_PATH.unshift ::File.expand_path(::File.dirname(__FILE__) + '/lib')
require 'shopify_integration'

run ShopifyIntegration::Server
