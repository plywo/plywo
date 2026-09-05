require "digest"
require "open3"
require "socket"

module Plywo
  module Rails
    class HostClockDomain
      class << self
        def id
          @id ||= build_id
        end

        private

        def build_id
          marker = linux_boot_id || bsd_boot_time
          return if marker.nil? || marker.empty?

          Digest::SHA256.hexdigest("#{Socket.gethostname}\0#{marker}")
        end

        def linux_boot_id
          path = "/proc/sys/kernel/random/boot_id"
          return unless File.readable?(path)

          File.read(path).strip
        rescue SystemCallError
          nil
        end

        def bsd_boot_time
          stdout, status = Open3.capture2("sysctl", "-n", "kern.boottime")
          return unless status.success?

          value = stdout.strip
          value unless value.empty?
        rescue Errno::ENOENT
          nil
        end
      end
    end
  end
end
