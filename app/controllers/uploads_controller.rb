# https://github.com/FineUploader/php-s3-server/blob/master/endpoint-cors.php
class UploadsController < ApplicationController
  skip_before_action :verify_authenticity_token

  def new
  end

  # http://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-UsingHTTPPOST.html
  def sign
    json_request = JSON.parse(request.raw_post)

    response_data = if json_request['headers']
      headers = json_request['headers'].split("\n")
      credential_scope_index = headers.index { |s| s.match /^\d{8}\/.+\/s3\/aws4_request$/ }
      canonical_headers = headers.slice(credential_scope_index+1..-1)
      canonical_headers_digest = hexdigest(canonical_headers.join("\n"))
      string_to_sign = (headers.slice(0..credential_scope_index) + [canonical_headers_digest]).join("\n")
      { 'signature' => signature(string_to_sign, json_request) }
    else
      encoded_policy = Base64.encode64(request.raw_post).gsub("\n", '')
      { 'signature' => signature(encoded_policy, json_request), 'policy' => encoded_policy }
    end

    render json: response_data
  end

  def create
    upload = Upload.new(
      object_key: params['key'],
      uuid: params['uuid'],
      name: params['name'] # original filename
    )
    if upload.save
      render json: { 'tempLink' => upload.url }
    else
      render json: { 'error' => upload.errors.messages.first.flatten.join(' '), 'preventRetry' => true }, status: :unprocessable_entity
    end
  end

  def destroy
    upload = Upload.find_by_uuid(params['uuid'])
    if upload.destroy
      render json: {}, state: :ok
    else
      render json: {}, state: :unprocessable_entity
    end
  end

  private

  # VERSION 4
  # Extracted from lib/aws-sdk-core/signers/v4.rb
  # http://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-query-string-auth.html

  def hexdigest(value)
    Aws::Checksums.sha256_hexdigest(value)
  end

  def hmac(key, value)
    OpenSSL::HMAC.digest(OpenSSL::Digest.new('sha256'), key, value)
  end

  def hexhmac(key, value)
    OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), key, value)
  end

  def date_and_region(json_request)
    if json_request['headers'] # multipart
      header = json_request['headers'].split("\n").select { |s| s.match /^\d{8}\/[\w\-]+\/s3\/aws4_request$/ }.first
      header.split('/').slice(0..1)
    else
      credential_scope = json_request['conditions'].select { |h| h.is_a?(Hash) && h.keys.first == 'x-amz-credential' }.first.values.first
      credential_scope.split('/').slice(1..2)
    end
  end

  def signature(payload, json_request)
    date, region = date_and_region(json_request)
    k_date = hmac("AWS4#{ENV.fetch('AWS_SECRET_ACCESS_KEY')}", date)
    k_region = hmac(k_date, region)
    k_service = hmac(k_region, 's3')
    k_credentials = hmac(k_service, 'aws4_request')
    hexhmac(k_credentials, payload)
  end
end
