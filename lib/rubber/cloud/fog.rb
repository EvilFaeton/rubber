require 'fog'
require 'rubber/cloud/fog_storage'

module Rubber
  module Cloud

    class Fog < Base

      attr_reader :compute_provider, :storage_provider

      def initialize(env, capistrano)
        super(env, capistrano)

        compute_credentials = Rubber::Util.symbolize_keys(env.compute_credentials)
        storage_credentials = Rubber::Util.symbolize_keys(env.storage_credentials) if env.storage_credentials

        @compute_provider = ::Fog::Compute.new(compute_credentials)
        @storage_provider = storage_credentials ? ::Fog::Storage.new(storage_credentials) : nil
      end

      def storage(bucket)
        return Rubber::Cloud::FogStorage.new(@storage_provider, bucket)
      end

      def table_store(table_key)
        raise NotImplementedError, "No table store available for generic fog adapter"
      end

      def create_instance(instance_alias, ami, ami_type, security_groups, availability_zone, region, ebs_optimized)
        response = @compute_provider.servers.create(:image_id => ami,
                                                    :flavor_id => ami_type,
                                                    :groups => security_groups,
                                                    :availability_zone => availability_zone,
                                                    :key_name => env.key_name,
                                                    :ebs_optimized => ebs_optimized)
        instance_id = response.id
        return instance_id
      end

      def create_spot_instance_request(spot_price, ami, ami_type, security_groups, availability_zone)
        response = @compute_provider.spot_requests.create(:price => spot_price,
                                                          :image_id => ami,
                                                          :flavor_id => ami_type,
                                                          :groups => security_groups,
                                                          :availability_zone => availability_zone,
                                                          :key_name => env.key_name)
        request_id = response.id
        return request_id
      end

      def describe_instances(instance_id=nil)
        instances = []
        opts = {}
        opts["instance-id"] = instance_id if instance_id

        response = @compute_provider.servers.all(opts)
        response.each do |item|
          instance = {}
          instance[:id] = item.id
          instance[:type] = item.flavor_id
          instance[:external_host] = item.dns_name
          instance[:external_ip] = item.public_ip_address
          instance[:internal_host] = item.private_dns_name
          instance[:internal_ip] = item.private_ip_address
          instance[:state] = item.state
          instance[:zone] = item.availability_zone
          instance[:platform] = item.platform || 'linux'
          instance[:root_device_type] = item.root_device_type
          instances << instance
        end

        return instances
      end

      def destroy_instance(instance_id)
        response = @compute_provider.servers.get(instance_id).destroy()
      end

      def destroy_spot_instance_request(request_id)
        @compute_provider.spot_requests.get(request_id).destroy
      end

      def reboot_instance(instance_id)
        response = @compute_provider.servers.get(instance_id).reboot()
      end

      def stop_instance(instance, force=false)
        # Don't force the stop process. I.e., allow the instance to flush its file system operations.
        response = @compute_provider.servers.get(instance.instance_id).stop(force)
      end

      def start_instance(instance)
        response = @compute_provider.servers.get(instance.instance_id).start()
      end

      def create_static_ip
        address = @compute_provider.addresses.create()
        return address.public_ip
      end

      def attach_static_ip(ip, instance_id)
        address = @compute_provider.addresses.get(ip)
        server = @compute_provider.servers.get(instance_id)
        response = (address.server = server)
        return ! response.nil?
      end

      def detach_static_ip(ip)
        address = @compute_provider.addresses.get(ip)
        response = (address.server = nil)
        return ! response.nil?
      end

      def describe_static_ips(ip=nil)
        ips = []
        opts = {}
        opts["public-ip"] = ip if ip
        response = @compute_provider.addresses.all(opts)
        response.each do |item|
          ip = {}
          ip[:instance_id] = item.server_id
          ip[:ip] = item.public_ip
          ips << ip
        end
        return ips
      end

      def destroy_static_ip(ip)
        address = @compute_provider.addresses.get(ip)
        return address.destroy
      end

      def create_volume(size, zone, volume_type, iops)
        volume = @compute_provider.volumes.create(:size => size.to_s,   :availability_zone => zone,
                                                  :type => volume_type, :iops => iops)
        return volume.id
      end

      def attach_volume(volume_id, instance_id, device)
        volume = @compute_provider.volumes.get(volume_id)
        server = @compute_provider.servers.get(instance_id)
        volume.device = device
        volume.server = server
      end

      def detach_volume(volume_id, force=true)
        volume = @compute_provider.volumes.get(volume_id)
        force ? volume.force_detach : (volume.server = nil)
      end

      def describe_volumes(volume_id=nil)
        volumes = []
        opts = {}
        opts[:'volume-id'] = volume_id if volume_id
        response = @compute_provider.volumes.all(opts)
        response.each do |item|
          volume = {}
          volume[:id] = item.id
          volume[:status] = item.state
          if item.server_id
            volume[:attachment_instance_id] = item.server_id
            volume[:attachment_status] = item.attached_at ? "attached" : "waiting"
          end
          volumes << volume
        end
        return volumes
      end

      def destroy_volume(volume_id)
        @compute_provider.volumes.get(volume_id).destroy
      end

      def create_image(image_name)
        raise NotImplementedError, "create_image not implemented in generic fog adapter"
      end

      def describe_images(image_id=nil)
        images = []
        opts = {"Owner" => "self"}
        opts["image-id"] = image_id if image_id
        response = @compute_provider.images.all(opts)
        response.each do |item|
          image = {}
          image[:id] = item.id
          image[:location] = item.location
          image[:root_device_type] = item.root_device_type
          images << image
        end
        return images
      end

      def destroy_image(image_id)
        raise NotImplementedError, "destroy_image not implemented in generic fog adapter"
      end

      def describe_load_balancers(name=nil)
        raise NotImplementedError, "describe_load_balancers not implemented in generic fog adapter"
      end
    end

  end
end
