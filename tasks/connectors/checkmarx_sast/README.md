## Running Checkmarx SAST task

This toolkit brings in data from Checkmarx SAST (https://partners9x.checkmarx.net/cxrestapi/)

To run this task you need the following information from Checkmarx SAST:

1. Username
2. Password
3. Client Secret
4. Client ID (optional)
5. grant_type (optional)
6. scope (optional)

## This Task will use the Checkmarx SAST API to

- Get a list of Projects currently present in the user's Checkmarx SAST account.
- Get a list of Scans in the user's Checkmarx SAST account associated with each Project.
- Generate Report Id on each scan.
- Get a list of scan reports using newly generated above report id.
- Output a json file in the Kenna Data Importer (KDI) format.
- Post the file to Kenna if API Key and Connector ID are provided


Complete list of Options:

| Option | Required | Description | default |
| --- | --- | --- | --- |
| checkmarx_sast_user | true | Checkmarx SAST username | n/a |
| checkmarx_sast_password | true | Checkmarx SAST password | n/a |
| client_id | false | Checkmarx SAST Client ID | n/a |
| client_secret | true | Checkmarx SAST Client Secret | n/a |
| grant_type | false | password | n/a |
| scope | false | access_control_api sast_api | n/a |
| kenna_api_key | false | Kenna API Key for use with connector option | n/a |
| kenna_api_host | false | Kenna API Hostname if not US shared | api.kennasecurity.com |
| kenna_connector_id | false | If set, we'll try to upload to this connector | n/a |
| output_directory | false | If set, will write a file upon completion. Path is relative to #{$basedir} | output/checkmarx_sast |

## Command Line

See the main Toolkit for instructions on running tasks. For this task, if you leave off the Kenna API Key and Kenna Connector ID, the task will create a json file in the default or specified output directory. You can review the file before attempting to upload to the Kenna directly.

Recommended Steps:

For extracting Image vulnerability data:

    toolkit:latest task=checkmarx_sast checkmarx_sast_console=xxx checkmarx_sast_user=xxx checkmarx_sast_password=xxx
    checkmarx_sast_base_api_url=partners9x.checkmarx.net/cxrestapi container_data=false kenna_connector_id=15xxxx
    kenna_api_host=api.sandbox.us.kennasecurity.com kenna_api_key=xxx

For extracting Container vulnerability data in addition to Images:

    toolkit:latest task=checkmarx_sast checkmarx_sast_console=xxx checkmarx_sast_user=xxx checkmarx_sast_password=xxx checkmarx_sast_base_api_url=partners9x.checkmarx.net/cxrestapi container_data=true kenna_connector_id=15xxxx
    kenna_api_host=api.sandbox.us.kennasecurity.com kenna_api_key=xxx
