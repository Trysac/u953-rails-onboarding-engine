# frozen_string_literal: true

require "json"
require "openssl"

module Trysac
  module RailsOnboardingEngine
    # Encodes and verifies HMAC-SHA256 signed, expiring resume tokens.
    module TokenCodec
      # Minimum allowed secret byte size.
      MIN_SECRET_BYTES = 32

      # Maximum token length accepted for verification.
      MAX_TOKEN_LENGTH = 2048

      # Validates that the signing secret meets the minimum length requirement.
      #
      # @param secret [String] HMAC secret
      # @return [String] frozen secret string
      # @raise [Error] with code :invalid_flow if secret is nil or shorter than 32 bytes
      def self.validate_secret!(secret)
        if !secret.is_a?(String) || secret.bytesize < MIN_SECRET_BYTES
          raise Error.new(:invalid_flow, "Secret must be a String of at least #{MIN_SECRET_BYTES} bytes")
        end

        secret.dup.freeze
      end

      # Generates a signed resume token for a Progress instance.
      # Payload carries only flow name, progress id, version, and expiry epoch seconds.
      #
      # @param progress [Progress] progress instance
      # @param secret [String] HMAC secret (>= 32 bytes)
      # @param expires_at [Integer] expiration epoch timestamp in seconds
      # @return [String] base64url(payload).base64url(hmac)
      def self.encode(progress:, secret:, expires_at:)
        payload_hash = {
          "f" => progress.flow_name,
          "p" => progress.id,
          "v" => progress.version,
          "e" => expires_at.to_i
        }
        payload_b64 = urlsafe_encode(JSON.generate(payload_hash))
        sig_b64 = sign_part(secret, payload_b64)
        "#{payload_b64}.#{sig_b64}"
      end

      # Verifies a resume token using constant-time comparison before parsing the JSON payload.
      #
      # @param token [String] signed resume token
      # @param secret [String] HMAC secret
      # @param expected_flow [String] expected flow name
      # @param now_epoch [Integer] current epoch timestamp in seconds
      # @return [Hash{String => Object}] verified token claims ("f", "p", "v", "e")
      # @raise [Error] with code :invalid_token or :token_expired
      def self.decode_and_verify(token:, secret:, expected_flow:, now_epoch:)
        payload_b64, provided_sig = split_token!(token)
        unless secure_compare(sign_part(secret, payload_b64), provided_sig)
          raise Error.new(:invalid_token, "Token signature verification failed")
        end

        claims = parse_claims(payload_b64)
        raise Error.new(:invalid_token, "Token flow mismatch") unless claims["f"] == expected_flow
        raise Error.new(:token_expired, "Resume token has expired") if now_epoch > claims["e"].to_i

        claims
      end

      # Splits a token into its payload and signature segments after checking its type, size and shape.
      #
      # @param token [Object] untrusted token
      # @return [Array(String, String)] payload and signature segments
      # @raise [Error] with code :invalid_token when the token is malformed
      def self.split_token!(token)
        raise Error.new(:invalid_token, "Token must be a non-empty String") unless token.is_a?(String) && !token.empty?
        raise Error.new(:invalid_token, "Token exceeds maximum length") if token.bytesize > MAX_TOKEN_LENGTH

        token_segments!(token)
      end

      # Splits a token on "." and checks it has exactly two non-empty segments.
      #
      # @param token [String] token string
      # @return [Array(String, String)] payload and signature segments
      # @raise [Error] with code :invalid_token when the structure is wrong
      def self.token_segments!(token)
        parts = token.split(".", -1)
        raise Error.new(:invalid_token, "Malformed token structure") unless parts.length == 2
        raise Error.new(:invalid_token, "Empty token segment") if parts.any?(&:empty?)

        parts
      end

      # Computes the base64url HMAC-SHA256 signature for a payload segment.
      #
      # @param secret [String] HMAC secret
      # @param payload_b64 [String] base64url encoded payload
      # @return [String] base64url encoded signature without padding
      def self.sign_part(secret, payload_b64)
        digest = OpenSSL::HMAC.digest("SHA256", secret, payload_b64)
        urlsafe_encode(digest)
      end

      # Performs constant-time signature comparison.
      #
      # @param expected [String] expected signature
      # @param actual [String] provided signature
      # @return [Boolean]
      def self.secure_compare(expected, actual)
        return false unless expected.bytesize == actual.bytesize

        OpenSSL.fixed_length_secure_compare(expected, actual)
      end

      # Decodes and parses the base64url JSON claims.
      #
      # @param payload_b64 [String] base64url string
      # @return [Hash{String => Object}]
      def self.parse_claims(payload_b64)
        json_str = urlsafe_decode(payload_b64)
        claims = JSON.parse(json_str)
        valid_claims = claims.is_a?(Hash) &&
                       claims["f"].is_a?(String) &&
                       claims["p"].is_a?(String) &&
                       claims["e"].is_a?(Integer)
        raise Error.new(:invalid_token, "Invalid token claims") unless valid_claims

        claims
      rescue ArgumentError, JSON::ParserError
        raise Error.new(:invalid_token, "Invalid token encoding")
      end

      # Encodes bytes as unpadded base64url (RFC 4648 section 5).
      #
      # @param bytes [String] raw bytes
      # @return [String] base64url text without "=" padding
      def self.urlsafe_encode(bytes)
        [bytes].pack("m0").tr("+/", "-_").delete("=")
      end

      # Decodes base64url text, with or without "=" padding, as the base64 gem's urlsafe_decode64 does.
      #
      # @param text [String] base64url text
      # @return [String] raw bytes
      # @raise [ArgumentError] when the text is not valid base64
      def self.urlsafe_decode(text)
        padded = !text.end_with?("=") && (text.length % 4).nonzero? ? text.ljust((text.length + 3) & ~3, "=") : text
        padded.tr("-_", "+/").unpack1("m0")
      end

      private_class_method :sign_part, :secure_compare, :parse_claims, :split_token!, :token_segments!,
                           :urlsafe_encode, :urlsafe_decode
    end
  end
end
