# frozen_string_literal: true

module Kenna
  module Toolkit
    module BitsightHelpers
      @headers = nil
      @bitsight_api_key = nil
      @company_guid = nil

      def globals(bitsight_api_key)
        @headers = {
          "Authorization" => "Basic #{Base64.strict_encode64(bitsight_api_key)}",
          "accept" => :json,
          "content_type" => :json
        }
        @bitsight_api_key = bitsight_api_key
        my_company
      end

      def get_bitsight_findings_and_create_kdi(bitsight_create_benign_findings, bitsight_benign_finding_grades)
        limit = 100
        page_count = 0

        endpoint = "https://api.bitsighttech.com/ratings/v1/companies/#{@company_guid}/findings?limit=#{limit}"

        while endpoint
          response = http_get(endpoint, @headers)
          result = JSON.parse(response.body)

          # do the right thing with the findings here
          result["results"].lazy.each do |finding|
            add_finding_to_working_kdi(finding, bitsight_create_benign_findings, bitsight_benign_finding_grades)
          end

          # check for more
          endpoint = result["links"]["next"]

          if page_count > 10
            filename = "bitsight_kdi#{Time.now.strftime('%Y%m%dT%H%M')}.json"
            kdi_upload @output_dir, filename, @kenna_connector_id, @kenna_api_host, @kenna_api_key, false, 3, 2
            page_count = 0
          end
          page_count += 1
        end
        filename = "bitsight_kdi#{Time.now.strftime('%Y%m%dT%H%M')}.json"
        kdi_upload @output_dir, filename, @kenna_connector_id, @kenna_api_host, @kenna_api_key, false, 3, 2
      end

      def my_company
        # First get my company
        response = http_get("https://#{@bitsight_api_key}:@api.bitsighttech.com/portfolio", { accept: :json, content_type: :json })
        portfolio = JSON.parse(response.body)
        @company_guid = portfolio["my_company"]["guid"]
      end

      def valid_bitsight_api_key?
        endpoint = "https://api.bitsighttech.com/"

        response = http_get(endpoint, @headers)

        result = JSON.parse(response.body)
        result.key? "disclaimer"
      end

      private

      def add_finding_to_working_kdi(finding, create_benign_findings, benign_finding_grades)
        scanner_id = finding["risk_vector_label"]
        vuln_def_id = (finding["risk_vector_label"]).to_s.tr(" ", "_").tr("-", "_").downcase.strip
        print_debug "Working on finding of type: #{vuln_def_id}"

        # get the grades labled as benign... Default: GOOD

        finding["assets"].each do |a|
          asset_name = a["asset"]
          default_tags = ["Bitsight"]
          default_tags.concat ["bitsight_cat_#{a['category']}".downcase]
          asset_attributes = if a["is_ip"] # TODO: ... keep severity  ]
                               {
                                 "ip_address" => asset_name,
                                 "tags" => default_tags
                               }
                             else
                               {
                                 "hostname" => asset_name,
                                 "tags" => default_tags
                               }
                             end

          ### CHECK OPEN PORTS AND LOOK OFOR VULNERABILITIEIS
          if vuln_def_id == "patching_cadence"

            # grab the CVE
            cve_id = finding["vulnerability_name"]

            if /^CVE-/i.match?(cve_id)
              create_cve_vuln(cve_id, scanner_id, finding, asset_attributes)
            else
              print_error "ERROR! Unknown vulnerability: #{cve_id}!"
              print_debug "#{finding}\n\n"
            end

          ####
          #### OPEN PORTS CAN HAVE BOTH!
          ####
          elsif vuln_def_id == "open_ports"

            # create the sensitive service first
            create_cwe_vuln(vuln_def_id, scanner_id, finding, asset_attributes)

            ###
            ### for each vuln on the service, create a cve
            ###
            finding["details"]["vulnerabilities"].each do |v|
              cve_id = v["name"]
              print_debug "Got CVE: #{cve_id}"
              print_error "ERROR! Unknown vulnerability!" unless /^CVE-/i.match?(cve_id)
              create_cve_vuln(cve_id, scanner_id, finding, asset_attributes)
            end

          ####
          #### NON-CVE CASE, just create the normal finding
          ####
          elsif finding["details"] && finding["details"]["grade"]

            ###
            ### Bitsight sometimes gives us stuff graded positively.
            ### check the options to determine what to do here.
            ###
            print_debug "Got finding #{vuln_def_id} with grade: #{finding['details']['grade']}"

            # if it is labeled as one of our types
            if benign_finding_grades.include?(finding["details"]["grade"])

              print_debug "Adjusting to benign finding due to grade: #{vuln_def_id}"

              # AND we're allowed to create
              if create_benign_findings
                # then create it
                create_cwe_vuln("benign_finding", scanner_id, finding, asset_attributes)
              else # otherwise skip!
                print "Skipping benign finding: #{vuln_def_id}"
              end

            else # we are probably a negative finding, just create it
              create_cwe_vuln(vuln_def_id, scanner_id, finding, asset_attributes)
            end

          else # no grade, so fall back to just creating
            create_cwe_vuln(vuln_def_id, scanner_id, finding, asset_attributes)

          end
        end
      end

      ###
      ### Helper to handle creating a cve vuln
      ###
      def create_cve_vuln(vuln_def_id, scanner_id, finding, asset_attributes)
        # then create each vuln for this asset

        vuln_attributes = {
          "scanner_identifier" => scanner_id,
          "vuln_def_name" => vuln_def_id,
          "scanner_type" => "Bitsight",
          "details" => JSON.pretty_generate(finding),
          "created_at" => finding["first_seen"],
          "last_seen_at" => finding["last_seen"]
        }

        # set the port if it's available
        vuln_attributes["port"] = (finding["details"]["dest_port"]).to_s.to_i if finding["details"]

        # def create_kdi_asset_vuln(asset_id, asset_locator, args)
        create_kdi_asset_vuln(asset_attributes, vuln_attributes)

        vd = {
          "scanner_type" => "Bitsight"
        }

        vd["cve_identifiers"] = vuln_def_id if /^CVE-/i.match?(vuln_def_id)
        vd["name"] = vuln_def_id
        vd["scanner_identifier"] = vuln_def_id
        create_kdi_vuln_def(vd)
      end

      ###
      ### Helper to handle creating a cwe vuln
      ###
      def create_cwe_vuln(vuln_def_id, scanner_id, finding, asset_attributes)
        vd = {
          "scanner_identifier" => vuln_def_id.to_s
        }

        # get our mapped vuln
        fm = Kenna::Toolkit::Data::Mapping::DigiFootprintFindingMapper
        cvd = fm.get_canonical_vuln_details("Bitsight", vd)

        # then create each vuln for this asset
        vuln_attributes = {
          "scanner_identifier" => scanner_id,
          "vuln_def_name" => vuln_def_id,
          "scanner_type" => "Bitsight",
          "details" => JSON.pretty_generate(finding),
          "created_at" => finding["first_seen"],
          "last_seen_at" => finding["last_seen"]
        }

        # set the port if it's available
        vuln_attributes["port"] = (finding["details"]["dest_port"]).to_s.to_i if finding["details"]

        ###
        ### Set Scores based on what was available in the CVD
        ###
        vuln_attributes["vuln_def_name"] = cvd["name"] if cvd["name"]

        vuln_attributes["scanner_score"] = cvd["scanner_score"] if cvd["scanner_score"]

        vuln_attributes["override_score"] = cvd["override_score"] if cvd["override_score"]

        create_kdi_asset_vuln(asset_attributes, vuln_attributes)

        ###
        ### Put them through our mapper
        ###
        create_kdi_vuln_def(cvd)
      end
    end
  end
end