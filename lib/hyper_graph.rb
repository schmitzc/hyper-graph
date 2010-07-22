require 'net/http'
require 'net/https'
require 'time'
require 'json'
require 'hyper_graph_object'

# Wrapper for errors generated by the Facebook Graph API server
class FacebookError<StandardError;end

# HyperGraph acts as a facade for the Facebook Graph API.
# It handles network calls and JSON response parsing.
class HyperGraph
  API_URL = 'graph.facebook.com'
  
  # Class methods
  class << self
    # Request an object from the social graph
    def get(requested_object_id, options = {})
      http = initialize_http_connection
      request_path = "/#{requested_object_id}"
      
      query = build_query(options)   
      request_path << "?#{URI.escape(query)}" unless query==""
      
      http_response = http.get(request_path)
      data = extract_data(JSON.parse(http_response.body))
      normalize_response(data)
    end
  
    # Post an object to the graph
    def post(requested_object_id, options = {})
      http = initialize_http_connection
      request_path = "/#{requested_object_id}"
      http_response = http.post(request_path, build_query(options))
      if http_response.body=='true'
        return true
      else
        data = extract_data(JSON.parse(http_response.body))
        return normalize_response(data)
      end
    end
    
    # Send a delete request to the graph
    def delete(requested_object_id, options = {})
       post(requested_object_id, options.merge(:method => 'delete'))
    end
    
    # Redirect users to this url to get authorization
    def authorize_url(client_id, redirect_uri, options={})
      "https://#{API_URL}/oauth/authorize?#{build_query(options.merge(:client_id => client_id, :redirect_uri => redirect_uri))}"
    end
    
    def get_access_token(client_id, client_secret, redirect_uri, code)
      http = initialize_http_connection
      request_path = "/oauth/access_token"
      request_path << "?#{build_query(:client_id => client_id, :client_secret => client_secret, :redirect_uri => redirect_uri, :code => code)}"
      http_response = http.get(request_path)
      http_response.body.split(/\=|&/)[1]
    end
    
    def search(query, options = {})
      get('search', options.merge(:q => query))
    end
    
    protected
    
    def build_query(options)
      options.to_a.collect{ |i| "#{i[0].to_s}=#{i[1]}" }.sort.join('&')
    end
    
    def normalize_response(response)
     normalized_response = {}      
      case response
      when Hash
        normalized_response = normalize_hash(response)
      when Array
        normalized_response = normalize_array(response)
      end
      normalized_response
    end
    
    private
    
    def initialize_http_connection
      http = Net::HTTP.new(API_URL, 443) 
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      http
    end
    
    # Converts JSON-parsed hash keys and values into a Ruby-friendly format
    # Convert :id into integer and :updated_time into Time and all keys into symbols
    def normalize_hash(hash)
      normalized_hash = {}
      hash.each do |k, v|
        case k 
        when "error"
          raise FacebookError.new("#{v['type']} - #{v['message']}")
        when "id"
          if (v == v.to_i.to_s)
            normalized_hash[k.to_sym] = v.to_i 
          else
            normalized_hash[k.to_sym] = v 
          end
        when /_time$/
          normalized_hash[k.to_sym] = Time.parse(v)
        else
          data = extract_data(v)
          case data
          when Hash
            normalized_hash[k.to_sym] = normalize_hash(data)
          when Array
            normalized_hash[k.to_sym] = normalize_array(data)
          else
            normalized_hash[k.to_sym] = data
          end
        end
      end
      normalized_hash
    end
    
    def normalize_array(array)
      array.collect{ |item| normalize_response(item) }
    end
    
    # Extracts data from "data" key in Hash, if present
    def extract_data(object)
      if object.is_a?(Hash)&&object.keys.include?('data')
        return object['data']
      else
        return object
      end
    end   
  end
  
  # Instance methods
  def initialize(access_token)
    @access_token = access_token
  end
  
  def object(id)
    HyperGraphObject.new(self, id)
  end
  
  def get(requested_object_id, options = {})
    self.class.get(requested_object_id, options.merge(:access_token => @access_token))
  end
  
  def post(requested_object_id, options = {})
    self.class.post(requested_object_id, options.merge(:access_token => @access_token))
  end

  def delete(requested_object_id, options = {})
    self.class.delete(requested_object_id, options.merge(:access_token => @access_token))
  end
  
  def search(query, options = {})
    self.class.get('search', options.merge(:access_token => @access_token, :q => query))
  end
end