module Technoweenie # :nodoc:
  module AttachmentFu # :nodoc:
    module Backends
      # = AWS::S3 v1 Storage Backend
      # see compatible docs in Technoweenie::AttachmentFu::Backends::S3v1Backend

      module S3v1Backend
        class RequiredLibraryNotFoundError < StandardError; end
        class ConfigFileNotFoundError < StandardError; end

        def self.included(base) #:nodoc:
          mattr_reader :bucket_name, :s3_config, :s3_conn

          begin
            require 'aws-sdk-s3'
          rescue LoadError
            raise RequiredLibraryNotFoundError.new('AWS::S3 could not be loaded')
          end

          begin
            @@s3_config_path = base.attachment_options[:s3_config_path] || (Rails.root.join('config/s3_images.yml'))
            @@s3_config = YAML.load(ERB.new(File.read(@@s3_config_path)).result)[Rails.env].symbolize_keys
          end

          bucket_key = base.attachment_options[:bucket_key]

          if bucket_key and s3_config[bucket_key.to_sym]
            eval_string = "def bucket_name()\n  \"#{s3_config[bucket_key.to_sym]}\"\nend"
          else
            eval_string = "def bucket_name()\n  \"#{s3_config[:bucket_name]}\"\nend"
          end
          base.class_eval(eval_string, __FILE__, __LINE__)

          @@s3_conn = Aws::S3::Client.new(s3_config.slice(:access_key_id, :secret_access_key, :server, :port, :use_ssl, :persistent, :proxy, :region))

          base.before_update :rename_file
        end

        def self.protocol
          @protocol ||= s3_config[:use_ssl] ? 'https://' : 'http://'
        end

        def self.hostname
          @hostname ||= s3_config[:server] || 's3.amazonaws.com'
        end

        def self.port_string
          @port_string ||= (s3_config[:port].nil? || s3_config[:port] == (s3_config[:use_ssl] ? 443 : 80)) ? '' : ":#{s3_config[:port]}"
        end

        def self.distribution_domain
          @distribution_domain = s3_config[:distribution_domain]
        end

        module ClassMethods
          def s3_protocol
            Technoweenie::AttachmentFu::Backends::S3v1Backend.protocol
          end

          def s3_hostname
            Technoweenie::AttachmentFu::Backends::S3v1Backend.hostname
          end

          def s3_port_string
            Technoweenie::AttachmentFu::Backends::S3v1Backend.port_string
          end

          def cloudfront_distribution_domain
            Technoweenie::AttachmentFu::Backends::S3v1Backend.distribution_domain
          end
        end

        # see compatible docs in Technoweenie::AttachmentFu::Backends::S3v1Backend
        def filename=(value)
          @old_filename = filename unless filename.nil? || @old_filename
          write_attribute :filename, sanitize_filename(value)
        end

        # see compatible docs in Technoweenie::AttachmentFu::Backends::S3v1Backend
        def attachment_path_id
          path_id = ((respond_to?(:parent_id) && parent_id) || id).to_s
          ("%08d" % path_id).scan(/..../)
        end

        # see compatible docs in Technoweenie::AttachmentFu::Backends::S3v1Backend
        def base_path
          File.join(attachment_options[:path_prefix], attachment_path_id)
        end

        # see compatible docs in Technoweenie::AttachmentFu::Backends::S3v1Backend
        def full_filename(thumbnail = nil)
          File.join(base_path, thumbnail_name_for(thumbnail))
        end

        # see compatible docs in Technoweenie::AttachmentFu::Backends::S3v1Backend
        def s3_url(thumbnail = nil)
          File.join(s3_protocol + "#{bucket_name}.#{s3_hostname}" + s3_port_string, full_filename(thumbnail))
        end

        # see compatible docs in Technoweenie::AttachmentFu::Backends::S3v1Backend
        def cloudfront_url(thumbnail = nil)
          "http://" + cloudfront_distribution_domain + "/" + full_filename(thumbnail)
        end

        def public_filename(*args)

          if args.empty?
            clean_args = nil
          else
            clean_args = args.join
          end

          if attachment_options[:cloudfront]
            cloudfront_url(clean_args)
          else
            s3_url(clean_args)
          end
        end

        # see compatible docs in Technoweenie::AttachmentFu::Backends::S3v1Backend
        def authenticated_s3_url(*args)
          options   = args.extract_options!
          options[:expires_in] = options[:expires_in].to_i if options[:expires_in]
          thumbnail = args.shift
          s3_conn.buckets[bucket_name].objects[full_filename(thumbnail)].url_for(options)
        end

        def create_temp_file
          write_to_temp_file current_data
        end

        def current_data
          s3_conn.buckets[bucket_name].objects[full_filename].read
        end

        def s3_protocol
          Technoweenie::AttachmentFu::Backends::S3v1Backend.protocol
        end

        def s3_hostname
          Technoweenie::AttachmentFu::Backends::S3v1Backend.hostname
        end

        def s3_port_string
          Technoweenie::AttachmentFu::Backends::S3v1Backend.port_string
        end

        def cloudfront_distribution_domain
          Technoweenie::AttachmentFu::Backends::S3v1Backend.distribution_domain
        end

        protected
          # Called in the after_destroy callback
          def destroy_file
            s3_conn.buckets[bucket_name].objects[full_filename].delete
          end

          def rename_file
            return unless @old_filename && @old_filename != filename

            old_full_filename = File.join(base_path, @old_filename)

            s3_conn.buckets[bucket_name].objects[old_full_filename].move_to(full_filename, :acl => attachment_options[:s3_access])

            @old_filename = nil
            true
          end

          def save_to_storage
            if save_attachment?
              ff = full_filename.gsub(/^\/+/, '')
              s3_conn.buckets[bucket_name].objects[ff].write(
                (temp_path ? File.open(temp_path) : temp_data),
                :content_type => content_type,
                :acl => attachment_options[:s3_access]
              )
            end

            @old_filename = nil
            true
          end
      end
    end
  end
end
