# https://system.netsuite.com/help/helpcenter/en_US/Output/Help/SuiteCloudCustomizationScriptingWebServices/SuiteTalkWebServices/upsertList.html
module NetSuite
  module Actions
    class UpsertList
      include Support::Requests

      def initialize(*objects)
        @objects = objects
      end

      private

      def request(credentials={})
        NetSuite::Configuration.connection(
          { element_form_default: :unqualified }, credentials
        ).call(:upsert_list, message: request_body)
      end

      # <soap:Body>
      #   <upsertList>
      #     <record xsi:type="listRel:Customer" externalId="ext1">
      #       <listRel:entityId>Shutter Fly</listRel:entityId>
      #       <listRel:companyName>Shutter Fly, Inc</listRel:companyName>
      #     </record>
      #     <record xsi:type="listRel:Customer" externalId="ext2">
      #       <listRel:entityId>Target</listRel:entityId>
      #       <listRel:companyName>Target</listRel:companyName>
      #     </record>
      #   </upsertList>
      # </soap:Body>
      def request_body
        attrs = @objects.map do |o|
          hash = o.to_record.merge({
            '@xsi:type' => o.record_type
          })

          if o.respond_to?(:external_id) && o.external_id
            hash['@externalId'] = o.external_id
          end

          hash
        end

        { 'record' => attrs }
      end

      def response_hash
        @response_hash ||= Array[@response.body[:upsert_list_response][:write_response_list][:write_response]].flatten
      end

      def response_body
        @response_body ||= response_hash.map { |h| h[:base_ref] }
      end

      def response_errors
        if response_hash.any? { |h| h[:status] && h[:status][:status_detail] }
          @response_errors ||= errors
        end
      end

      def errors
        errors = response_hash.select { |h| h[:status] && h[:status][:status_detail] }.map do |obj|
          error_obj = obj[:status][:status_detail]
          error_obj = [error_obj] if error_obj.class == Hash
          errors = error_obj.map do |error|
            NetSuite::Error.new(error) if error[:@type]=="ERROR"
          end.compact

          [obj[:base_ref][:@external_id], errors] unless errors.empty?
        end
        Hash[errors]
      end

      def success?
        @success ||= response_hash.all? { |h| h[:status][:@is_success] == 'true' }
      end

      module Support

        def self.included(base)
          base.extend(ClassMethods)
        end

        module ClassMethods
          def upsert_list(records, credentials = {})
            @netsuite_records = records.map { |r| r.kind_of?(self) ? r : self.new(r) }
            response = NetSuite::Actions::UpsertList.call(@netsuite_records, credentials)

            success_records = []

            response.body.each do |attr|
              if (attr[:@internal_id] && (response.errors.empty? || !response.errors.keys.include?(attr[:@external_id])))
                record = @netsuite_records.find{|r| r.external_id == attr[:@external_id].to_i}
                record.instance_variable_set('@internal_id', attr[:@internal_id])
                success_records << record
              end
            end

            [success_records, response.errors]
          end
        end
      end
    end
  end
end
