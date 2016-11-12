$domain_list = ("<fqdn for dynamic update>")
$email = "<email from cloudflare>"
$api_key = "<api key from cloudflare>"

function Get-externalIp() {
try {
$ip = invoke-restmethod 'https://api.ipify.org?format=json' | select -expandproperty IP 
return $ip
} catch {
return $false
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
			return $_
		}
	} else {
		return $false
	}
}

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

$current_ip = Get-externalIp
if($current_ip) {
	foreach($domain in $domain_list) {
	$id = get-cfzoneid $domain
		if(-not(update-CFdns $domain $current_ip $id)){
		create-CFdns $domain A $current_ip $id
		}
	}
}