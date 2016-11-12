$domain_to_sync_list = ("<define domain on ad to sync>")
$email = "<email from cloudflare>"
$api_key = "<api key from cloudflare>"

#When set to True deletes extra DNS entries that do not match AD
$strict = $false

function get-cfzoneid() {
Param(
	[string] $DNSname
)
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("Content-Type", "application/json")
$headers.Add("X-Auth-Key", "$api_key")
$headers.Add("X-Auth-Email", "$email")

	if($result = invoke-restmethod -Uri "https://api.cloudflare.com/client/v4/zones/" -Method GET  -headers $headers | select result) {
		if($DNSname.count -ge 1) {
			$dns_tmp = $DNSname.split(".")
			$zone = $dns_Tmp[$dns_tmp.count-2] + "." + $dns_Tmp[$dns_tmp.count-1]
		}
		
		if ($id = $result.result | where { $_.name -match $zone} | select -expandproperty id) {
			return $id
		} else {
			return $false
		}
	}
}

function create-CFdns() {
Param(
	[Parameter(Mandatory=$true)]
	[string] $DNSname,
	[Parameter(Mandatory=$true)]
	[string] $type,
	[Parameter(Mandatory=$true)]
	[string] $ip_update,
	[string] $id="NS"
  )
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("Content-Type", "application/json")
$headers.Add("X-Auth-Key", "$api_key")
$headers.Add("X-Auth-Email", "$email")
$uri_base = "https://api.cloudflare.com/client/v4/zones/" + $id

	if(-not($result = invoke-restmethod -Uri "$uri_base/dns_records" -Method GET  -headers $headers)) {
		return $false
	}

	if(-not ($result.result | where { $_.name -eq "$DNSname"})) {
		try {
			$json = "{""type"":""" + $type +""",
					 ""name"":""" + $dnsname + """,
					 ""content"":""" + $ip_update + """ }"
			$result = invoke-restmethod -Uri "https://api.cloudflare.com/client/v4/zones/$id/dns_records/" -Method POST -Body $json -headers $headers
			return $result.result
		} catch {
			return $false
		}
	} else {
		return $false
	}
}

function update-CFdns() {
Param(
  [Parameter(Mandatory=$true)]
  [string] $DNSname,
  [Parameter(Mandatory=$true)]
  [string] $ip_update,
  [string] $id="NS"
  )

$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("Content-Type", "application/json")
$headers.Add("X-Auth-Key", "$api_key")
$headers.Add("X-Auth-Email", "$email")
$uri_base = "https://api.cloudflare.com/client/v4/zones/" + $id

	if($id -eq "NS") {
	$id = get-cfzoneid $DNSname
	}

	if(-not ($result = invoke-restmethod -Uri "$uri_base/dns_records" -Method GET  -headers $headers)) {
	return $false
	}

	if($data = $result.result | where { $_.name -eq "$DNSname"}) {
		try {
			$data | add-member "content" "$ip_update" -force
			$json = $data | ConvertTo-Json
			$query_url = $uri_base + "/dns_records/" + $data.id
			$result = invoke-restmethod -Uri $query_url -Method PUT -Body $json -headers $headers
			return $result.result
		} catch {
			return $false
		}
	} else {
		return $false
	}
}

function delete-CFdns() {
Param(
  [Parameter(Mandatory=$true)]
  [string] $DNSname,
  [string] $id="NS"
  )

$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("Content-Type", "application/json")
$headers.Add("X-Auth-Key", "$api_key")
$headers.Add("X-Auth-Email", "$email")

	if($id -eq "NS") {
	$id = get-cfzoneid $DNSname
	}
	$uri_base = "https://api.cloudflare.com/client/v4/zones/" + $id
	if(-not ($result = invoke-restmethod -Uri "$uri_base/dns_records" -Method GET  -headers $headers)) {
	return $false
	}

	if($data = $result.result | where { $_.name -eq "$DNSname"}) {
		try {
			$query_url = $uri_base + "/dns_records/" + $data.id
			$result = invoke-restmethod -Uri $query_url -Method DELETE -headers $headers
			return $result.result
		} catch {
			return $false
		}
	} else {
		return $false
	}
}

function get-cfdnslist() {
	Param(
  [Parameter(Mandatory=$true)]
  [string] $id
  )
  
	$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
	$headers.Add("Content-Type", "application/json")
	$headers.Add("X-Auth-Key", "$api_key")
	$headers.Add("X-Auth-Email", "$email")
	$uri_base = "https://api.cloudflare.com/client/v4/zones/" + $id
	$cf_dns_list = invoke-restmethod -Uri "$uri_base/dns_records" -Method GET  -headers $headers
	return $cf_dns_list.result
}

foreach($domain in $domain_to_sync_list) {
$dns_list = Get-DnsServerResourceRecord -ZoneName "$domain" | where {($_.RecordType -eq "A") -or ($_.RecordType -eq "CNAME")}
$id = get-cfzoneid $domain
	foreach($dns_entry in $dns_list) {
		if(($dns_entry.HostName -ne "@") -AND ($dns_entry.HostName -ne "domaindnszones") -AND ($dns_entry.HostName -ne "forestdnszones")) {
			switch($dns_entry.RecordType) {
				"A" {
						if(-not(update-CFdns $dns_entry.Hostname $dns_entry.RecordData.IPv4Address.IpaddressToString $id)){
						create-CFdns $dns_entry.Hostname $dns_entry.RecordType $dns_entry.RecordData.IPv4Address.IpaddressToString $id
						}
				}
				
				"CNAME" {
					if(-not(update-CFdns $dns_entry.Hostname $dns_entry.RecordData.HostnameAlias $id)){
					create-CFdns $dns_entry.Hostname $dns_entry.RecordType $dns_entry.RecordData.HostnameAlias $id
					}
				}
			}
		}	
	}
	
	if($strict) {
	$cf_dns_list = get-cfdnslist $id
		foreach($entry in $cf_dns_list.result.name) {
		$replace_string = "." + $domain
		$verify = $entry -Replace $replace_string
			if($dns_list.Hostname -notcontains "$verify") {
			delete-CFdns $entry $id
			}
		}
	}
}